# Submit an app to Get Apps

Anyone can send in an app. Apps are single Lua text files that run in a sandbox on the
T-Deck, so there's nothing to compile and nothing that can hurt your device.

If you've never written one: read the [app-maker's guide](LUA_APP_SPEC.md) first, or hand
that file to an AI assistant and describe the app you want.

## What an app is

Two things:

1. A folder `apps/<id>/main.lua` — your app, one plain text file.
2. One entry in `apps/catalog.json` — how it shows up on the device.

`<id>` is the folder name on the SD card: 2-14 characters, lowercase letters, numbers or
dashes (`pinball`, `tide-clock`). It has to be unique.

Your catalog entry looks like this:

```json
{
  "id": "tide-clock",
  "name": "Tides",
  "kind": "tool",
  "desc": "Next high and low tide for a spot you pick.",
  "ver": "1",
  "bytes": 3104,
  "url": "apps/tide-clock/main.lua"
}
```

| Field | Rules |
|---|---|
| `id` | must match the folder name |
| `name` | what shows under the tile — 14 characters max |
| `kind` | `game`, `tool`, or `toy` |
| `desc` | one sentence, under 90 characters (it has to fit the device screen) |
| `ver` | bump it when you change the app |
| `bytes` | the exact size of your `main.lua` — the checker tells you the number if you get it wrong |
| `url` | always `apps/<id>/main.lua` |

## How to send it

1. Fork this repository.
2. Add your folder and your catalog entry.
3. Open a pull request.

A check runs automatically and posts back either a green tick or a plain-English list of
what to fix. Once it's green, Jake reviews it and merges. After that it appears in the
store on the device and on the [web page](https://jeeab.github.io/t-ui/apps.html) — no
new firmware needed.

## Check it yourself first

```
python3 tools/check_app.py            # check everything
python3 tools/check_app.py tide-clock # check just yours
```

## What the check looks for

- The file is plain text, valid Lua, and under 16 KB.
- It defines at least one of `on_open`, `on_tick`, `on_touch`, `on_drag`, `on_close` —
  otherwise nothing would ever run.
- It doesn't reach for `io`, `os`, `require`, `load`, `debug` or friends. The app engine
  doesn't provide these at all, so using one means the app is either broken or probing.
  Words inside comments and strings are ignored, so you can *talk* about them freely.
- No invisible control characters (they can make code read differently to a reviewer than
  it runs).
- Your catalog entry matches the file that's actually there.

The check reads your code as text and never runs it.

## House rules

- It has to be yours to give, and it gets published under this repository's licence.
- Keep it family-friendly — this thing gets handed to relatives.
- No app that only pretends to be another app, and nothing that asks for a password.

Broken apps can't hurt the device: if a script hits an error the engine catches it, and
uninstalling is deleting the folder.
