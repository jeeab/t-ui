#!/usr/bin/env python3
"""
Safety + sanity check for a submitted T-UI app.

Runs on every pull request (see .github/workflows/app-check.yml) and can be run by hand:

    python3 tools/check_app.py            # check every app in the catalog
    python3 tools/check_app.py dice       # check one app

An app is a folder `apps/<id>/main.lua` plus one entry in `apps/catalog.json`.
Apps run inside the launcher's sandboxed Lua engine, which already withholds the
dangerous standard libraries. This script is the second line of defence: it rejects a
submission that *tries* to reach outside the sandbox, that is too big for the device,
or whose catalog entry doesn't match the file on disk.

Exit code 0 = everything passed. 1 = at least one problem (the PR check goes red).
"""

import json
import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
APPS = ROOT / "apps"
CATALOG = APPS / "catalog.json"

# The device is a 320x240 ESP32 with 8 MB of PSRAM. The real ceiling is generous enough for
# a big game (Deep Space is ~82 KB) with plenty of room to grow, but not so big it would
# crowd the SD card or the Lua heap. Must match kScriptCap in the firmware's LuaApp.cpp so a
# submission that passes here can actually launch on the device.
MAX_BYTES = 196608

# The tile label on the launcher grid is narrow, and the id doubles as the folder name
# on the SD card (FAT: keep it short, lowercase, no spaces or punctuation).
ID_RE = re.compile(r"^[a-z][a-z0-9-]{1,13}$")

# Ways a script could try to escape the sandbox or reach the filesystem/network. The Lua
# engine doesn't load these libraries at all, so a script naming one is either broken or
# probing - either way it doesn't belong in the store. `\b` so `iodine` or `position`
# don't trip it.
FORBIDDEN = [
    ("io", "file access"),
    ("os", "operating-system access"),
    ("require", "loading other modules"),
    ("package", "loading other modules"),
    ("dofile", "running another file"),
    ("loadfile", "running another file"),
    ("loadstring", "running generated code"),
    ("load", "running generated code"),
    ("debug", "the debug library"),
    ("collectgarbage", "manual garbage collection"),
    ("_G", "reaching into the global table"),
    ("setfenv", "changing the environment"),
    ("getfenv", "changing the environment"),
    ("coroutine", "coroutines (not available on device)"),
]

LIFECYCLE = ["on_open", "on_tick", "on_touch", "on_drag", "on_close"]

REQUIRED_FIELDS = ["id", "name", "kind", "desc", "ver", "bytes", "url"]
ALLOWED_KINDS = ["game", "tool", "toy"]


