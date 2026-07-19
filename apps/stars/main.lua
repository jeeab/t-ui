-- Starfield for T-UI ------------------------------------------------------------
-- Fly through 220 stars. DRAG anywhere to steer left and right; let go and it
-- straightens up. Tap the WARP button in the bottom-left corner to change speed.
--
-- This one exists to show what the canvas can do: 220 moving stars plus streaks is
-- far past the 80-object ceiling of the screen.* API. Every star is a pixel drawn
-- straight into a frame buffer, so the whole thing is one object on screen.
----------------------------------------------------------------------------------
local W, H = 320, 240
local CX, CY = W / 2, H / 2
local COUNT = 220

local stars = {}
local warp = 1           -- 1, 2 or 3
local drift = 0          -- current steering
local steerTo = 0        -- where dragging wants it
local best = 0
local travelled = 0
local hintUntil = 0
local ok = false

-- the warp button, bottom-left
local BX, BY, BW, BH = 6, 202, 74, 32

-- Sprite art: one character per pixel, blank = see-through. Three frames so the ship
-- banks into the turn. 11 wide, 8 tall, drawn at 3x so it reads on a 320x240 screen.
local SHIP_W, SHIP_SCALE = 11, 3
local PALETTE = {
    ["W"] = 0xf2f6ff, -- hull highlight
    ["B"] = 0x8fa9c8, -- hull shadow
    ["C"] = 0x0a84ff, -- cockpit
    ["F"] = 0xff9f0a, -- engine flame
    ["R"] = 0xff453a, -- flame core
}
local SHIP = {
    -- banking left
    "    WW     " ..
    "   WWWB    " ..
    "  WWCWBB   " ..
    " WWWCWWBB  " ..
    "WWWWWWWBBB " ..
    " W  FFF  B " ..
    "    RFR    " ..
    "     R     ",
    -- level
    "     W     " ..
    "    WWW    " ..
    "   WWCWB   " ..
    "  WWWCWBB  " ..
    " WWWWWWBBB " ..
    "W   FFF   B" ..
    "    RFR    " ..
    "     R     ",
    -- banking right
    "     WW    " ..
    "    BWWW   " ..
    "   BBWCWW  " ..
    "  BBWWCWWW " ..
    " BBBWWWWWWW" ..
    " B  FFF  W " ..
    "    RFR    " ..
    "     R     ",
}

local function reseed(s, atFront)
    -- x,y are a direction from the centre; z is depth (small z = right in your face).
    -- At z = 1 the whole spread lands on screen, so new stars always appear.
    s.x = (math.random() - 0.5) * 2
    s.y = (math.random() - 0.5) * 2
    s.z = atFront and (math.random() * 0.8 + 0.2) or 1.0
    local shade = math.random()
    if shade > 0.92 then s.c = 0x9ad0ff
    elseif shade > 0.80 then s.c = 0xffe9a8
    else s.c = 0xffffff end
end

function on_open()
    ok = canvas.begin()
    if not ok then
        screen.label(1, 40, 110, "Canvas unavailable", 0xff453a)
        return
    end
    best = tonumber(store.read("best.txt") or "0") or 0
    for i = 1, COUNT do
        stars[i] = {}
        reseed(stars[i], true)
    end
    -- controls are not obvious on a blank starfield; say so for the first few seconds
    hintUntil = device.time() + 5000
    screen.label(2, 38, 8, "drag or A / D to steer, space = warp", 0x8e8e93)
end

-- A tap only does something in the warp button. Everywhere else belongs to steering —
-- and note a drag BEGINS with a touch, so anything global here would fire mid-steer.
function on_touch(x, y)
    if not ok then return end
    if x >= BX and x <= BX + BW and y >= BY and y <= BY + BH then
        warp = warp + 1
        if warp > 3 then warp = 1 end
        device.beep()
    end
end

function on_drag(x)
    if not ok then return end
    steerTo = (x - CX) / CX      -- -1 (hard left) .. +1 (hard right)
end

-- Physical keyboard. Printable keys arrive as themselves ("a"), the rest by name
-- ("left", "enter"). Each press nudges the steering, which then decays like a drag
-- does, so holding a key down steers continuously and releasing straightens up.
function on_key(k)
    if not ok then return end
    if k == "left" or k == "a" then
        steerTo = -1
    elseif k == "right" or k == "d" then
        steerTo = 1
    elseif k == " " or k == "enter" or k == "w" then
        warp = warp + 1
        if warp > 3 then warp = 1 end
        device.beep()
    end
end

function on_tick()
    if not ok then return end

    -- Ease towards where the finger is, and fall back to straight when it lets go.
    -- Without the decay the field would keep turning forever after one drag.
    drift = drift + (steerTo - drift) * 0.18
    steerTo = steerTo * 0.90

    canvas.clear(0x000000)

    -- Steering moves the point you're flying towards. Nudging each star's own position
    -- (the first attempt) shifted the picture by about 1.5 pixels — technically working,
    -- completely invisible. Moving the vanishing point swings the whole field, and the
    -- per-star nudge below then makes near stars sweep further than distant ones, which
    -- is what sells it as turning rather than sliding.
    local vpx = CX - drift * 130

    local speed = warp * 0.012
    for i = 1, COUNT do
        local s = stars[i]
        local pz = s.z
        s.z = s.z - speed
        if s.z <= 0.02 then
            reseed(s, false)
            pz = s.z
        end

        -- Note the minus: steering left must sweep the stars RIGHT, the same way the
        -- vanishing point moves. With a plus these two cancelled out and the whole effect
        -- nearly vanished.
        s.x = s.x - drift * 0.010 / s.z

        local px = vpx + (s.x / s.z) * CX
        local py = CY + (s.y / s.z) * CY

        if px < 0 or px >= W or py < 0 or py >= H then
            reseed(s, false)
        elseif s.z < 0.35 then
            -- close stars get a motion streak back towards where they came from
            local ox = vpx + (s.x / pz) * CX
            local oy = CY + (s.y / pz) * CY
            canvas.line(math.floor(ox), math.floor(oy), math.floor(px), math.floor(py), s.c)
        else
            canvas.pixel(math.floor(px), math.floor(py), s.c)
        end
    end

    -- Your ship, banking into the turn. Sitting low and centred so the stars stream
    -- past it; the frame is chosen from how hard you're currently steering.
    local frame = 2
    if drift < -0.25 then frame = 1 elseif drift > 0.25 then frame = 3 end
    local shipW = SHIP_W * SHIP_SCALE
    canvas.sprite(CX - shipW / 2 - drift * 18, 168, SHIP_W, SHIP[frame], PALETTE, SHIP_SCALE)

    -- warp button, drawn on the canvas so it can't eat into the element budget
    canvas.rect(BX, BY, BW, BH, 0x1c1c20)
    canvas.rect(BX, BY, BW, 2, 0x30d158)
    for i = 1, warp do
        canvas.rect(BX + 8 + (i - 1) * 14, BY + 12, 10, 10, 0x30d158)
    end

    canvas.flip()

    if hintUntil > 0 and device.time() > hintUntil then
        hintUntil = 0
        screen.hide(2)
    end

    travelled = travelled + warp
    if travelled > best then
        best = travelled
        if travelled % 500 < warp then store.write("best.txt", tostring(math.floor(best))) end
    end
end

function on_close()
    if ok then store.write("best.txt", tostring(math.floor(best))) end
end
