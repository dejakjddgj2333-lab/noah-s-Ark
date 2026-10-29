"""Screenshot all admin pages. Serve dist already running on 5517."""
import os
from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:5517"
OUT = r"C:\Users\other8080\Videos\project\hk\shots_admin"
os.makedirs(OUT, exist_ok=True)

PAGES = [
    ("/dashboard", "01_dashboard"),
    ("/users", "02_users"),
    ("/deposit/records", "03_deposit_records"),
    ("/deposit/addresses", "04_deposit_addresses"),
    ("/sweep", "05_sweep"),
    ("/withdrawal/list", "06_withdrawal"),
    ("/product/list", "07_product"),
    ("/order/list", "08_order"),
    ("/reports", "09_reports"),
    ("/admins", "10_admins"),
    ("/roles", "11_roles"),
    ("/legal", "12_legal"),
    ("/features", "13_features"),
    ("/config", "14_config"),
]

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    page = b.new_page(viewport={"width": 1600, "height": 900})
    page.goto(f"{BASE}/login")
    page.wait_for_timeout(2500)
    page.screenshot(path=f"{OUT}\\00_login.png")

    page.fill('input[placeholder="用户名"]', "admin")
    page.fill('input[placeholder="密码"]', "BpAbbk80li0IStD1")
    page.click('button.login-btn')
    page.wait_for_url("**/dashboard", timeout=15000)
    page.wait_for_timeout(3000)

    for path, name in PAGES:
        page.goto(f"{BASE}{path}")
        page.wait_for_timeout(3500)
        page.screenshot(path=f"{OUT}\\{name}.png")
        print("shot", name)

    b.close()
print("done")
