-- Dice for T-UI ---------------------------------------------------------------
-- Two big dice. Tap anywhere to roll (they tumble for a moment, then settle).
-- Tap the little "1 die / 2 dice" button bottom-left to switch. Handy for board
-- games when the real dice rolled under the couch.
------------------------------------------------------------------------------
local twoDice = true
local v1, v2 = 3, 5          -- current face values
local rollUntil = 0          -- device.time() until which we're still tumbling
local lastShuffle = 0

-- die geometry (big, centered)
local DS = 96                -- die size
local P = 16                 -- pip size

local function drawPips(base, x0, y0, v)
  -- pip positions on a 3x3 grid of the die face
  local cx = {x0 + 14, x0 + DS // 2 - P // 2, x0 + DS - 14 - P}
  local cy = {y0 + 14, y0 + DS // 2 - P // 2, y0 + DS - 14 - P}
  local pips = {
    [1] = {{2,2}},
    [2] = {{1,1},{3,3}},
    [3] = {{1,1},{2,2},{3,3}},
    [4] = {{1,1},{3,1},{1,3},{3,3}},
    [5] = {{1,1},{3,1},{2,2},{1,3},{3,3}},
    [6] = {{1,1},{3,1},{1,2},{3,2},{1,3},{3,3}},
  }
  for i = 1, 6 do
    if pips[v][i] then
      local p = pips[v][i]
      screen.box(base + i, cx[p[1]], cy[p[2]], P, P, 0x1c1c1e, 99)
    else
      screen.hide(base + i)
    end
  end
end

local function drawDice()
  if twoDice then
    local x1, x2, y = 40, 184, 72
    screen.box(1, x1, y, DS, DS, 0xf2f2f7, 14)
    screen.box(2, x2, y, DS, DS, 0xf2f2f7, 14)
    drawPips(10, x1, y, v1)
    drawPips(20, x2, y, v2)
    screen.label(40, 136, 24, 'total  ' .. (v1 + v2), 0xffd60a)
  else
    local x, y = 112, 72
    screen.box(1, x, y, DS, DS, 0xf2f2f7, 14)
    drawPips(10, x, y, v1)
    for i = 1, 6 do screen.hide(20 + i) end
    screen.hide(2)
    screen.label(40, 136, 24, 'rolled  ' .. v1, 0xffd60a)
  end
end

local function startRoll()
  rollUntil = device.time() + 650
  device.beep()
end

function on_open()
  math.randomseed(device.time())
  screen.box(50, 0, 0, 320, 240, 0x0a3d1f, 0)     -- felt-green table
  screen.label(41, 96, 6, 'tap to roll', 0x8e8e93)
  screen.box(30, 8, 206, 92, 28, 0x1c1c1e, 8)      -- mode button
  screen.label(31, 20, 212, '1 die / 2', 0xffffff)
  drawDice()
end

function on_touch(x, y)
  if x < 108 and y > 198 then                      -- mode button corner
    twoDice = not twoDice
    drawDice()
    return
  end
  startRoll()
end

function on_tick(dt)
  local now = device.time()
  if rollUntil ~= 0 then
    if now < rollUntil then
      if now - lastShuffle > 80 then               -- tumble: reshuffle faces fast
        lastShuffle = now
        v1 = math.random(6)
        v2 = math.random(6)
        drawDice()
      end
    else
      rollUntil = 0
      v1 = math.random(6)                          -- the real, final roll
      v2 = math.random(6)
      drawDice()
      device.beep()
    end
  end
end
