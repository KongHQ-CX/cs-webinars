"""Tiny client for the admin listener. Runs inside the pod through kubectl exec.

    python3 /app/adminctl.py get
    python3 /app/adminctl.py set 50

Prints the percent the server reports. Exits non-zero on any error.
"""
import json
import os
import sys
import urllib.request

URL = "http://127.0.0.1:%s/admin/failure" % os.environ.get("ADMIN_PORT", "9911")


def main(argv):
    if argv[:1] == ["get"] and len(argv) == 1:
        req = urllib.request.Request(URL)
    elif argv[:1] == ["set"] and len(argv) == 2:
        try:
            percent = int(argv[1])
        except ValueError:
            sys.exit("percent must be an integer")
        req = urllib.request.Request(URL, data=json.dumps({"percent": percent}).encode(), method="POST",
                                     headers={"Content-Type": "application/json"})
    else:
        sys.exit("usage: adminctl.py get | set PERCENT")
    with urllib.request.urlopen(req, timeout=5) as resp:
        print(json.load(resp)["percent"])


if __name__ == "__main__":
    main(sys.argv[1:])
