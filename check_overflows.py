"""Build web, serve statically on 8088, collect overflow errors. Self-contained check loop."""
import http.server
import os
import socketserver
import subprocess
import threading

from playwright.sync_api import sync_playwright

APP = r"C:\Users\other8080\Videos\project\hk\app"
PORT = 8088
raw = []

def serve():
    os.chdir(os.path.join(APP, "build", "web"))
    handler = http.server.SimpleHTTPRequestHandler
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), handler) as httpd:
        httpd.serve_forever()

def main():
    build = subprocess.run(
        "flutter build web --debug",
        cwd=APP, capture_output=True, text=True, shell=True)
    if build.returncode != 0:
        print("BUILD FAILED")
        print(build.stderr[-2000:])
        return 1

    t = threading.Thread(target=serve, daemon=True)
    t.start()

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 390, "height": 844})
        page.on("console", lambda m: raw.append(m.text) if (
            "overflow" in m.text.lower() or "EXCEPTION" in m.text) else None)
        page.goto(f"http://127.0.0.1:{PORT}")
        page.wait_for_timeout(15000)
        raw.append("--- PAGE terminal ---")
        navs = [
            ("market", (78, 78)), ("duowei", (143, 78)),
            ("liquidation", (221, 78)), ("whale", (299, 78)),
            ("funding", (372, 78)), ("news", (146, 823)),
            ("chat", (244, 823)), ("assets", (341, 823)),
        ]
        for name, pos in navs:
            raw.append(f"--- PAGE {name} ---")
            page.mouse.click(pos[0], pos[1])
            page.wait_for_timeout(2000)
        browser.close()

    overflows = [l for l in raw if "overflow" in l.lower() or "PAGE" in l or "file:///" in l]
    for l in overflows:
        print(l[:220])
    n = sum(1 for l in raw if "overflowed" in l)
    print(f"OVERFLOW_COUNT={n}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
