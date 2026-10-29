# demo-app

A small Python service that reports its zone and fails a set share of requests.

## What it does

- `GET /` on port 8080 returns `{"service": "demo-app", "zone": "<ZONE>", "status": 200}`. With the failure switch on, a share of calls return 503 with the same body shape.
- `GET /healthz` on port 8080 always returns 200. It is for the readiness probe.
- The admin listener (`GET` and `POST /admin/failure`, body `{"percent": 0..100}`) binds to `127.0.0.1:9911`. It is not in the Service and not in the gateway route. `kubectl exec` and `kubectl port-forward` reach it. No other pod can. Port 9911 avoids 9901, the default Envoy admin port in the sidecar that shares the pod network namespace.
- A percent that is not an integer from 0 to 100 returns 400. A POST without `Content-Type: application/json` returns 415. A POST with an `Origin` header (any browser request) returns 403.
- SIGTERM and SIGINT stop both listeners, so a pod delete finishes in seconds.
- Every response, including 503, carries `Access-Control-Allow-Origin` set to the `ALLOWED_ORIGIN` value. No wildcard. The app refuses to start with `*` or an empty value.

## Environment

| Variable | Meaning |
|---|---|
| `ZONE` | Zone name echoed in responses. Set per cluster by `stages/02-app/apply.sh`. |
| `ALLOWED_ORIGIN` | The one browser origin allowed to read responses, `http://localhost:8099`. The manifest sets it. Leave it unless a browser page of your own calls the gateway. |
| `SERVICE_NAME` | Defaults to `demo-app`. |
| `PORT`, `ADMIN_PORT` | 8080 and 9911. |

## The failure switch

The switch lives in the app. Run it once per cluster context (`ready-1`, then `ready-2`):

```
code/bin/set-failure.sh 50
code/bin/set-failure.sh 0
```

The script sets every demo pod in the active context and reads each pod back. It exits non-zero if any pod differs. `code/stages/02-app/verify-switch.sh` checks both zones end to end.


## Image

The Dockerfile has no default `BASE`, because no digest can be verified offline and a tag can move. Pass a python slim image pinned by digest, read from the registry: `--build-arg BASE=python:3.13.5-slim@sha256:<digest>`. A build without `BASE` stops with a blank base name. Build, push and digest-pin the demo image, then export `DEMO_IMAGE` (name@sha256:<64 hex digits>) from your shell environment. The image path never appears in a file in this folder. Stage 02 `apply.sh` refuses an image that does not end in a full digest, and refuses a kubectl context that does not start with `ready-`.
