"""Web 终端页面截图验证."""
from playwright.sync_api import sync_playwright

BASE = "http://localhost:5520"
OUT = r"C:\Users\other8080\Videos\project\hk\shots_web"

import os
os.makedirs(OUT, exist_ok=True)

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    page = b.new_page(viewport={"width": 1600, "height": 900})

    # 登录页
    page.goto(f"{BASE}/login")
    page.wait_for_timeout(2500)
    page.screenshot(path=f"{OUT}\\01_login.png")
    print("01_login")

    # 登录
    page.fill('input[placeholder="请输入用户名"]', "test01")
    page.fill('input[placeholder="请输入密码"]', "Test123456")
    page.click('button.submit')
    page.wait_for_url("**/overview", timeout=15000)
    page.wait_for_timeout(4000)
    page.screenshot(path=f"{OUT}\\02_overview.png")
    print("02_overview")

    pages = [
        ("/market", "03_market"),
        ("/market/BTC-USDT", "04_market_detail"),
        ("/multi", "05_multi"),
        ("/liquidation", "06_liquidation"),
        ("/whale", "07_whale"),
        ("/funding", "08_funding"),
        ("/news", "09_news"),
        ("/chat", "10_chat"),
        ("/assets", "11_assets"),
        ("/profile", "12_profile"),
    ]
    for path, name in pages:
        page.goto(f"{BASE}{path}")
        page.wait_for_timeout(3500)
        page.screenshot(path=f"{OUT}\\{name}.png")
        print(name)

    # 资讯详情: 从列表第一条进
    page.goto(f"{BASE}/news")
    page.wait_for_timeout(3000)
    row = page.locator(".news-row").first
    if row.count():
        row.click()
        page.wait_for_timeout(2500)
        page.screenshot(path=f"{OUT}\\13_news_detail.png")
        print("13_news_detail")

    b.close()
print("done")
