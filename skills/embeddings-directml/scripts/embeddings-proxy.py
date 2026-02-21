import os
import json
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("EMBEDDINGS_PROXY_HOST", "127.0.0.1")
PORT = int(os.environ.get("EMBEDDINGS_PROXY_PORT", "8124"))
WIN_PORT = int(os.environ.get("EMBEDDINGS_WINDOWS_PORT", "8124"))
FORWARD_TIMEOUT_SECONDS = float(os.environ.get("EMBEDDINGS_PROXY_FORWARD_TIMEOUT_SECONDS", "120"))


def resolve_windows_host() -> str:
    env = os.environ.get("EMBEDDINGS_WINDOWS_HOST")
    if env:
        return env
    # Prefer default gateway from ip route (more reliable in WSL)
    try:
        import subprocess

        out = subprocess.check_output(["/usr/sbin/ip", "route"], text=True)
        for line in out.splitlines():
            if line.startswith("default "):
                return line.split()[2]
    except Exception:
        pass
    # Fallback to resolv.conf nameserver
    try:
        with open("/etc/resolv.conf", "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("nameserver"):
                    return line.split()[1].strip()
    except Exception:
        pass
    return "127.0.0.1"


class ProxyHandler(BaseHTTPRequestHandler):
    def _forward(self):
        win_host = resolve_windows_host()
        target = f"http://{win_host}:{WIN_PORT}{self.path}"
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length > 0 else None

        req = urllib.request.Request(target, data=body, method=self.command)
        for key, value in self.headers.items():
            k = key.lower()
            if k in ("host", "content-length"):
                continue
            req.add_header(key, value)

        try:
            with urllib.request.urlopen(req, timeout=FORWARD_TIMEOUT_SECONDS) as resp:
                data = resp.read()
                self.send_response(resp.status)
                for header, value in resp.getheaders():
                    if header.lower() == "transfer-encoding":
                        continue
                    self.send_header(header, value)
                self.end_headers()
                if data:
                    self.wfile.write(data)
        except urllib.error.HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            for header, value in e.headers.items():
                if header.lower() == "transfer-encoding":
                    continue
                self.send_header(header, value)
            self.end_headers()
            if data:
                self.wfile.write(data)
        except Exception as e:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode("utf-8"))

    def do_GET(self):
        self._forward()

    def do_POST(self):
        self._forward()

    def log_message(self, fmt, *args):
        # quiet
        return


def main():
    server = ThreadingHTTPServer((HOST, PORT), ProxyHandler)
    print(f"Embeddings proxy listening on http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
