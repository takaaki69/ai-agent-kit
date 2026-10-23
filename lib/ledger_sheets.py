"""Minimal Google Sheets client for a ledger spreadsheet (standard library only).

Needs two environment variables (no defaults, nothing is stored in the repo):
    AI_KIT_LEDGER_SHEET_ID   the spreadsheet id (the part of the URL between /d/ and /edit)
    AI_KIT_LEDGER_SA         the service account email that the sheet is shared with

Authentication: the cloud environment's network proxy attaches credentials to requests for
iamcredentials.googleapis.com. We ask that API for a short-lived access token with the
spreadsheets scope, then call the Sheets API with that token. See docs/LEDGER-PATTERN.md.

Errors print only the HTTP status and the request path, never the token or the response body.

    python3 lib/ledger_sheets.py     # read test: prints the title and tab names
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

NEED = ("AI_KIT_LEDGER_SHEET_ID", "AI_KIT_LEDGER_SA")


def _env() -> tuple[str, str]:
    missing = [k for k in NEED if not os.environ.get(k, "").strip()]
    if missing:
        raise SystemExit("Not set: " + ", ".join(missing) + " (see docs/LEDGER-PATTERN.md)")
    return os.environ["AI_KIT_LEDGER_SHEET_ID"].strip(), os.environ["AI_KIT_LEDGER_SA"].strip()


def _call(method: str, url: str, body: dict | None = None, token: str | None = None) -> dict:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    where = f"{method} {urllib.parse.urlparse(url).path}"
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raise SystemExit(f"Request failed: HTTP {e.code} {where}") from None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
        raise SystemExit(f"Request failed: {type(e).__name__} {where}") from None


def token() -> str:
    _, sa = _env()
    url = f"https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/{urllib.parse.quote(sa, safe='@')}:generateAccessToken"
    r = _call("POST", url, {"scope": ["https://www.googleapis.com/auth/spreadsheets"]})
    if "accessToken" not in r:
        raise SystemExit("Could not get an access token (check the network secret and the service account).")
    return r["accessToken"]


def api(method: str, path: str, body: dict | None = None) -> dict:
    """Call the Sheets API for the ledger. `path` starts with '?' or '/', e.g. '/values/Sheet1!A1:C5'.

    Tab names with spaces or other special characters are encoded for you.
    """
    sid, _ = _env()
    return _call(method, "https://sheets.googleapis.com/v4/spreadsheets/" + sid + urllib.parse.quote(path, safe="/!:?=&,$'"), body, token())


if __name__ == "__main__":
    r = api("GET", "?fields=properties.title,sheets.properties.title")
    print(r.get("properties", {}).get("title", "(no title)"))
    for s in r.get("sheets", []):
        print(" -", s["properties"]["title"])
    sys.exit(0 if "properties" in r else 1)
