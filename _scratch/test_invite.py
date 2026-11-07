from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    errors = []
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.goto('file:///C:/Users/other8080/Videos/project/hk/server/static/invite.html')
    page.wait_for_load_state('load')
    print('goAuto type:', page.evaluate('typeof window.goAuto'))
    # 点击"网页版"按钮, 应触发跳转 (file:// 环境跳到 https 会失败, 只验证不报错且 URL 变化)
    try:
        with page.expect_navigation(timeout=3000) as nav:
            page.locator('button.store').first.click()
        print('navigated to:', page.url)
    except Exception as e:
        print('navigation result:', page.url)
    print('page errors:', errors)
    # 区块顺序: get 应在 caps 前
    order = page.evaluate("""() => {
      const g = document.querySelector('#get'), c = document.querySelector('.caps');
      return g.compareDocumentPosition(c) & Node.DOCUMENT_POSITION_FOLLOWING ? 'get-before-caps' : 'WRONG';
    }""")
    print('section order:', order)
    ios = page.locator('a.store[href$="ios.html"]').count()
    print('ios buttons:', ios)
    browser.close()
