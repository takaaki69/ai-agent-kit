"""Tiny Google Drive client for the kit (standard library only, no pip installs).

It stores and fetches small files (login files) under <root folder>/<folder>/<name>.
Credentials come from environment variables, so they can live in the cloud
environment's settings:

    AI_KIT_DRIVE_CLIENT_ID
    AI_KIT_DRIVE_CLIENT_SECRET
    AI_KIT_DRIVE_REFRESH_TOKEN
    AI_KIT_DRIVE_ROOT_FOLDER_ID

For projects that already use `<PREFIX>_DRIVE_*` names (montage-studio uses
OPENMONTAGE_DRIVE_*), those are accepted as they are, with the same layout, so an
existing Drive copy keeps working. Nothing here deletes files.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request

SUFFIXES = ("CLIENT_ID", "CLIENT_SECRET", "REFRESH_TOKEN", "ROOT_FOLDER_ID")
API = "https://www.googleapis.com/drive/v3/files"
UPLOAD = "https://www.googleapis.com/upload/drive/v3/files"
FOLDER_MIME = "application/vnd.google-apps.folder"


def credential_prefixes() -> list[str]:
    """Env prefixes that carry a full set of Drive credentials: AI_KIT first, then any <X>_DRIVE."""
    found = []
    for prefix in ["AI_KIT_DRIVE"] + sorted({k[: -len("_REFRESH_TOKEN")] for k in os.environ if k.endswith("_DRIVE_REFRESH_TOKEN")}):
        if prefix not in found and all(os.environ.get(f"{prefix}_{s}", "").strip() for s in SUFFIXES):
            found.append(prefix)
    return found


def missing_credentials() -> list[str]:
    """Names of the AI_KIT_DRIVE_* variables that are not set (empty when some prefix is complete)."""
    if credential_prefixes():
        return []
    return [f"AI_KIT_DRIVE_{s}" for s in SUFFIXES if not os.environ.get(f"AI_KIT_DRIVE_{s}", "").strip()]


class Drive:
    def __init__(self, prefix: str | None = None):
        prefixes = credential_prefixes()
        if prefix is None:
            if not prefixes:
                raise SystemExit("Drive credentials are not set: " + ", ".join(missing_credentials()))
            prefix = prefixes[0]
        self.v = {s: os.environ[f"{prefix}_{s}"].strip() for s in SUFFIXES}
        self._token: str | None = None

    def _access_token(self) -> str:
        if self._token is None:
            body = urllib.parse.urlencode(
                {
                    "client_id": self.v["CLIENT_ID"],
                    "client_secret": self.v["CLIENT_SECRET"],
                    "refresh_token": self.v["REFRESH_TOKEN"],
                    "grant_type": "refresh_token",
                }
            ).encode()
            with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=body), timeout=60) as r:
                self._token = json.load(r)["access_token"]
        return self._token

    def _call(self, method: str, url: str, params: dict | None = None, data: bytes | None = None, headers: dict | None = None):
        if params:
            url += "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, data=data, method=method, headers={"Authorization": f"Bearer {self._access_token()}", **(headers or {})})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            raise SystemExit(f"Drive request failed: HTTP {e.code} {method} {urllib.parse.urlparse(url).path}") from None

    def _find(self, parent: str, name: str, folder: bool | None = None) -> dict | None:
        esc = lambda s: s.replace("\\", "\\\\").replace("'", "\\'")
        q = f"name = '{esc(name)}' and '{esc(parent)}' in parents and trashed = false"
        if folder is not None:
            q += f" and mimeType {'=' if folder else '!='} '{FOLDER_MIME}'"
        params = {"q": q, "fields": "files(id,name)", "pageSize": 10, "supportsAllDrives": "true", "includeItemsFromAllDrives": "true"}
        files = json.loads(self._call("GET", API, params))["files"]
        return files[0] if files else None

    def _folder(self, name: str, create: bool) -> str | None:
        found = self._find(self.v["ROOT_FOLDER_ID"], name, folder=True)
        if found:
            return found["id"]
        if not create:
            return None
        meta = {"name": name, "mimeType": FOLDER_MIME, "parents": [self.v["ROOT_FOLDER_ID"]]}
        out = self._call("POST", API, {"fields": "id", "supportsAllDrives": "true"}, json.dumps(meta).encode(), {"Content-Type": "application/json"})
        return json.loads(out)["id"]

    def get(self, folder: str, name: str) -> bytes | None:
        parent = self._folder(folder, create=False)
        entry = self._find(parent, name, folder=False) if parent else None
        if entry is None:
            return None
        return self._call("GET", f"{API}/{urllib.parse.quote(entry['id'], safe='')}", {"alt": "media", "supportsAllDrives": "true"})

    def put(self, folder: str, name: str, data: bytes) -> None:
        parent = self._folder(folder, create=True)
        entry = self._find(parent, name, folder=False)
        if entry:
            self._call("PATCH", f"{UPLOAD}/{urllib.parse.quote(entry['id'], safe='')}", {"uploadType": "media", "supportsAllDrives": "true"}, data, {"Content-Type": "application/json"})
            return
        boundary = "aikit" + os.urandom(8).hex()
        meta = json.dumps({"name": name, "parents": [parent]}).encode()
        body = (
            f"--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".encode()
            + meta
            + f"\r\n--{boundary}\r\nContent-Type: application/json\r\n\r\n".encode()
            + data
            + f"\r\n--{boundary}--".encode()
        )
        self._call("POST", UPLOAD, {"uploadType": "multipart", "fields": "id", "supportsAllDrives": "true"}, body, {"Content-Type": f"multipart/related; boundary={boundary}"})
