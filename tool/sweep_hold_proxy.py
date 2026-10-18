#!/usr/bin/env python3
"""A localhost PUT proxy that HOLDS each upload before passing it on (F-125 S4).

    python3 tool/sweep_hold_proxy.py <port> <log-file>

`PUT /?to=<url>&ms=<n>` reads the whole body, waits n ms, PUTs the same body
(and Content-Type) to <url>, and answers with that answer's status and body.
So an upload the app hands off just before it leaves the foreground FINISHES
while the app is in the background — what the device test
(integration_test/sweep_background_test.dart) needs to prove that a
background upload completes, and is recorded, with the app away.

`GET /log` answers the JSON lines written to <log-file>: one per upload, with
when it arrived, when it was answered (ms since 1970) and the status passed
back.

<url> must be localhost (the storage emulator): this never sends bytes
anywhere else.
"""
import http.server
import json
import sys
import threading
import time
import urllib.parse
import urllib.request

PORT = int(sys.argv[1])
LOG = sys.argv[2]
_lock = threading.Lock()


def _now_ms():
    return round(time.time() * 1000)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path != "/log":
            self.send_error(404)
            return
        try:
            body = open(LOG, "rb").read()
        except FileNotFoundError:
            body = b""
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_PUT(self):
        arrived = _now_ms()
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        to = q.get("to", [""])[0]
        ms = int(q.get("ms", ["0"])[0])
        host = urllib.parse.urlparse(to).hostname
        if host not in ("localhost", "127.0.0.1"):
            self.send_error(400, "not localhost")
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        time.sleep(ms / 1000)
        req = urllib.request.Request(to, data=body, method="PUT")
        req.add_header("Content-Type", self.headers.get("Content-Type") or "application/octet-stream")
        try:
            with urllib.request.urlopen(req) as r:
                status, answer = r.status, r.read()
        except urllib.error.HTTPError as e:
            status, answer = e.code, e.read()
        self.send_response(status)
        self.send_header("Content-Length", str(len(answer)))
        self.end_headers()
        self.wfile.write(answer)
        answered = _now_ms()
        with _lock, open(LOG, "a") as f:
            f.write(json.dumps({"arrivedMs": arrived, "answeredMs": answered,
                                "status": status, "bytes": len(body), "heldMs": ms}) + "\n")


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
