#!/usr/bin/env python3
"""Fails if a Markdown file links to a repository file or folder that does not exist.

External links (http/https/mailto) are not fetched; only relative links are checked.
Usage: python3 .github/scripts/check_md_links.py [root]
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
link = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
skip = ("http://", "https://", "mailto:", "#")
errors = []

for md in sorted(root.rglob("*.md")):
    relative_parts = md.relative_to(root).parts
    if any(part.startswith(".") for part in relative_parts[:-1]) or "node_modules" in relative_parts:
        continue  # .git, .build and other hidden or generated folders
    in_code = False
    for number, line in enumerate(md.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("```"):
            in_code = not in_code
        if in_code:
            continue
        for target in link.findall(line):
            if target.startswith(skip):
                continue
            path = target.split("#", 1)[0]
            if path and not (md.parent / path).resolve().exists():
                errors.append(f"{md.relative_to(root)}:{number}: broken link -> {target}")

print("\n".join(errors) or "All relative Markdown links resolve.")
sys.exit(1 if errors else 0)
