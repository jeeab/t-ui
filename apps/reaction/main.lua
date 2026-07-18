-- Reaction Timer for T-UI -------------------------------------------------------
-- Test your reflexes: tap to arm, WAIT while the box is red, then tap the moment
-- it turns green. Shows your milliseconds; best time is saved. Tapping early
-- counts as a jump start. Challenge the family — lowest number wins.
------------------------------------------------------------------------------
local st = 0            -- 0 idle · 1 armed/red (waiting) · 2 green (go!) · 3 result
local goAt = 0          -- when the box turns green
local t0 = 0            -- green timestamp (reaction measured from here)
local best = 0

local function say(t, c)
  screen.label(3, 60, 30, t, c or 0xffffff)
end

local function drawBest()
  if best > 0 then
    screen.label(4, 104, 6, 'best ' .. best .. ' ms', 0xffd60a)
  end
end

local function idle()
  st = 0
  screen.box(1, 40, 60, 240, 140, 0x1c1c3a, 16)
  say('tap to start', 0x8e8e93)
end

function on_open()
  math.randomseed(device.time())
  best = math.floor(tonumber(store.read('best.txt') or '') or 0)
  screen.box(2, 0, 0, 320, 240, 0x000000, 0)
  drawBest()
  idle()
end

function on_touch(x, y)
  local now = device.time()
  if st == 0 or st == 3 then          -- arm a new round
    st = 1
    goAt = now + 1200 + math.random(0, 2300)
    screen.box(1, 40, 60, 240, 140, 0xb3261e, 16)
    say('wait for GREEN...', 0xffffff)
  elseif st == 1 then                 -- tapped while still red
    st = 3
    screen.box(1, 40, 60, 240, 140, 0x1c1c3a, 16)
    say('Too soon! tap to retry', 0xff9f0a)
    device.beep()
  elseif st == 2 then                 -- the measurement
    local ms = now - t0
    st = 3
    screen.box(1, 40, 60, 240, 140, 0x1c1c3a, 16)
    if best == 0 or ms < best then
      best = ms
      store.write('best.txt', tostring(best))
      drawBest()
      say(ms .. ' ms  NEW BEST!', 0x30d158)
      device.beep(true)
    else
      say(ms .. ' ms  ·  tap to retry', 0xffffff)
      device.beep()
    end
  end
end

function on_tick(dt)
  if st == 1 and device.time() >= goAt then
    st = 2
    t0 = device.time()
    screen.box(1, 40, 60, 240, 140, 0x1f8a3b, 16)
    say('TAP NOW!', 0xffffff)
  end
end
