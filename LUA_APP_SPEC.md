# Writing an app for the T-Deck launcher (Lua) — full specification

This document describes everything needed to write a working app or game for the LilyGo
**T-Deck** running Jake's custom launcher firmware. Hand this whole file to an AI assistant
(e.g. Claude) and say *"write me a game for this, following these rules"* — it has all the
constraints and the exact API.

An app is a single text file named **`main.lua`**. You put it in a folder on the T-Deck's
SD card and it shows up as a tile in the launcher. No compiling, no tools — just a text file.

---

## The device, in numbers
- **Screen:** 320 wide × 240 tall pixels, landscape. Top-left corner is `(0, 0)`; x grows
  right, y grows down.
- **Colors:** 24-bit hex numbers, `0xRRGGBB` (e.g. `0xff453a` red, `0x30d158` green,
  `0xffffff` white, `0x000000` black). The background is always black.
- **Input:** the **touchscreen only** (tap and drag). The physical keyboard and trackball are
  NOT available to apps — the trackball's double-click is reserved by the system to exit the app.
- **Language:** Lua 5.4. Integer division `//` and `math.floor` both work.
- **Frame rate:** about 30 frames per second.

## What your script may use
Only these standard Lua libraries are available: **base**, **string**, **math**, **table**.
Deliberately absent (for safety): `io`, `os`, `package`/`require`, `coroutine`. So: no general
file access, no `os.time` (use `device.time()` instead), no external modules. To save data, use
`store.write`/`store.read` below — that's the safe, supported way, and it keeps your app inside
its own folder. Everything you need is in the API below.

---

## The lifecycle: functions YOU define
Define any of these as global Lua functions. The system calls them for you. All are optional
except that you'll almost always want `on_open`.

| Function | When it's called | Use it for |
|---|---|---|
| `on_open()` | once, when the app starts | draw the initial/static screen, set up state |
| `on_tick(dt)` | ~every 33 ms (about 30×/sec) | animation, game logic, movement |
| `on_touch(x, y)` | the moment the finger lands | buttons, "tap to start", firing, menu picks |
| `on_drag(x, y)` | repeatedly while a finger slides | steering a paddle, sliders, dragging |
| `on_close()` | once, when the user exits the app | (rarely needed — state is discarded anyway) |

`dt` in `on_tick` is a nominal ~33 (ms). It does NOT measure real elapsed time — if you need
accurate timing (e.g. a metronome, a countdown), read `device.time()` yourself and compare.

## The API: functions the system gives YOU
This is the **complete** toolbox. There is nothing else.

### Drawing (retained — you draw by id, and update in place)
Every visual element has an integer **id** you choose. Draw with an id; call the same function
again with the **same id** to move/update that element; the screen remembers it between frames.
Use a **unique id for every element** (a label and a box should not share an id).

- `screen.label(id, x, y, text, color)` — text at (x, y). `color` optional (default white).
- `screen.box(id, x, y, w, h, color)` — a filled rectangle w×h at (x, y), lightly rounded.
  `color` optional (default white).
- `screen.line(id, x1, y1, x2, y2, thickness, color)` — a straight line from (x1, y1) to
  (x2, y2). `thickness` optional (default 4), `color` optional (default white). Good for
  flipper arms, gauge needles, borders, graph lines.
- `screen.hide(id)` — hide the element with this id (e.g. a brick that got hit). You can show it
  again by drawing to that id.

Limits: at most **64 elements** on screen at once. Text uses one built-in font (no size control).

### Device
- `device.beep()` — a short gentle beep. `device.beep(true)` — a **louder** beep (for a clear
  tick/hit).
