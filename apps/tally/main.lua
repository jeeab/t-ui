-- Tally Counter for T-UI -------------------------------------------------------
-- Four independent counters. Tap the big coloured block to count up, the small
-- "-1" under it to correct a mistake. Long-ish tap on a counter's label zeroes
-- just that one (it asks first). Everything is saved as you count, so you can
-- close the app, let the battery die, and come back to the same numbers.
--
-- For counting anything: inventory, laps, birds, cars, people through a door.
----------------------------------------------------------------------------------
local COLS = {0x30d158, 0x0a84ff, 0xff9f0a, 0xbf5af2}
local NAMES = {"A", "B", "C", "D"}
local n = {0, 0, 0, 0}
local armed = 0      -- which counter is waiting for a reset confirmation
local armedUntil = 0

local function save()
    store.write("tally.txt", table.concat(n, ","))
end

local function restore()
    local s = store.read("tally.txt")
    if not s then return end
    local i = 1
    for v in s:gmatch("-?%d+") do
        if i <= 4 then n[i] = tonumber(v) end
        i = i + 1
    end
end

-- 2x2 grid of counters
local function cell(i)
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    return col * 160, row * 104 + 26
end

local function draw()
    screen.label(1, 8, 6, "Tally", 0xffffff)
    screen.label(2, 190, 6, armed > 0 and ("Zero " .. NAMES[armed] .. "? tap") or "tap name to zero", 0x8e8e93)

    for i = 1, 4 do
        local x, y = cell(i)
        local b = i * 10
        screen.box(b, x + 4, y, 152, 96, 0x1c1c20)
        -- name doubles as the reset button
        screen.label(b + 1, x + 12, y + 6, NAMES[i], armed == i and 0xff453a or COLS[i])
        local t = tostring(n[i])
        screen.label(b + 2, x + 74 - (#t * 5), y + 40, t, 0xffffff)
        screen.box(b + 3, x + 108, y + 68, 44, 22, 0x2c2c2e)
        screen.label(b + 4, x + 122, y + 72, "-1", 0xff453a)
    end
end

function on_open()
    restore()
    draw()
end

function on_touch(x, y)
    if y < 24 then return end

    local col = x < 160 and 0 or 1
    local row = y < 130 and 0 or 1
    local i = row * 2 + col + 1
    if i < 1 or i > 4 then return end

    local cx, cy = cell(i)
    local ry = y - cy

    if ry < 0 then return end

    if ry >= 68 and ry <= 92 and x >= cx + 108 then
        -- the -1 button
        n[i] = n[i] - 1
        armed = 0
        device.beep()
    elseif ry < 26 and x < cx + 60 then
        -- tapped the name: arm, then confirm
        if armed == i and device.time() < armedUntil then
            n[i] = 0
            armed = 0
            device.beep(true)
        else
            armed = i
            armedUntil = device.time() + 4000
            device.beep()
        end
    else
        -- anywhere else in the block counts up
        n[i] = n[i] + 1
        armed = 0
        device.beep()
    end
    save()
    draw()
end

function on_tick()
    if armed > 0 and device.time() >= armedUntil then
        armed = 0
        draw()
    end
end
