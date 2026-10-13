#!/usr/bin/env python3
# App Group assign 完成后一键重建 profile + 安装 + 填工程.
# 用法: python3 app/ios/finalize_widget_profiles.py
import json, os, sys, time, base64, subprocess, urllib.request, urllib.error
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

ISS = "179ed838-15a7-4b56-82d0-a4d9f65eaeb9"
KID = "553U88DHNG"
KEY = open(os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_553U88DHNG.p8"), "rb").read()
pk = serialization.load_pem_private_key(KEY, password=None)
CERT = "223JTY52C4"          # IOS_DISTRIBUTION 证书 (2027 过期)
MAIN_BUNDLE = "MQC8N69T7C"   # com.hkmc.noahsark
WIDGET_BUNDLE = "SHA3ZNMFM8" # com.hkmc.noahsark.MingceWidget
PROF_DIR = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
IOS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)))

def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def token():
    now = int(time.time())
    h = b64(json.dumps({"alg":"ES256","kid":KID,"typ":"JWT"}, separators=(',',':')).encode())
    p = b64(json.dumps({"iss":ISS,"iat":now,"exp":now+1200,"aud":"appstoreconnect-v1"}, separators=(',',':')).encode())
    sig = pk.sign(f"{h}.{p}".encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(sig)
    return f"{h}.{p}.{b64(r.to_bytes(32,'big')+s.to_bytes(32,'big'))}"
def req(path, method="GET", body=None):
    r = urllib.request.Request("https://api.appstoreconnect.apple.com/v1"+path, method=method)
    r.add_header("Authorization", "Bearer "+token())
    data = None
    if body is not None:
        r.add_header("Content-Type", "application/json")
        data = json.dumps(body).encode()
    try:
        with urllib.request.urlopen(r, data) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")

def profile_uuid(content_b64):
    raw = base64.b64decode(content_b64)
    open("/tmp/_p.mob","wb").write(raw)
    r = subprocess.run(["security","cms","-D","-i","/tmp/_p.mob"], capture_output=True)
    open("/tmp/_p.plist","wb").write(r.stdout)
    u = subprocess.run(["plutil","-extract","UUID","raw","-o","-","/tmp/_p.plist"], capture_output=True)
    ent = subprocess.run(["plutil","-extract","Entitlements","json","-o","-","/tmp/_p.plist"], capture_output=True)
    return u.stdout.decode().strip(), raw, json.loads(ent.stdout.decode() or "{}")

def create_profile(name, bundle_id):
    body = {"data":{"type":"profiles","attributes":{"name":name,"profileType":"IOS_APP_STORE"},
      "relationships":{"bundleId":{"data":{"type":"bundleIds","id":bundle_id}},
        "certificates":{"data":[{"type":"certificates","id":CERT}]},"devices":{"data":[]}}}}
    st, d = req("/profiles","POST",body)
    return st, d

def delete_profile(pid):
    st, _ = req(f"/profiles/{pid}", "DELETE")
    return st

def install(name, bundle_id):
    st, d = create_profile(name, bundle_id)
    if st != 201:
        print(f"  create {name} failed:", json.dumps(d, ensure_ascii=False)[:400]); return None
    content = d["data"]["attributes"]["profileContent"]
    uuid, raw, ent = profile_uuid(content)
    groups = ent.get("com.apple.security.application-groups", [])
    dest = os.path.join(PROF_DIR, uuid + ".mobileprovision")
    open(dest, "wb").write(raw)
    print(f"  {name}: uuid={uuid} groups={groups} -> {dest}")
    return uuid, groups

if __name__ == "__main__":
    os.makedirs(PROF_DIR, exist_ok=True)
    print("== 主 App profile ==")
    main = install("Mingce AppStore", MAIN_BUNDLE)
    print("== Widget profile ==")
    widget = install("MingceWidget AppStore", WIDGET_BUNDLE)
    if not main or not widget:
        sys.exit(1)
    if "group.com.hkmc.noahsark.shared" not in main[1] or "group.com.hkmc.noahsark.shared" not in widget[1]:
        print("\n[!] application-groups 为空 — App Group 还没 assign 到 App ID。先去 developer.apple.com 勾 App Groups 再重跑。")
        sys.exit(2)
    print("\nMAIN_UUID=" + main[0])
    print("WIDGET_UUID=" + widget[0])
    print("OK - 把这两个 UUID 填进工程 Release PROVISIONING_PROFILE_SPECIFIER + ExportOptions.plist")
