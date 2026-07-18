-- Pinball for T-UI  ·  Neon edition v5 ----------------------------------------
-- HOLD the LEFT half of the screen to raise the LEFT flipper, RIGHT half for the
-- right (press = instant, hold = stays up). BOTH flippers work at the same time
-- on firmware with device.touches() (2026.07.16.4+): hold one side and flip the
-- other, or trap the ball with both up — like a real table. On older firmware it
-- falls back to one-side-at-a-time. Keep the ball alive, smash the bumpers.
-- 3 balls. High score saved to hiscore.txt in this app's folder.
--
-- Needs T-UI firmware with screen.line — flippers are real solid segments the
-- ball bounces off, not just a visual.
------------------------------------------------------------------------------
local W, H = 320, 240
local br = 6                    -- ball radius
local bx, by = 160.0, 150.0     -- ball CENTER
local vx, vy = 0.0, 0.0
local grav = 0.16
local sc, balls, hs = 0, 3, 0
local st = 0                    -- 0 play · 1 game over · 2 waiting next ball
local waitUntil = 0
local leftFire, rightFire = 0, 0
local flashId, flashUntil = 0, 0
local jackUntil = 0
local launchSide = 1            -- alternate launch corners so no two balls repeat
local stillSince = 0            -- for the anti-stuck table nudge
local wasUpL, wasUpR = false, false -- last tick's flipper state (detects the flip moment)
local shownL, shownR = nil, nil     -- what's on screen (redraw flippers only on change)

-- flipper geometry: pivot, rest tip, raised tip (ball bounces off the pivot->tip
-- bar). Rest tips 44px apart: the ball (12px) genuinely FITS through the middle
-- gap — a real, drainable center like an actual table (28px only looked open;
-- with bar+ball thickness the lane was 4px, i.e. sealed).
local LF = {px=78,  py=204, rx=138, ry=226, ux=142, uy=192}
local RF = {px=242, py=204, rx=182, ry=226, ux=178, uy=192}

-- bumpers: {x, y, r, color, points}  (x,y = center)
local BUMP = {
  {100, 74, 16, 0xff2d55, 10},
  {160, 52, 18, 0x30d158, 10},
  {220, 74, 16, 0x0a84ff, 10},
  { 84, 126, 12, 0xffd60a, 25},
  {236, 126, 12, 0xffd60a, 25},
  {160, 108, 14, 0xbf5af2, 50},   -- center jackpot bumper
}

-- (the old center peg is gone — Jake wants a real open drain between the tips)

------------------------------------------------------------------------------
-- math helpers
local function clampSeg(px, py, qx, qy, cx, cy)
  local dx, dy = qx - px, qy - py
  local L2 = dx * dx + dy * dy
  local t = 0
  if L2 > 0 then t = ((cx - px) * dx + (cy - py) * dy) / L2 end
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return px + dx * t, py + dy * t, t
end

-- Reflect the ball off segment p->q if it overlaps. pad = half the bar thickness.
-- rest = bounciness (0..1). kick = launch speed of a FLIPPING bar: real-table
-- leverage — the tip sweeps much faster than the base, so the kick scales with
-- WHERE along the bar the ball sits (t: 0 = pivot, 1 = tip).
local function bounceSeg(px, py, qx, qy, pad, rest, kick)
  local ax, ay, t = clampSeg(px, py, qx, qy, bx, by)
  local nx, ny = bx - ax, by - ay
  local d2 = nx * nx + ny * ny
  local rr = br + pad
  if d2 >= rr * rr then return false end
  local d = math.sqrt(d2)
  if d < 0.001 then nx, ny, d = 0, -1, 1 end   -- dead-center: shove upward
  nx, ny = nx / d, ny / d
  bx = ax + nx * rr                              -- pop out of the bar
  by = ay + ny * rr
  local vn = vx * nx + vy * ny
  if vn < 0 then
    vx = (vx - 2 * vn * nx) * rest
    vy = (vy - 2 * vn * ny) * rest
  end
  if kick and kick > 0 then
    local lever = 0.3 + 0.95 * t   -- base = soft push, tip = full launch
    vx = vx + nx * kick * lever
    vy = vy + ny * kick * lever
  end
  return true
end

