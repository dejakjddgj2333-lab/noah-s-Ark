"""Diagnostic: serve existing build/web, capture FULL overflow console traces per page."""
import http.server
import os
import socketserver
import threading

from playwright.sync_api import sync_playwright

APP = r"C:\Users\other8080\Videos\project\hk\app"
PORT = 8091


def serve():
    os.chdir(os.path.join(APP, "build", "web"))
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), http.server.SimpleHTTPRequestHandler) as httpd:
        httpd.serve_forever()


t = threading.Thread(target=serve, daemon=True)
t.start()

msgs = []
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 390, "height": 844})
    page.on("console", lambda m: msgs.append(("PAGE?" , m.text)) if ("overflowed" in m.text or "error-causing widget" in m.text or "lib/pages" in m.text) else None)
    page.goto(f"http://127.0.0.1:{PORT}")
    page.wait_for_timeout(15000)
    cur = "terminal"
    print(f"===== PAGE {cur} =====")
    navs = [("market", (78, 78)), ("duowei", (143, 78)), ("liquidation", (221, 78)),
            ("whale", (299, 78)), ("funding", (372, 78))]
    idx = 0
    # print initial batch
    for name, pos in navs:
        # drain messages for current page
        while idx < len(msgs):
            print(msgs[idx][1])
            idx += 1
        print(f"===== PAGE {name} =====")
        page.mouse.click(pos[0], pos[1])
        page.wait_for_timeout(2000)
    while idx < len(msgs):
        print(msgs[idx][1])
        idx += 1
    browser.close()
