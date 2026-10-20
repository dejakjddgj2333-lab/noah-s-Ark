"""Retake user profile drawer screenshot."""
from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:5517"
OUT = r"C:\Users\other8080\Videos\project\hk\shots_admin"

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    page = b.new_page(viewport={"width": 1600, "height": 900})
    page.goto(f"{BASE}/login")
    page.wait_for_timeout(2000)
    page.fill('input[placeholder="用户名"]', "admin")
    page.fill('input[placeholder="密码"]', "BpAbbk80li0IStD1")
    page.click('button.login-btn')
    page.wait_for_url("**/dashboard", timeout=15000)

    page.goto(f"{BASE}/users")
    page.wait_for_timeout(3000)
    page.locator('button:has-text("档案")').first.click()
    page.wait_for_timeout(2500)
    page.screenshot(path=f"{OUT}\\d_user_profile.png")
    print("shot d_user_profile")
    b.close()
