-- Box Breathing for T-UI -------------------------------------------------------
-- Breathe in for 4, hold for 4, out for 4, hold for 4. A square grows and shrinks
-- with you and there's a gentle beep at each corner, so you can follow it with your
-- eyes closed. Tap to start or stop. It counts the rounds you've completed.
--
-- Timing comes from device.time() rather than counting frames, so it stays honest
-- even if the screen is busy.
----------------------------------------------------------------------------------
local PHASES = {
    {name = "Breathe in", secs = 4, colour = 0x30d158},
    {name = "Hold",       secs = 4, colour = 0x0a84ff},
    {name = "Breathe out",secs = 4, colour = 0xbf5af2},
    {name = "Hold",       secs = 4, colour = 0x0a84ff},
}

local running = false
local phase = 1
local phaseStart = 0
local rounds = 0
local lastBox = -1

local MIN, MAX = 40, 150   -- square size at empty lungs / full lungs

local function save() store.write("rounds.txt", tostring(rounds)) end

local function fraction()
    local p = PHASES[phase]
    local elapsed = device.time() - phaseStart
    local f = elapsed / (p.secs * 1000)
    if f < 0 then f = 0 end
    if f > 1 then f = 1 end
    return f
end

-- How big the square should be right now: growing while breathing in, shrinking
-- while breathing out, steady on the holds.
local function boxSize()
    local f = fraction()
    if phase == 1 then return MIN + (MAX - MIN) * f
    elseif phase == 2 then return MAX
    elseif phase == 3 then return MAX - (MAX - MIN) * f
    else return MIN end
end

local function draw()
    local p = PHASES[phase]
    screen.label(1, 8, 6, "Box breathing", 0x8e8e93)
    screen.label(2, 230, 6, "rounds " .. rounds, 0x8e8e93)

    if not running then
        screen.label(3, 96, 110, "Tap to start", 0xffffff)
        screen.hide(4)
        screen.hide(5)
        screen.hide(6)
        return
    end

    local size = math.floor(boxSize())
    -- only redraw the square when it actually changes size (saves needless work)
    if size ~= lastBox then
        lastBox = size
        local x = 160 - math.floor(size / 2)
        local y = 130 - math.floor(size / 2)
        screen.box(4, x, y, size, size, p.colour)
    end

    screen.label(3, 110, 30, p.name, p.colour)
    local left = math.ceil(p.secs - fraction() * p.secs)
    if left < 1 then left = 1 end
    screen.label(5, 156, 214, tostring(left), 0xffffff)
    screen.label(6, 88, 214, "tap to stop", 0x8e8e93)
end

function on_open()
    rounds = tonumber(store.read("rounds.txt") or "0") or 0
    draw()
end

function on_touch()
    running = not running
    if running then
        phase = 1
        phaseStart = device.time()
        lastBox = -1
        device.beep()
    else
        screen.hide(4)
        screen.hide(5)
        save()
    end
    draw()
end

function on_tick()
    if not running then return end
    local p = PHASES[phase]
    if device.time() - phaseStart >= p.secs * 1000 then
        phase = phase + 1
        if phase > #PHASES then
            phase = 1
            rounds = rounds + 1
            save()
            device.beep(true)   -- louder beep completes a round
        else
            device.beep()
        end
        phaseStart = device.time()
    end
    draw()
end

function on_close()
    save()
end