- `device.time()` — whole milliseconds since the device booted (an integer). Use differences of
  this for real timing. (This is NOT the wall clock — apps can't read the date or time of day.)
- `device.touches()` — **multi-touch.** Returns the number of fingers currently on the screen,
  followed by an x and y for each (up to 2). Use it when one finger isn't enough — Pinball uses
  it so both flippers can be held at once:

  ```lua
  local n, x1, y1, x2, y2 = device.touches()
  if n >= 1 and x1 < 160 then leftFlipperUp = true end
  if n >= 2 and x2 > 160 then rightFlipperUp = true end
  ```

  `on_touch`/`on_drag` still work and are simpler — reach for `device.touches()` only when you
  genuinely need two fingers at the same time.

### The canvas — for games (firmware 2026.07.19.2 and newer)
`screen.*` above is a **UI toolkit**: every element is a real object and there's a hard ceiling
of **80** of them. Perfect for tools, fine for a simple game, hopeless for a tile map, a
particle effect, or a hundred bullets.

The **canvas** is a full screen of pixels you draw into freely. It's a single object as far as
the system is concerned, so the 80-element limit stops applying. Every call below runs as
native code, so it's fast enough for real games — your Lua decides *what* to draw, the canvas
does the drawing.

```lua
function on_open()
  if not canvas.begin() then return end   -- false if memory is short: fall back to screen.*
end

function on_tick()
  canvas.clear(0x000000)                  -- wipe the frame
  canvas.circle(160, 120, 30, 0x30d158, true)
  canvas.rect(10, 200, 60, 8, 0xff453a)
  canvas.line(0, 0, 320, 240, 0x0a84ff)
  canvas.pixel(50, 50, 0xffffff)
  canvas.flip()                           -- show it
end
```

- `canvas.begin()` — set it up. Returns `false` if there wasn't enough memory; check it.
- `canvas.clear(color)` — fill the whole frame.
- `canvas.rect(x, y, w, h, color)` — filled rectangle.
- `canvas.circle(x, y, radius, color, filled)` — `filled` is `true` or `false`.
- `canvas.line(x1, y1, x2, y2, color)`
- `canvas.pixel(x, y, color)`
- `canvas.flip()` — **nothing appears until you call this.** Draw the whole frame, then flip,
  and the player never sees a half-drawn picture.

Anything drawn off the edge is safely ignored, so you don't need to check coordinates yourself.

**Mix freely:** the canvas sits *behind* the `screen.*` elements, so draw your game world on
the canvas and put the score on top with `screen.label`. That's usually the best of both.

**Costs about 150 KB of memory** while your app is open, released when you leave. Clearing and
redrawing the whole frame each tick is the normal way to use it.

### Saving data (your app remembers things)
Your app has its own folder on the SD card and can keep files there. Use it for high scores,
settings, saved games — anything that should survive closing the app or a reboot.

- `store.write(name, text)` — save `text` under `name`. Returns `true` if it worked.
- `store.read(name)` — returns the saved text, or `nil` if there's nothing saved yet.

Everything is **text**, so convert numbers on the way in and out:

```lua
local best = tonumber(store.read("best.txt") or "0") or 0
if score > best then store.write("best.txt", tostring(score)) end
```

Rules: `name` is a plain filename like `best.txt` — no slashes and no `..` (you can only write
inside your own app's folder). Max **4 KB** per file. Always handle `nil` from `store.read` —
the first time your app ever runs, nothing is saved yet.

### Hard limits (respect these)
- The whole `main.lua` file must be **under 48 KB** of text. (Aim smaller — most apps are 2-4 KB;
  Pinball is about 12 KB, and Deep Space, a full game, is about 18 KB.)
- Max 64 on-screen elements.
- Max 4 KB per saved file.
- If your script hits a Lua error, the system catches it (the device won't crash) but your app
  may stop updating — so test your logic.

---

## A complete, working example (annotated)
A tiny "tap the moving dot" game. Copy this into `main.lua` and it runs.

```lua
-- state
local x, y = 150, 110      -- dot position
local dx, dy = 4, 3        -- dot velocity
local score = 0
local size = 24

function on_open()
  screen.label(1, 8, 8, 'Score 0', 0xffffff)     -- id 1 = the score text
  screen.label(2, 8, 220, 'tap the green dot', 0x8e8e93)
end

function on_tick(dt)
  -- move the dot and bounce off the edges
  x = x + dx; y = y + dy
  if x < 0 or x > 320 - size then dx = -dx end
  if y < 30 or y > 240 - size then dy = -dy end
  screen.box(10, x, y, size, size, 0x30d158)     -- id 10 = the dot
end

function on_touch(tx, ty)
  -- did the tap land on the dot?
  if tx >= x and tx <= x + size and ty >= y and ty <= y + size then
    score = score + 1
    screen.label(1, 8, 8, 'Score ' .. score, 0xffffff)
    device.beep()
    dx = dx * 1.1; dy = dy * 1.1               -- speed up a little
  end
end
```

For a richer reference, the built-in **Breakout** game and **Metronome** tool are themselves Lua
scripts on the SD card at `/apps/breakout/main.lua` and `/apps/metronome/main.lua` — open those on
a computer to see real examples of `on_drag` steering, grids of boxes, and `device.time`-free
timing via `on_tick`.

---

## Installing your app on the T-Deck
1. Pop the microSD card out of the T-Deck and into a computer (or use the T-Deck's own Files app
   once file-copy is available).
2. Make a new folder inside the `/apps` folder, named for your app, e.g. `/apps/mygame`.
3. Put your `main.lua` inside it: `/apps/mygame/main.lua`.
4. Put the card back and reboot the T-Deck. Your app appears as a tile in the launcher.
5. To **uninstall**, delete that `main.lua` (or the whole folder). To reorder tiles, long-press a
   tile and use the arrange screen.

The tile's name comes from the folder name. (Custom tile icons aren't user-settable yet — new
apps get a default icon.)

---

## Prompt template (for handing to an AI)
> Using the attached T-Deck Lua app specification, write a complete `main.lua` for a game called
> **[NAME]**. It should **[describe gameplay]**. Controls: **[tap / drag]**. Follow every limit in
> the spec (320×240 screen, 0xRRGGBB colors, only `screen.*`/`device.*`/`store.*`, the `on_open/
> on_tick/on_touch/on_drag` callbacks, ≤64 elements, ≤48 KB, touchscreen only). Save the high
> score with `store.write`/`store.read`. Give me only the contents of `main.lua`, ready to drop
> on the SD card.

## Ideas that fit this device well
Pong, Breakout, Snake, Simon (color memory), Whac-A-Mole, a reaction-timer, a dice roller, a
tip calculator, a drum pad (using `device.beep`), a soundboard, a "tap to the beat" trainer,
a simple maze, Flappy-style tap game, a countdown/interval timer, a score keeper for card games
(`store` remembers the running totals), a tally counter, a unit converter, 2048, Connect 4.

---

## Sharing your app
Apps you write can go in **Get Apps**, the T-Deck's built-in app list, so anyone can install
them over Wi-Fi without a computer. Submissions are open to everyone — see
[SUBMITTING.md](SUBMITTING.md) for how to send one in. A check runs automatically and tells you
in plain English if anything needs fixing.
