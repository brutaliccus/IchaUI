"""Build dist/IchaUI-<version>.zip from the committed addon folders.

Files come from git HEAD (so text files are LF and nothing untracked slips in).
Entries use forward slashes and the addon folders sit at the zip root, so the
zip extracts straight into Interface/AddOns.

    python tools/build_release.py
"""
import os
import re
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

FOLDERS = [
    "IchaUI", "IchaUI_Bars", "IchaUI_BuffBars", "IchaUI_Chat", "IchaUI_CustomDrawers",
    "IchaUI_Hero", "IchaUI_Minimap", "IchaUI_Plates", "IchaUI_Shaman", "IchaUI_SmartMark",
    "IchaUI_SmartTab", "IchaUI_UnitFrames", "IchaUI_XP",
]
BLOCKED = re.compile(r"(\.py[co]?$|\.png$|\.bak$|__pycache__|(^|/)_)", re.I)


def git(*args):
    return subprocess.run(["git", "-C", REPO] + list(args), check=True, capture_output=True).stdout


def version():
    toc = git("show", "HEAD:IchaUI/IchaUI.toc").decode("utf-8", "replace")
    m = re.search(r"^## Version:\s*(\S+)", toc, re.M)
    return m.group(1) if m else "1.0.0"


def main():
    ver = version()
    files = git("ls-tree", "-r", "--name-only", "HEAD", "--", *FOLDERS).decode().splitlines()
    bad = [f for f in files if BLOCKED.search(f)]
    if bad:
        sys.exit("refusing to package dev leftovers: " + ", ".join(bad))
    os.makedirs(os.path.join(REPO, "dist"), exist_ok=True)
    out = os.path.join(REPO, "dist", "IchaUI-%s.zip" % ver)
    dirs = set()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in sorted(files):
            parts = f.split("/")
            for i in range(1, len(parts)):
                d = "/".join(parts[:i]) + "/"
                if d not in dirs:
                    dirs.add(d)
                    z.writestr(zipfile.ZipInfo(d, date_time=(2026, 1, 1, 0, 0, 0)), "")
            z.writestr(f, git("show", "HEAD:" + f))
    print("wrote %s (%d files)" % (os.path.relpath(out, REPO), len(files)))


if __name__ == "__main__":
    main()
