"""v5 验证新交互: 概览周期切换、铃铛下拉、行情详情精度、聊天工具."""
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
    page.wait_for_timeout(5000)

    # 1. 概览: 点 4H 周期
    page.click("button:has-text('4H') >> nth=0")
    page.wait_for_timeout(2500)
    page.screenshot(path=f"{OUT}\\v5_overview_4h.png")
    print("v5_overview_4h")

    # 2. 铃铛下拉
    page.click('button[title="通知待办"]')
    page.wait_for_timeout(2500)
    page.screenshot(path=f"{OUT}\\v5_bell.png")
    print("v5_bell")

    # 3. 行情详情: 精度切换 + 自选
    page.goto(f"{BASE}/market/BTC-USDT")
    page.wait_for_timeout(5000)
    page.click("button:has-text('1.0')")
    page.wait_for_timeout(1200)
    page.screenshot(path=f"{OUT}\\v5_detail_precision.png")
    print("v5_detail_precision")

    # 4. 聊天: 表情面板
    page.goto(f"{BASE}/chat")
    page.wait_for_timeout(5000)
    page.click('button[title="插入表情与信号"]')
    page.wait_for_timeout(800)
    page.screenshot(path=f"{OUT}\\v5_chat_emoji.png")
    print("v5_chat_emoji")
    b.close()
print("done")
