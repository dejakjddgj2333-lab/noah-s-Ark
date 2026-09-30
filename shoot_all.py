"""Serve build/web and screenshot all pages."""
import http.server
import os
import socketserver
import threading

from playwright.sync_api import sync_playwright

APP = r"C:\Users\other8080\Videos\project\hk\app"
OUT = r"C:\Users\other8080\Videos\project\hk\shots2"
PORT = 8089

def serve():
    os.chdir(os.path.join(APP, "build", "web"))
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), http.server.SimpleHTTPRequestHandler) as h:
        h.serve_forever()

threading.Thread(target=serve, daemon=True).start()
os.makedirs(OUT, exist_ok=True)

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    page = b.new_page(viewport={"width": 390, "height": 844})
    page.goto(f"http://127.0.0.1:{PORT}")
    page.wait_for_timeout(15000)
    page.screenshot(path=f"{OUT}\\t1_terminal.png", full_page=False)
    navs = [("market", (78, 78)), ("duowei", (143, 78)), ("liquidation", (221, 78)),
            ("whale", (299, 78)), ("funding", (372, 78)), ("news", (146, 823)),
            ("chat", (244, 823)), ("assets", (341, 823))]
    for name, (x, y) in navs:
        page.mouse.click(x, y)
        page.wait_for_timeout(2000)
        page.screenshot(path=f"{OUT}\\{name}.png")
    b.close()
print("done")
