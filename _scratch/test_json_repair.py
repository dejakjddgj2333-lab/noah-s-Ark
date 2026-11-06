import json
import re

TH = re.compile(r"(?<=\d),(?=\d{3}(?!\d))")


def repair(text):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return json.loads(TH.sub("", text))


samples = [
    '{"supports":[76,904.06,76,517.84,75,734.50],"resistances":[77,565.00,78,066.30,78,241.91]}',
    '{"supports":[76,517.93,75,734.50,75,000],"resistances":[77,565.03,78,066.30,78,242.12]}',
    '{"stop_loss":"77,484.1","take_profit":"76,386.0","big":[1,234,567.89]}',
    '{"ok":[1,2,3],"note":"测试,逗号保留"}',
]
for s in samples:
    print(repair(s))
