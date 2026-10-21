"""Keep a helper CLI's login (Codex ChatGPT plan, Antigravity CLI Google account) between cloud sessions.

    python lib/auth_store.py codex|agy restore   # store -> local login (session start)
    python lib/auth_store.py codex|agy save      # local login -> store, when newer
    python lib/auth_store.py codex|agy status

Where the copy lives is chosen by AI_KIT_STORE:
  dir:<path>   a directory (a synced or mounted folder).
  drive        Google Drive through lib/drive.py (standard library only). Credentials are
               AI_KIT_DRIVE_{CLIENT_ID,CLIENT_SECRET,REFRESH_TOKEN,ROOT_FOLDER_ID}; a project's
               own <PREFIX>_DRIVE_* set (e.g. OPENMONTAGE_DRIVE_*) works as it is.
               The file goes to <Drive root>/_private/<tool>-auth.json.
Unset: drive when Drive credentials are set, otherwise dir:~/.ai-agent-kit-store, which does
not survive the session.

The file is a password. Nothing here prints its contents.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

REMOTE_DIR = "_private"


class Tool:
    def __init__(self, name: str, env: str, home: str, filename: str):
        self.name, self.env, self.home, self.filename = name, env, home, filename

    @property
    def remote_name(self) -> str:
        return f"{self.name}-auth.json"

    def local(self) -> Path:
        return Path(os.environ.get(self.env) or Path.home() / self.home) / self.filename

    def stamp(self, data: bytes) -> datetime | None:
        """When the login was last refreshed, or None if this is not a login we keep."""
        try:
            payload = json.loads(data)
        except ValueError:
            return None
        if not isinstance(payload, dict):
            return None
        epoch = datetime.min.replace(tzinfo=timezone.utc)
        if self.name == "codex":
            if not payload.get("tokens"):
                return None  # API-key logins are not ours to keep
            raw = str(payload.get("last_refresh") or "")
            try:
                s = datetime.fromisoformat(raw.replace("Z", "+00:00"))
            except ValueError:
                return epoch
            return s if s.tzinfo else s.replace(tzinfo=timezone.utc)
        token = payload.get("token")
        if not isinstance(token, dict) or not token.get("refresh_token"):
            return None
        raw = re.sub(r"(\.\d{6})\d+", r"\1", str(token.get("expiry") or ""))  # moves forward on each refresh
        try:
            s = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            return epoch
        return s if s.tzinfo else s.replace(tzinfo=timezone.utc)


TOOLS = {
    "codex": Tool("codex", "CODEX_HOME", ".codex", "auth.json"),
    "agy": Tool("agy", "AGY_AUTH_DIR", ".gemini/antigravity-cli", "antigravity-oauth-token"),
}


def _md5(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def _write_private(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    partial = path.with_name(path.name + ".part")
    fd = os.open(partial, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(data)
    partial.replace(path)


class DirStore:
    def __init__(self, root: Path):
        self.root = root

    def get(self, name: str) -> bytes | None:
        path = self.root / name
        return path.read_bytes() if path.is_file() else None

    def put(self, name: str, data: bytes) -> None:
        _write_private(self.root / name, data)


class DriveStore:
    """Google Drive through lib/drive.py: <root>/_private/<tool>-auth.json."""

    def __init__(self):
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from drive import Drive

        self.drive = Drive()

    def get(self, name: str) -> bytes | None:
        return self.drive.get(REMOTE_DIR, name)

    def put(self, name: str, data: bytes) -> None:
        self.drive.put(REMOTE_DIR, name, data)


def _drive_credentials() -> bool:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from drive import credential_prefixes

    return bool(credential_prefixes())


def store_kind() -> str:
    """Which store is in use: 'drive', 'dir', and whether it was chosen by AI_KIT_STORE or by default."""
    spec = os.environ.get("AI_KIT_STORE", "")
    if spec:
        return ("drive" if spec == "drive" else "dir") + " (AI_KIT_STORE)"
    return ("drive" if _drive_credentials() else "dir") + " (default)"


def open_store():
    spec = os.environ.get("AI_KIT_STORE", "")
    if spec == "drive" or (not spec and _drive_credentials()):
        return DriveStore()
    root = spec[4:] if spec.startswith("dir:") else str(Path.home() / ".ai-agent-kit-store")
    return DirStore(Path(root).expanduser())


def restore(tool: Tool, store) -> str:
    remote = store.get(tool.remote_name)
    if remote is None or tool.stamp(remote) is None:
        return f"no login in the store yet: run the {tool.name} login script"
    local = tool.local()
    if local.exists():
        current = local.read_bytes()
        if _md5(current) == _md5(remote):
            return "already up to date"
        mine = tool.stamp(current)
        if mine is not None and mine >= tool.stamp(remote):
            return "kept the local login (it is as new as the store's or newer)"
    _write_private(local, remote)
    return f"restored the {tool.name} login"


def save(tool: Tool, store) -> str:
    local = tool.local()
    if not local.exists():
        return "no local login to save"
    data = local.read_bytes()
    mine = tool.stamp(data)
    if mine is None:
        return "local login is not one we keep; not saved"
    remote = store.get(tool.remote_name)
    if remote is not None:
        if _md5(remote) == _md5(data):
            return "store already has this login"
        theirs = tool.stamp(remote)
        if theirs is not None and theirs > mine:
            return "store has a newer login; not overwritten (run restore)"
    store.put(tool.remote_name, data)
    return f"saved the {tool.name} login"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Keep a helper CLI's login between cloud sessions.")
    parser.add_argument("tool", choices=sorted(TOOLS))
    parser.add_argument("command", choices=["restore", "save", "status", "store"])
    args = parser.parse_args(argv)
    tool = TOOLS[args.tool]
    if args.command == "store":
        print(store_kind())
        return 0
    store = open_store()
    if args.command == "restore":
        print(f"{tool.name} auth:", restore(tool, store))
    elif args.command == "save":
        print(f"{tool.name} auth:", save(tool, store))
    else:
        local, remote = tool.local(), store.get(tool.remote_name)
        print("local login:", "yes" if local.exists() and tool.stamp(local.read_bytes()) else "no")
        print("store copy:", "yes" if remote is not None and tool.stamp(remote) else "no")
    return 0


if __name__ == "__main__":
    sys.exit(main())
