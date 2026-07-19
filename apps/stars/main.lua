-- Starfield for T-UI ------------------------------------------------------------
-- Fly through 220 stars. Drag left/right to steer, tap to change speed.
--
-- This one exists to show what the canvas can do: 220 moving stars, plus streaks,
-- is far past the 80-object ceiling of the screen.* API. Every star is a pixel drawn
-- straight into a frame buffer, so the whole thing is one object on screen.
----------------------------------------------------------------------------------
local W, H = 320, 240
local CX, CY = W / 2, H / 2
local COUNT = 220

local stars = {}
local speed = 1.0
local drift = 0          -- steering, set by dragging
local best = 0           -- furthest distance travelled
local travelled = 0
local paused = false

local function reseed(s, near)
    -- x,y are direction from the centre; z is depth. Small z = close to your face.
    s.x = (math.random() - 0.5) * 2
    s.y = (math.random() - 0.5) * 2
    s.z = near and (math.random() * 0.8 + 0.2) or 1.0
    -- a few stars are brighter, which reads as depth
    local shade = math.random()
    if shade > 0.92 then s.c = 0x9ad0ff
    elseif shade > 0.80 then s.c = 0xffe9a8
    else s.c = 0xffffff end
end

function on_open()
    if not canvas.begin() then
        -- No frame buffer available: say so plainly rather than showing a black screen.
        screen.label(1, 40, 110, "Canvas unavailable", 0xff453a)
        return
    end
    best = tonumber(store.read("best.txt") or "0") or 0
    for i = 1, COUNT do
        stars[i] = {}
        reseed(stars[i], true)
    end
end

function on_touch()
    paused = not paused
    if not paused then
        speed = speed + 0.5
        if speed > 3.0 then speed = 1.0 end
    end
    device.beep()
end

function on_drag(x)
    -- steer: how far the finger is from the middle
    drift = (x - CX) / CX * 2.5
end

function on_tick()
    if paused then return end

    canvas.clear(0x000000)

    for i = 1, COUNT do
        local s = stars[i]
        local pz = s.z
        s.z = s.z - 0.012 * speed
        if s.z <= 0.02 then
            reseed(s, false)
            pz = s.z
        end

        s.x = s.x + drift * 0.0009 / s.z

        local px = CX + (s.x / s.z) * CX
        local py = CY + (s.y / s.z) * CY

        if px < 0 or px >= W or py < 0 or py >= H then
            reseed(s, false)
        else
            -- close stars get a motion streak back towards where they came from
            if s.z < 0.35 then
                local ox = CX + (s.x / pz) * CX
                local oy = CY + (s.y / pz) * CY
                canvas.line(math.floor(ox), math.floor(oy), math.floor(px), math.floor(py), s.c)
            else
                canvas.pixel(math.floor(px), math.floor(py), s.c)
            end
        end
    end

    travelled = travelled + speed
    if travelled > best then
        best = travelled
        if travelled % 500 < speed then store.write("best.txt", tostring(math.floor(best))) end
    end

    canvas.flip()
end

function on_close()
    store.write("best.txt", tostring(math.floor(best)))
end