-- One flipper's physics for this tick. ONLY the flip itself launches the ball
-- (the tick the flipper starts rising): the swing arc is swept in 5 steps so the
-- bar can never teleport past the ball, and the kick carries the leverage above
-- (tip >> base). A flipper merely HELD up is a plain wall — it can't add energy,
-- exactly like leaning on a real flipper button.
local function flip(F, up, rose)
  if rose then
    for i = 0, 4 do
      local k = i / 4
      local tx = F.rx + (F.ux - F.rx) * k
      local ty = F.ry + (F.uy - F.ry) * k
      if bounceSeg(F.px, F.py, tx, ty, 7, 0.35, 9) then
        -- land the ball ABOVE the raised bar, whatever angle it was caught at —
        -- a flip must never leave (or throw) the ball underneath the flipper
        local ax, ay = clampSeg(F.px, F.py, F.ux, F.uy, bx, by)
        local dxp, dyp = F.ux - F.px, F.uy - F.py
        local L = math.sqrt(dxp * dxp + dyp * dyp)
        local nx, ny = dyp / L, -dxp / L
        if ny > 0 then nx, ny = -nx, -ny end   -- perpendicular that points UP
        bx, by = ax + nx * 13.5, ay + ny * 13.5
        if vy > -2.5 then vy = -2.5 end        -- a flip never sends the ball DOWN
        device.beep()
        return
      end
    end
  else
    local tx, ty = F.rx, F.ry
    if up then tx, ty = F.ux, F.uy end
    bounceSeg(F.px, F.py, tx, ty, 6, 0.55, 0)
  end
end

------------------------------------------------------------------------------
-- drawing
local function hud()
  screen.label(30, 6, 3, 'Score ' .. sc, 0xffffff)
  screen.label(31, 246, 3, 'Best ' .. hs, 0xffd60a)
  screen.label(32, 136, 3, 'Balls ' .. balls, 0x8e8e93)
end

local function msg(t, c)
  screen.label(33, 70, 150, t, c or 0xffffff)
end

local function drawBumpers()
  local now = device.time()
  for i = 1, #BUMP do
    local b = BUMP[i]
    local c = b[4]
    local halo = 0x1c1c3a
    if i == flashId and now < flashUntil then c = 0xffffff; halo = 0x3a3a6e end
    -- outer halo + glow ring + core = neon depth
    screen.box(50 + i, b[1] - b[3] - 5, b[2] - b[3] - 5, (b[3] + 5) * 2, (b[3] + 5) * 2, 0x12122a, 99)
    screen.box(40 + i, b[1] - b[3] - 2, b[2] - b[3] - 2, (b[3] + 2) * 2, (b[3] + 2) * 2, halo, 99)
    screen.box(20 + i, b[1] - b[3], b[2] - b[3], b[3] * 2, b[3] * 2, c, 99)
  end
end

local function drawFlipper(id, F, up)
  local tx, ty, c = F.rx, F.ry, 0xff9f0a
  if up then tx, ty, c = F.ux, F.uy, 0xffd60a end
  screen.line(id, F.px, F.py, tx, ty, 12, c)
end

local function drawTable()
  -- dark space-blue playfield with a sprinkle of stars
  screen.box(4, 4, 20, W - 8, H - 20, 0x0a0a24, 6)
  local sx = {36, 262, 140, 58, 288, 190, 96, 232}
  local sy = {46, 40, 84, 168, 120, 156, 108, 178}
  for i = 1, 8 do
    screen.box(60 + i, sx[i], sy[i], 2, 2, 0x2e2e5e, 99)
  end
  -- neon rails: top, upper sides, then angled funnels down to the flippers
  screen.line(11, 8, 24, 312, 24, 4, 0x0a84ff)        -- top
  screen.line(12, 8, 24, 8, 140, 4, 0x0a84ff)         -- left upper
  screen.line(13, 312, 24, 312, 140, 4, 0x0a84ff)     -- right upper
  screen.line(14, 8, 140, LF.px, LF.py, 6, 0x5e5ce6)  -- left funnel -> left flipper
  screen.line(15, 312, 140, RF.px, RF.py, 6, 0x5e5ce6) -- right funnel -> right flipper
end

------------------------------------------------------------------------------
-- game flow
local function launchBall()
  -- launch from alternating sides, angled toward the middle — never straight up
  launchSide = -launchSide
  bx = 160 + launchSide * 62 + math.random(-8, 8)
  by = 158.0
  vx = -launchSide * (1.0 + math.random(0, 10) / 10)   -- 1.0 .. 2.0 toward center
  vy = -7.6
  msg('', 0)
end

local function newGame()
  sc, balls = 0, 3
  st = 0
  hud()
  launchBall()
end

local function saveScore()
  if sc > hs then
    hs = sc
    store.write('hiscore.txt', tostring(hs))
  end
  hud()
end

-- press-and-hold: each on_drag event extends the raise window a bit, so the
-- flipper is up the instant the finger lands and stays up while held
local function fire(side)
  local now = device.time()
  if side == 1 then leftFire = now + 130 else rightFire = now + 130 end
end

-- both-paddles-at-once: ask the firmware for EVERY finger on the screen right now
-- (up to 2). The event path above only ever reports one point, so holding one side
-- used to block the other. nil-safe on firmware without device.touches().
local function heldSides()
  if not device.touches then return false, false end
  local L, R = false, false
  local n, x1, y1, x2, y2 = device.touches()
  if n >= 1 then if x1 < 160 then L = true else R = true end end
  if n >= 2 then if x2 < 160 then L = true else R = true end end
  return L, R
