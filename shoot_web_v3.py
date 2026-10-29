"""v3 高保真还原后全页面复拍."""
from playwright.sync_api import sync_playwright

BASE = "http://localhost:5520"
OUT = r"C:\Users\other8080\Videos\project\hk\shots_web"

PAGES = [
    ("/overview", "v3_overview"),
    ("/market", "v3_market"),
    ("/market/BTC-USDT", "v3_market_detail"),
    ("/multi", "v3_multi"),
    ("/liquidation", "v3_liquidation"),
    ("/whale", "v3_whale"),
    ("/funding", "v3_funding"),
    ("/news", "v3_news"),
    ("/chat", "v3_chat"),
    ("/assets", "v3_assets"),
    ("/profile", "v3_profile"),
]

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    ctx = b.new_context(viewport={"width": 1600, "height": 900})
    page = ctx.new_page()
    page.goto(f"{BASE}/login")
    page.wait_for_timeout(2500)
    page.screenshot(path=f"{OUT}\\v3_login.png")
    print("v3_login")
    page.goto(f"{BASE}/register")
    page.wait_for_timeout(1500)
    page.screenshot(path=f"{OUT}\\v3_register.png")
    print("v3_register")
    page.goto(f"{BASE}/login")
    page.wait_for_timeout(1500)
    page.fill('input[placeholder="name@institution.com 或 ID"]', "test01")
    page.fill('input[placeholder="••••••••••••"]', "Test123456")
    page.click('button[type="submit"]')
    page.wait_for_url("**/overview", timeout=15000)
    page.wait_for_timeout(5000)
    for path, name in PAGES:
        page.goto(f"{BASE}{path}")
        page.wait_for_timeout(5000)
        page.screenshot(path=f"{OUT}\\{name}.png")
        print(name)
    # 资讯详情: 从列表点第一条
    page.goto(f"{BASE}/news")
    page.wait_for_timeout(3000)
    page.locator("main a, main .cursor-pointer").first.click()
    page.wait_for_timeout(2500)
    page.screenshot(path=f"{OUT}\\v3_news_detail.png")
    print("v3_news_detail")
    b.close()
print("done")
