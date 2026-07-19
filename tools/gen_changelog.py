#!/usr/bin/env python3
"""
Write CHANGELOG.md from changelog.json.

changelog.json is the single source of truth: the What's new section on index.html renders
from it directly, and this produces the readable file for the repo and the "Full history"
link. Run it after editing changelog.json:

    python3 tools/gen_changelog.py

Also sanity-checks that the version the installer is currently handing out (manifest.json)
has an entry - it's easy to ship a build and forget to say what changed.
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "changelog.json"
OUT = ROOT / "CHANGELOG.md"
MANIFEST = ROOT / "manifest.json"

HEADER = """# T-UI changelog

Every release, newest first. Written for people using the device, not developers.

Install the latest from **<https://jeeab.github.io/t-ui/>**.
"""


def main() -> int:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    releases = data.get("releases", [])
    if not releases:
        print("changelog.json has no releases")
        return 1

    lines = [HEADER]
    for r in releases:
        lines.append(f"\n## {r['title']}")
        lines.append(f"\n**{r['version']}** · {r['date']}\n")
        for c in r.get("changes", []):
            lines.append(f"- {c}")
        lines.append("")

    OUT.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    print(f"wrote {OUT.name}: {len(releases)} releases")

    # The thing most likely to be forgotten: shipping a build without a changelog entry.
    if MANIFEST.is_file():
        version = json.loads(MANIFEST.read_text(encoding="utf-8-sig")).get("version")
        if version and not any(r["version"] == version for r in releases):
            print(f"WARNING: manifest.json ships {version}, which has no changelog entry.")
            return 1
        if version:
            print(f"manifest ships {version} - entry present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