end

function on_open()
  math.randomseed(device.time())
  hs = math.floor(tonumber(store.read('hiscore.txt') or '') or 0)
  drawTable()
  drawBumpers()
  local hint = 'hold left / right to flip'
  if device.touches then hint = 'hold left + right - both flip!' end
  screen.label(34, 58, 224, hint, 0x6e6e73)
  newGame()
end

function on_touch(x, y)
  if st == 1 then newGame() return end
  if x < 160 then fire(1) else fire(2) end
end

function on_drag(x, y)
  if st ~= 0 then return end
  if x < 160 then fire(1) else fire(2) end
end

function on_tick(dt)
  local now = device.time()
  -- a side is UP if a finger is on it right now (multi-touch, instant release) OR
  -- its tap window is still open (catches taps shorter than one 33ms tick)
  local heldL, heldR = heldSides()
  local upL, upR = heldL or now < leftFire, heldR or now < rightFire

  if st == 2 and now >= waitUntil then
    launchBall()
    st = 0
  end

  if st == 0 then
    vy = vy + grav
    if vx > 7 then vx = 7 elseif vx < -7 then vx = -7 end
    if vy > 8.5 then vy = 8.5 elseif vy < -9 then vy = -9 end
    bx = bx + vx
    by = by + vy

    -- straight outer walls (upper section)
    if bx < 8 + br then bx = 8 + br; vx = math.abs(vx) * 0.85 end
    if bx > 312 - br then bx = 312 - br; vx = -math.abs(vx) * 0.85 end
    if by < 24 + br then by = 24 + br; vy = math.abs(vy) * 0.85 end

    -- angled funnels guide the ball toward the flippers
    bounceSeg(8, 140, LF.px, LF.py, 3, 0.8, 0)
    bounceSeg(312, 140, RF.px, RF.py, 3, 0.8, 0)

    -- bumpers: kick away from center (with a little jitter so the same shot
    -- never repeats forever), score + flash + beep
    for i = 1, #BUMP do
      local b = BUMP[i]
      local dx, dy = bx - b[1], by - b[2]
      local rr = b[3] + br
      if dx * dx + dy * dy < rr * rr then
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 1 then d = 1 end
        local nx, ny = dx / d, dy / d
        if ny > 0.8 then               -- never kick STRAIGHT down (unsavable drain)
          ny = 0.8
          local sx = 0.6
          if nx < 0 or (nx == 0 and math.random(2) == 1) then sx = -0.6 end
          nx = sx
        end
        vx = nx * 5.8 + (math.random(0, 16) - 8) / 10
        vy = ny * 5.8
        sc = sc + b[5]
        flashId, flashUntil = i, now + 140
        if b[5] >= 50 then
          jackUntil = now + 900
          screen.label(35, 118, 132, 'JACKPOT!', 0xbf5af2)
        end
        hud()
        drawBumpers()
        device.beep()
      end
    end
    if flashId ~= 0 and now >= flashUntil then
      flashId = 0
      drawBumpers()
    end
    if jackUntil ~= 0 and now >= jackUntil then
      jackUntil = 0
      screen.hide(35)
    end

    -- flippers (see flip() above: kick on the flip moment, wall when held)
    flip(LF, upL, upL and not wasUpL)
    flip(RF, upR, upR and not wasUpR)

    -- anti-stuck: a ball resting motionless down low gets a little table nudge
    if math.abs(vx) + math.abs(vy) < 0.5 and by > 195 then
      if stillSince == 0 then stillSince = now end
      if now - stillSince > 900 then
        stillSince = 0
        vx = (math.random(0, 16) - 8) / 5
        vy = -1.2
      end
    else
      stillSince = 0
    end

    -- drain (through the gap between the flipper tips)
    if by - br > H then
      balls = balls - 1
      if balls <= 0 then
        st = 1
        saveScore()
        msg('Game Over - tap to retry', 0xff2d55)
      else
        st = 2
        waitUntil = now + 700
        hud()
        msg('Ball lost!', 0xff9f0a)
      end
    end
  end

  -- redraw a flipper only when it actually moved — repainting them every tick
  -- is what made the whole game stutter
  if upL ~= shownL then drawFlipper(2, LF, upL); shownL = upL end
  if upR ~= shownR then drawFlipper(3, RF, upR); shownR = upR end
  wasUpL, wasUpR = upL, upR

  if st == 0 then
    -- soft glow under the ball, then the ball itself
    screen.box(6, math.floor(bx - br) - 3, math.floor(by - br) - 3, br * 2 + 6, br * 2 + 6, 0x26264e, 99)
    screen.box(1, math.floor(bx - br), math.floor(by - br), br * 2, br * 2, 0xffffff, 99)
  else
    screen.hide(1)
    screen.hide(6)
  end
end
