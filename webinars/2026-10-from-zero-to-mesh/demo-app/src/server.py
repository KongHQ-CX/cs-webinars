"""Demo app: reports its zone and fails a set percent of requests.

Two listeners:
- service port (default 8080, all interfaces): GET / and GET /healthz.
- admin port (default 9911, 127.0.0.1 only, not configurable; 9901 is the Envoy admin default in the sidecar): GET and POST /admin/failure.
  Only kubectl exec and kubectl port-forward reach it. No other pod can.

Standard library only, so the image has no packages to pin or patch.
"""
import json
import os
import random
import signal
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ADMIN_BIND = "127.0.0.1"


class Config:
    def __init__(self, zone, service, allowed_origin, port=8080, admin_port=9911, bind="0.0.0.0"):
        self.zone = zone
        self.service = service
        self.allowed_origin = allowed_origin
        self.port = port
        self.admin_port = admin_port
        self.bind = bind

    @classmethod
    def from_env(cls, env):
        origin = env.get("ALLOWED_ORIGIN", "")
        if not origin or origin == "*":
            raise ValueError("ALLOWED_ORIGIN must name the request page origin, not empty and not *")
        return cls(
            zone=env.get("ZONE", "unknown"),
            service=env.get("SERVICE_NAME", "demo-app"),
            allowed_origin=origin,
            port=int(env.get("PORT", "8080")),
            admin_port=int(env.get("ADMIN_PORT", "9911")),
        )


class Failure:
    """Holds the failure percent (0 to 100) and decides per request."""

    def __init__(self, rng=random.random):
        self._percent = 0
        self._lock = threading.Lock()
        self._rng = rng

    def get(self):
        with self._lock:
            return self._percent

    def set(self, percent):
        with self._lock:
            self._percent = percent

    def should_fail(self):
        p = self.get()
        return p > 0 and self._rng() * 100 < p


def valid_percent(value):
    """True only for a real integer from 0 to 100. Bool, float and string are rejected."""
    return type(value) is int and 0 <= value <= 100


def _service_handler(app):
    cfg = app.cfg

    class Handler(BaseHTTPRequestHandler):
        server_version = "demo-app"
        sys_version = ""

        def version_string(self):
            return self.server_version  # the base class appends a space and sys_version

        def log_message(self, format, *args):
            pass

        def _send(self, status, payload):
            body = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", cfg.allowed_origin)
            self.send_header("Vary", "Origin")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path == "/healthz":
                self._send(200, {"status": 200})
            elif path == "/":
                status = 503 if app.failure.should_fail() else 200
                self._send(status, {"service": cfg.service, "zone": cfg.zone, "status": status})
            else:
                self._send(404, {"status": 404})

        def do_POST(self):
            self._send(404, {"status": 404})

        do_PUT = do_DELETE = do_PATCH = do_POST

    return Handler


def _admin_handler(app):
    class Handler(BaseHTTPRequestHandler):
        server_version = "demo-app"
        sys_version = ""

        def version_string(self):
            return self.server_version

        def log_message(self, format, *args):
            pass

        def _send(self, status, payload):
            body = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/admin/failure":
                self._send(200, {"percent": app.failure.get()})
            else:
                self._send(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/admin/failure":
                self._send(404, {"error": "not found"})
                return
            # A browser page cannot set a JSON type without a CORS preflight, and every browser request
            # carries Origin. Refusing both keeps a web page from driving the switch through port-forward.
            if self.headers.get("Origin") is not None:
                self._send(403, {"error": "browser requests are refused"})
                return
            ctype = self.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
            if ctype != "application/json":
                self._send(415, {"error": "Content-Type must be application/json"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                doc = json.loads(self.rfile.read(length) or b"null")
            except (ValueError, UnicodeDecodeError):
                self._send(400, {"error": "body must be JSON"})
                return
            value = doc.get("percent") if isinstance(doc, dict) else None
            if not valid_percent(value):
                self._send(400, {"error": "percent must be an integer from 0 to 100"})
                return
            app.failure.set(value)
            self._send(200, {"percent": app.failure.get()})

    return Handler


class App:
    def __init__(self, cfg, rng=random.random):
        self.cfg = cfg
        self.failure = Failure(rng)
        self.server = ThreadingHTTPServer((cfg.bind, cfg.port), _service_handler(self))
        self.admin_server = ThreadingHTTPServer((ADMIN_BIND, cfg.admin_port), _admin_handler(self))
        self.server.daemon_threads = True
        self.admin_server.daemon_threads = True
        self.port = self.server.server_address[1]
        self.admin_port = self.admin_server.server_address[1]
        self._threads = []
        self._stop_event = threading.Event()

    def start(self):
        for s in (self.server, self.admin_server):
            t = threading.Thread(target=s.serve_forever, daemon=True)
            t.start()
            self._threads.append(t)

    def stop(self):
        for s in (self.server, self.admin_server):
            s.shutdown()
            s.server_close()

    def request_stop(self):
        self._stop_event.set()

    def serve_forever(self):
        """Serve until request_stop() is called (the signal handlers do this), then shut down."""
        self.start()
        while not self._stop_event.wait(0.5):
            pass
        self.stop()


def main():
    app = App(Config.from_env(os.environ))
    print(f"zone={app.cfg.zone} service port={app.port} admin 127.0.0.1:{app.admin_port}", flush=True)
    # PID 1 in a container gets no default SIGTERM action, so without a handler a pod delete waits out
    # the 30 second grace period and then SIGKILLs.
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda _signo, _frame: app.request_stop())
    app.serve_forever()


if __name__ == "__main__":
    main()
