#!/usr/bin/env python3
"""Fail if a relative link in any Markdown file points to a file that does not exist."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", "node_modules"}
LINK = re.compile(r"\]\(([^)\s]+)\)")
bad = []
checked = 0
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for name in filenames:
        if not name.endswith(".md"):
            continue
        path = os.path.join(dirpath, name)
        text = open(path, encoding="utf8").read()
        text = re.sub(r"```.*?```", "", text, flags=re.S)  # ignore code blocks
        for target in LINK.findall(text):
            if re.match(r"^[a-z]+:", target) or target.startswith("#"):
                continue
            target = target.split("#", 1)[0]
            if not target:
                continue
            checked += 1
            if not os.path.exists(os.path.normpath(os.path.join(dirpath, target))):
                bad.append("%s -> %s" % (os.path.relpath(path, ROOT), target))
print("checked %d relative link(s)" % checked)
if bad:
    print("BROKEN LINKS:\n  " + "\n  ".join(bad))
    sys.exit(1)
