"""Full console error capture with file:line creators, coordinate-based nav."""
import os
from playwright.sync_api import sync_playwright

BASE = "http://localhost:5217"
OUT = r"C:\Users\other8080\Videos\project\hk\shots"

raw = []

def main():
    os.makedirs(OUT, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 390, "height": 844})
        page.on("console", lambda m: raw.append(m.text) if (
            "overflow" in m.text.lower() or "Noto" in m.text) else None)
        page.goto(BASE)
        page.wait_for_timeout(12000)

        navs = [
            ("terminal", None),
            ("market", (78, 78)),
            ("duowei", (143, 78)),
            ("liquidation", (221, 78)),
            ("whale", (299, 78)),
            ("funding", (372, 78)),
            ("news", (146, 823)),
            ("chat", (244, 823)),
            ("assets", (341, 823)),
            ("home_back", (48, 823)),
        ]
        raw.append(f"--- PAGE terminal ---")
        for name, pos in navs:
            if pos:
                raw.append(f"--- PAGE {name} ---")
                page.mouse.click(pos[0], pos[1])
                page.wait_for_timeout(2000)
                page.screenshot(path=f"{OUT}\\nav_{name}.png")
        browser.close()

    with open(r"C:\Users\other8080\Videos\project\hk\overflow_report.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(raw))
    print(f"lines={len(raw)}")

if __name__ == "__main__":
    main()
