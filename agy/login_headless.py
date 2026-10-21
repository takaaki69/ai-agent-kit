#!/usr/bin/env python3
"""Log agy in from a cloud session, where nobody can click through its terminal UI.

    python3 login_headless.py start          # opens agy in a background pty, prints the sign-in URL
    python3 login_headless.py code <CODE>    # types the code the user got, waits for the token, saves it

The user opens the URL, signs in with the Google AI Pro account and pastes back the code.
The code only works for the agy process started by `start`, so run both steps without
restarting in between (it stays alive for ~25 minutes). Nothing secret is printed.
"""
import os, pty, re, select, subprocess, sys, time
from pathlib import Path

WORK = Path(os.environ.get("AGY_LOGIN_WORK", "/tmp/agy-login"))
TOKEN = Path(os.environ.get("AGY_AUTH_DIR") or Path.home() / ".gemini/antigravity-cli") / "antigravity-oauth-token"
KEYS, LOG = WORK / "keys", WORK / "out.log"
KIT = Path(__file__).resolve().parent.parent


def clean(raw: bytes) -> str:
    text = raw.decode("utf8", "ignore")
    text = re.sub(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)", "", text)
    return re.sub(r"\x1b\[[0-9;?<>]*[a-zA-Z]", "", text).replace("\r", "")


def daemon():
    env = dict(os.environ, TERM="xterm-256color", BROWSER="none")
    env["PATH"] = f"{Path.home()}/.local/bin:" + env["PATH"]
    for k in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        env.pop(k, None)
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe("agy", ["agy"], env)
    log = open(LOG, "ab", buffering=0)
    end = time.time() + 1500
    while time.time() < end and not TOKEN.exists():
        if select.select([fd], [], [], 1)[0]:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            log.write(data)
        if KEYS.exists():
            os.write(fd, KEYS.read_bytes().replace(b"\\r", b"\r")); KEYS.unlink()
    time.sleep(5)  # let agy finish writing the token
    os.kill(pid, 15)


def send(keys: str):
    KEYS.write_text(keys)
    while KEYS.exists():
        time.sleep(0.2)


def start():
    WORK.mkdir(parents=True, exist_ok=True)
    for f in (LOG, KEYS):
        f.unlink(missing_ok=True)
    subprocess.Popen([sys.executable, __file__, "daemon"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(8); send("\\r")  # choose "1. Google OAuth"
    time.sleep(6)
    urls = re.findall(r"\]8;id=[^;]*;(https://accounts\.google\.com[^\x07\x1b]*)", LOG.read_bytes().decode("utf8", "ignore"))
    if not urls:
        sys.exit("no sign-in URL found; see " + str(LOG))
    print(max(set(urls), key=len))


def code(value: str):
    send("\x1b[1;2B" * 12)  # scroll to the code box
    time.sleep(1)
    send(value)
    time.sleep(3)
    send("\\r")
    for _ in range(30):
        if TOKEN.exists():
            break
        time.sleep(1)
    else:
        sys.exit("no token yet; the code may have expired. Run `start` again.")
    print("agy token written")
    if os.environ.get("CLAUDE_CODE_REMOTE") == "true":
        subprocess.run([sys.executable, str(KIT / "lib/auth_store.py"), "agy", "save"])


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "daemon": daemon()
    elif cmd == "start": start()
    elif cmd == "code" and len(sys.argv) > 2: code(sys.argv[2])
    else: sys.exit(__doc__)
