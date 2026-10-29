"""v4 仅复拍 chat / liquidation 两张修复验证图."""
from playwright.sync_api import sync_playwright

BASE = "http://localhost:5520"
OUT = r"C:\Users\other8080\Videos\project\hk\shots_web"

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    ctx = b.new_context(viewport={"width": 1600, "height": 900})
    page = ctx.new_page()
    page.goto(f"{BASE}/login")
    page.wait_for_timeout(2000)
    page.fill('input[placeholder="name@institution.com 或 ID"]', "test01")
    page.fill('input[placeholder="••••••••••••"]', "Test123456")
    page.click('button[type="submit"]')
    page.wait_for_url("**/overview", timeout=15000)
    page.goto(f"{BASE}/chat")
    page.wait_for_timeout(6000)
    page.screenshot(path=f"{OUT}\\v4_chat.png")
    print("v4_chat")
    page.goto(f"{BASE}/liquidation")
    page.wait_for_timeout(6000)
    page.screenshot(path=f"{OUT}\\v4_liquidation.png")
    print("v4_liquidation")
    b.close()
print("done")
