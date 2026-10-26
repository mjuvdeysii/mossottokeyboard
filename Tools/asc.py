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


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "ensure-bundle-ids":
        ensure_bundle_ids(sys.argv[2:])
    elif cmd == "check-app":
        check_app(sys.argv[2])
    else:
        sys.exit(f"unknown command {cmd}")
