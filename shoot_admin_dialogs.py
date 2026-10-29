"""Screenshot key dialogs in admin."""
import os
from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:5517"
OUT = r"C:\Users\other8080\Videos\project\hk\shots_admin"

def snap_dialog(page, name):
    page.wait_for_timeout(1200)
    page.screenshot(path=f"{OUT}\\{name}.png")
    print("shot", name)
    page.keyboard.press("Escape")
    page.wait_for_timeout(600)

with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    page = b.new_page(viewport={"width": 1600, "height": 900})
    page.goto(f"{BASE}/login")
    page.wait_for_timeout(2000)
    page.fill('input[placeholder="用户名"]', "admin")
    page.fill('input[placeholder="密码"]', "BpAbbk80li0IStD1")
    page.click('button.login-btn')
    page.wait_for_url("**/dashboard", timeout=15000)
    page.wait_for_timeout(2000)

    def try_click(texts):
        for t in texts:
            try:
                page.click(f"text={t}", timeout=2500)
                return True
            except Exception:
                continue
        return False

    # 新建产品
    try:
        page.goto(f"{BASE}/product/list"); page.wait_for_timeout(3000)
        if try_click(["新建产品"]):
            snap_dialog(page, "d_product_new")
    except Exception as e:
        print("skip product:", e)

    # 用户: 调账 / 档案
    try:
        page.goto(f"{BASE}/users"); page.wait_for_timeout(3000)
        if try_click(["调账"]):
            snap_dialog(page, "d_user_adjust")
        if try_click(["档案"]):
            snap_dialog(page, "d_user_profile")
    except Exception as e:
        print("skip users:", e)

    # 新建角色
    try:
        page.goto(f"{BASE}/roles"); page.wait_for_timeout(3000)
        if try_click(["新建角色"]):
            snap_dialog(page, "d_role_new")
    except Exception as e:
        print("skip role:", e)

    # 新建管理员
    try:
        page.goto(f"{BASE}/admins"); page.wait_for_timeout(3000)
        if try_click(["新建管理员", "新增管理员"]):
            snap_dialog(page, "d_admin_new")
    except Exception as e:
        print("skip admin:", e)

    # 充值地址池: 导入/新增
    try:
        page.goto(f"{BASE}/deposit/addresses"); page.wait_for_timeout(3000)
        if try_click(["导入地址", "新增地址", "批量导入"]):
            snap_dialog(page, "d_address_import")
    except Exception as e:
        print("skip address:", e)

    # 协议管理: 编辑
    try:
        page.goto(f"{BASE}/legal"); page.wait_for_timeout(3000)
        if try_click(["编辑"]):
            snap_dialog(page, "d_legal_edit")
    except Exception as e:
        print("skip legal:", e)

    b.close()
print("done")
