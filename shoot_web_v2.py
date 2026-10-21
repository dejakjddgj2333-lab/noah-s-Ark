"""v2 复拍升级后的页面."""
from playwright.sync_api import sync_playwright

BASE = "http://localhost:5520"
OUT = r"C:\Users\other8080\Videos\project\hk\shots_web"

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    page = b.new_page(viewport={"width": 1600, "height": 900})
    page.goto(f"{BASE}/login")
    page.wait_for_timeout(2500)
    page.screenshot(path=f"{OUT}\\v2_login.png")
    print("v2_login")
    page.fill('input[placeholder="请输入用户名"]', "test01")
    page.fill('input[placeholder="请输入密码"]', "Test123456")
    page.click("button.submit")
    page.wait_for_url("**/overview", timeout=15000)
    page.wait_for_timeout(4500)
    page.screenshot(path=f"{OUT}\\v2_overview.png")
    print("v2_overview")
    for path, name in [("/liquidation", "v2_liquidation"), ("/funding", "v2_funding")]:
        page.goto(f"{BASE}{path}")
        page.wait_for_timeout(5000)
        page.screenshot(path=f"{OUT}\\{name}.png")
        print(name)
    page.goto(f"{BASE}/news")
    page.wait_for_timeout(3000)
    page.locator(".news-row").first.click()
    page.wait_for_timeout(2500)
    page.screenshot(path=f"{OUT}\\v2_news_detail.png")
    print("v2_news_detail")
    b.close()
print("done")
