#!/usr/bin/env python3
"""Simple webhook listener — prints every incoming request body as formatted JSON."""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
from datetime import datetime

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765


class Handler(BaseHTTPRequestHandler):
    def _timestamp(self):
        return datetime.now().strftime("%H:%M:%S.%f")[:-3]

    def _set_cors_headers(self):
        if self.path == "/cors-hook" or self.path.startswith("/cors-hook?"):
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE, PATCH")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, User-Agent, Authorization")

    def do_OPTIONS(self):
        self.send_response(200)
        self._set_cors_headers()
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        try:
            body = json.loads(raw)
            pretty = json.dumps(body, indent=2)
        except Exception:
            pretty = raw.decode(errors="replace")

        print(f"\n[{self._timestamp()}] POST {self.path}")
        print(f"  User-Agent: {self.headers.get('User-Agent', '-')}")
        print(pretty)

        self.send_response(200)
        self._set_cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        flat = {k: v[0] if len(v) == 1 else v for k, v in params.items()}

        print(f"\n[{self._timestamp()}] GET {parsed.path}")
        print(f"  User-Agent: {self.headers.get('User-Agent', '-')}")
        if flat:
            print(json.dumps(flat, indent=2))

        self.send_response(200)
        self._set_cors_headers()
        self.end_headers()

    def log_message(self, *_):
        pass  # suppress default access log


print(f"Listening on http://0.0.0.0:{PORT}  (Ctrl-C to stop)")
HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
