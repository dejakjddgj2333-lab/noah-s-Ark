# 验证 K线 tooltip 时间显示: 登录 -> BTC 详情 -> 悬停 -> 截图+抓 tooltip 文本
import re
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 1600, 'height': 900})
    page.goto('http://localhost:5520/login')
    page.wait_for_load_state('networkidle')

    page.fill('input[placeholder="请输入账号"]', 'test01')
    page.fill('input[type="password"]', 'Test123456')
    page.click('button[type="submit"]')
    page.wait_for_url('**/overview', timeout=15000)

    page.goto('http://localhost:5520/market/BTC-USDT')
    page.wait_for_load_state('networkidle')
    page.wait_for_selector('canvas', timeout=15000)
    page.wait_for_timeout(3000)  # 等蜡烛数据到位

    # 在图表区中心悬停, 触发 crosshair
    box = page.locator('canvas').first.bounding_box()
    cx = box['x'] + box['width'] * 0.92
    cy = box['y'] + box['height'] * 0.4
    for i in range(6):
        page.mouse.move(cx - 30 + i * 12, cy)
        page.wait_for_timeout(80)
    page.wait_for_timeout(500)

    # 抓 tooltip 文本 (含 开/高/低/收 的悬浮层)
    tips = page.evaluate('''() => {
      const out = []
      document.querySelectorAll('div').forEach(d => {
        const t = (d.innerText || '').trim()
        if (t.includes('开') && t.includes('收') && t.length < 200) out.push(t)
      })
      return out
    }''')
    print('TOOLTIP_TEXTS:')
    for t in tips:
        print(repr(t))

    page.screenshot(path=r'C:\Users\other8080\Videos\project\hk\_scratch\kline_tooltip.png')
    browser.close()
print('DONE')
