#!/usr/bin/env python3
"""
App Store Connect API helper used by CI.

  python3 Tools/asc.py ensure-bundle-ids app.mossling.keyboard app.mossling.keyboard.ext
  python3 Tools/asc.py check-app app.mossling.keyboard

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (contents of the .p8 key).
Requires: pip install pyjwt cryptography
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"},
                      os.environ["ASC_KEY_P8"], algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body else None)
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        print(f"::error title=App Store Connect {method} {path}::{e.code} {e.read().decode()[:400]}")
        raise


def find_bundle(identifier):
    q = urllib.parse.urlencode({"filter[identifier]": identifier, "limit": 200})
    for d in call("GET", f"/bundleIds?{q}").get("data", []):
        if d["attributes"]["identifier"] == identifier:
            return d
    return None


def ensure_bundle_ids(ids):
    for i in ids:
        if find_bundle(i):
            print(f"bundle id exists: {i}")
            continue
        name = "Xiaohe Keyboard" + (" Ext" if i.endswith(".ext") else "")
        call("POST", "/bundleIds", {"data": {"type": "bundleIds",
                                             "attributes": {"identifier": i, "name": name, "platform": "IOS"}}})
        print(f"::notice title=Bundle ID registered::{i}")


def check_app(bundle):
    q = urllib.parse.urlencode({"filter[bundleId]": bundle})
    apps = [a for a in call("GET", f"/apps?{q}").get("data", []) if a["attributes"]["bundleId"] == bundle]
    if not apps:
        print(f"::error title=App record missing::App Store Connect has no app for bundle ID {bundle}. "
              f"Create it once: App Store Connect > Apps > + > New App > iOS, Bundle ID {bundle}, any name/SKU. Then re-run.")
        sys.exit(2)
    a = apps[0]["attributes"]
    print(f"::notice title=App record::{a['name']} ({bundle})")


def whats_new(bundle, build, path, wait_minutes=25):
    """TestFlight 'What to Test' for this build, from a text file (zh-Hans; ≤ 4000 characters). The build appears in
    App Store Connect a few minutes after upload: wait for it."""
    text = open(path, encoding="utf-8").read().strip()[:4000]
    q = urllib.parse.urlencode({"filter[bundleId]": bundle})
    app = [a for a in call("GET", f"/apps?{q}").get("data", []) if a["attributes"]["bundleId"] == bundle][0]
    deadline = time.time() + wait_minutes * 60
    build_id = None
    while time.time() < deadline:
        q = urllib.parse.urlencode({"filter[app]": app["id"], "filter[version]": str(build), "limit": 1})
        data = call("GET", f"/builds?{q}").get("data", [])
        if data:
            build_id = data[0]["id"]; break
        time.sleep(30)
    if not build_id:
        print(f"::warning title=What to Test::build {build} not in App Store Connect after {wait_minutes} min"); return
    locs = call("GET", f"/builds/{build_id}/betaBuildLocalizations").get("data", [])
    mine = [l for l in locs if l["attributes"].get("locale") == "zh-Hans"]
    if mine:
        call("PATCH", f"/betaBuildLocalizations/{mine[0]['id']}",
             {"data": {"type": "betaBuildLocalizations", "id": mine[0]["id"], "attributes": {"whatsNew": text}}})
    else:
        call("POST", "/betaBuildLocalizations",
             {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "zh-Hans", "whatsNew": text},
                       "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    print(f"::notice title=What to Test::set for build {build}")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "ensure-bundle-ids":
        ensure_bundle_ids(sys.argv[2:])
    elif cmd == "check-app":
        check_app(sys.argv[2])
    elif cmd == "whats-new":
        whats_new(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit(f"unknown command {cmd}")
