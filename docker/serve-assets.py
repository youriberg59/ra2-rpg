import http.server
import os
import socketserver
from pathlib import Path

SOURCE = Path("/original-game")
CACHE = Path("/resource-cache")
PORT = 8090

CACHE.mkdir(parents=True, exist_ok=True)
FILES_DIR = CACHE / "files"

try:
    if FILES_DIR.is_symlink() or FILES_DIR.exists():
        if FILES_DIR.is_symlink():
            FILES_DIR.unlink()
        elif FILES_DIR.is_dir():
            os.rmdir(FILES_DIR)
    os.symlink(SOURCE, FILES_DIR, target_is_directory=True)
except OSError as e:
    print(f"Warning: could not refresh files symlink: {e}", flush=True)

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Cache-Control", "public, max-age=3600")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def log_message(self, fmt, *args):
        print("[ra2-assets] " + (fmt % args), flush=True)

os.chdir(CACHE)

print("Serving original RA2 files directly from /files/...", flush=True)
with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), Handler) as httpd:
    httpd.daemon_threads = True
    print(f"RA2 asset server listening on 0.0.0.0:{PORT}", flush=True)
    httpd.serve_forever()