def strip_lua_comments_and_strings(src: str) -> str:
    """
    Blank out comments and string literals so the forbidden-word scan only looks at real
    code. Without this, an app whose *description text* says "no io here" would be
    rejected, and a sentence in a comment could hide a genuine call from review.

    Not a full Lua lexer - it handles the forms these apps actually use: -- line comments,
    --[[ block comments ]], and '...' / "..." strings with backslash escapes.
    """
    out = []
    i, n = 0, len(src)
    while i < n:
        two = src[i : i + 2]
        if two == "--":
            if src[i + 2 : i + 4] == "[[":  # block comment
                end = src.find("]]", i + 4)
                end = n if end == -1 else end + 2
            else:  # line comment
                end = src.find("\n", i)
                end = n if end == -1 else end
            out.append(" " * (end - i))
            i = end
        elif src[i] in "\"'":
            quote, j = src[i], i + 1
            while j < n and src[j] != quote:
                j += 2 if src[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(" " * (j - i))
            i = j
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def check_app(app_id: str, entry: dict, problems: list, notes: list) -> None:
    where = f"apps/{app_id}"

    if not ID_RE.match(app_id):
        problems.append(
            f"{where}: the folder name must be 2-14 characters, lowercase letters, "
            f"numbers or dashes, starting with a letter (got '{app_id}')."
        )
        return

    main = APPS / app_id / "main.lua"
    if not main.is_file():
        problems.append(f"{where}: no main.lua found. An app is a folder with a main.lua inside it.")
        return

    raw = main.read_bytes()

    if b"\x00" in raw:
        problems.append(f"{where}/main.lua: this is not a plain text file (it contains raw binary).")
        return

    try:
        src = raw.decode("utf-8")
    except UnicodeDecodeError:
        problems.append(f"{where}/main.lua: must be saved as plain UTF-8 text.")
        return

    if len(raw) > MAX_BYTES:
        problems.append(
            f"{where}/main.lua is {len(raw):,} bytes - the limit is {MAX_BYTES:,} bytes. "
            f"Trim it down or split the work into fewer, simpler functions."
        )

    # Invisible/right-to-left control characters can make code read differently to a human
    # reviewer than it does to the interpreter. Nothing legitimate here needs them.
    sneaky = {c for c in src if unicodedata.category(c) == "Cf"}
    if sneaky:
        names = ", ".join(f"U+{ord(c):04X}" for c in sorted(sneaky))
        problems.append(f"{where}/main.lua contains invisible control characters ({names}). Remove them.")

    code = strip_lua_comments_and_strings(src)
    for word, why in FORBIDDEN:
        if re.search(rf"\b{re.escape(word)}\b", code):
            problems.append(
                f"{where}/main.lua uses '{word}' ({why}). Apps run in a sandbox that has no "
                f"access to this - see the app-maker's guide for the full list of what's available."
            )

    if not any(re.search(rf"\bfunction\s+{fn}\b", code) for fn in LIFECYCLE):
        problems.append(
            f"{where}/main.lua doesn't define any of {', '.join(LIFECYCLE)}, so nothing would "
            f"ever run. Most apps start with 'function on_open()'."
        )

    # --- catalog entry must match the file that's actually there -------------------
    for field in REQUIRED_FIELDS:
        if field not in entry:
            problems.append(f"catalog.json entry '{app_id}' is missing \"{field}\".")

    if entry.get("kind") not in ALLOWED_KINDS:
        problems.append(f"catalog.json entry '{app_id}': \"kind\" must be one of {ALLOWED_KINDS}.")

    expected_url = f"apps/{app_id}/main.lua"
    if entry.get("url") != expected_url:
        problems.append(f"catalog.json entry '{app_id}': \"url\" must be \"{expected_url}\".")

    # The device shows this size before downloading, so a wrong number is a small lie to
    # the user rather than a crash - fix it automatically-obviously rather than nagging.
    if entry.get("bytes") != len(raw):
        problems.append(
            f"catalog.json entry '{app_id}': \"bytes\" says {entry.get('bytes')} but "
            f"main.lua is {len(raw)} bytes. Set it to {len(raw)}."
        )

    desc = entry.get("desc", "")
    if len(desc) > 90:
        problems.append(
            f"catalog.json entry '{app_id}': \"desc\" is {len(desc)} characters - keep it under 90 "
            f"so it fits the device screen."
        )

    name = entry.get("name", "")
    if len(name) > 14:
        problems.append(f"catalog.json entry '{app_id}': \"name\" is too long for a tile (max 14 characters).")

    notes.append(f"  {app_id:<12} {len(raw):>6,} bytes   {entry.get('name','?')}")


def main() -> int:
    if not CATALOG.is_file():
        print(f"ERROR: {CATALOG} not found.")
        return 1

    try:
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"ERROR: apps/catalog.json is not valid JSON - {e}")
        return 1

    entries = {a.get("id"): a for a in catalog.get("apps", [])}
    problems: list = []
    notes: list = []

    wanted = sys.argv[1:] or sorted(entries)
    for app_id in wanted:
        if app_id not in entries:
            problems.append(f"apps/{app_id} has no entry in catalog.json, so the device would never see it.")
            continue
        check_app(app_id, entries[app_id], problems, notes)

    # A folder on disk with no catalog entry is dead weight - catch it in the full run.
    if not sys.argv[1:]:
        for folder in sorted(p for p in APPS.iterdir() if p.is_dir()):
            if folder.name not in entries:
                problems.append(
                    f"apps/{folder.name}/ exists but isn't listed in catalog.json - "
                    f"add an entry or remove the folder."
                )

    if notes:
        print("Checked:")
        print("\n".join(notes))

    if problems:
        print(f"\n{len(problems)} problem(s) found:\n")
        for p in problems:
            print(f"  - {p}")
        print("\nFix these and push again - the check re-runs automatically.")
        return 1

    print(f"\nAll good: {len(wanted)} app(s) passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
