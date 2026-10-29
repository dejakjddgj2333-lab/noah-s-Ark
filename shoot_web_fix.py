"""复验修复后的页面."""
from playwright.sync_api import sync_playwright

BASE = "http://localhost:5520"
OUT = r"C:\Users\other8080\Videos\project\hk\shots_web"

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    page = b.new_page(viewport={"width": 1600, "height": 900})
    page.goto(f"{BASE}/login")
    page.wait_for_timeout(2000)
    page.fill('input[placeholder="请输入用户名"]', "test01")
    page.fill('input[placeholder="请输入密码"]', "Test123456")
    page.click('button.submit')
    page.wait_for_url("**/overview", timeout=15000)

    for path, name, wait in [
        ("/whale", "fix_whale", 4000),
        ("/funding", "fix_funding", 4000),
        ("/market", "fix_market", 4000),
    ]:
        page.goto(f"{BASE}{path}")
        page.wait_for_timeout(wait)
        page.screenshot(path=f"{OUT}\\{name}.png")
        print(name)

    # 注册页
    page.goto(f"{BASE}/register")
    page.wait_for_timeout(2000)
    page.screenshot(path=f"{OUT}\\fix_register.png")
    print("fix_register")
    b.close()
print("done")
