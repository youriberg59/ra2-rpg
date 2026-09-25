import hashlib
import http.server
import os
import socketserver
import zipfile
from pathlib import Path

SOURCE = Path("/original-game")
CACHE = Path("/resource-cache")
ARCHIVE = CACHE / "original-game-pack.zip"
SIGFILE = CACHE / "original-game-pack.sig"
PORT = 8090

CACHE.mkdir(parents=True, exist_ok=True)

def source_signature():
    h = hashlib.sha256()
    for p in sorted(SOURCE.iterdir(), key=lambda x: x.name.lower()):
        if not p.is_file():
            continue
        st = p.stat()
        h.update(p.name.encode("utf-8", "surrogateescape"))
        h.update(str(st.st_size).encode())
        h.update(str(st.st_mtime_ns).encode())
    return h.hexdigest()

def build_if_needed():
    sig = source_signature()
    old = SIGFILE.read_text().strip() if SIGFILE.exists() else ""
    if ARCHIVE.exists() and old == sig:
        print("Using cached RA2 ZIP archive.", flush=True)
        return

    print("Building centralized RA2 ZIP archive...", flush=True)
    tmp = CACHE / "original-game-pack.zip.tmp"
    if tmp.exists():
        tmp.unlink()

    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as zf:
        for p in sorted(SOURCE.iterdir(), key=lambda x: x.name.lower()):
            if p.is_file():
                zf.write(p, arcname=p.name)

    tmp.replace(ARCHIVE)
    SIGFILE.write_text(sig)
    print(f"RA2 ZIP ready: {ARCHIVE} ({ARCHIVE.stat().st_size} bytes)", flush=True)

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
build_if_needed()

with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), Handler) as httpd:
    httpd.daemon_threads = True
    print(f"RA2 asset server listening on 0.0.0.0:{PORT}", flush=True)
    httpd.serve_forever()
