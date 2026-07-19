-- Interval Timer for T-UI ------------------------------------------------------
-- Repeating work/rest timer for workouts, drills, stretching, anything on a clock.
-- Set the work and rest seconds with the +/- buttons, tap START, and it loops:
-- beep at every changeover, a louder double beep when the whole set is done.
--
-- The built-in Timer app counts down once; this one keeps cycling and counts rounds.
-- Your settings are remembered between sessions.
----------------------------------------------------------------------------------
local work, rest, setRounds = 30, 15, 8
local running = false
local phase = "work"      -- "work" | "rest" | "done"
local phaseStart = 0
local round = 1

local function save()
    store.write("intervals.txt", table.concat({work, rest, setRounds}, ","))
end

local function restore()
    local s = store.read("intervals.txt")
    if not s then return end
    local v = {}
    for x in s:gmatch("%d+") do v[#v + 1] = tonumber(x) end
    if #v >= 3 then
        work, rest, setRounds = v[1], v[2], v[3]
        if work < 5 then work = 5 end
        if rest < 0 then rest = 0 end
        if setRounds < 1 then setRounds = 1 end
    end
end

local function secsLeft()
    local total = (phase == "work") and work or rest
    local left = total - math.floor((device.time() - phaseStart) / 1000)
    if left < 0 then left = 0 end
    return left
end

-- Rows of adjustable settings: label, -, value, +
local function drawSetting(base, y, name, value)
    screen.label(base, 14, y + 4, name, 0xffffff)
    screen.box(base + 1, 120, y, 34, 26, 0x2c2c2e)
    screen.label(base + 2, 133, y + 5, "-", 0xff453a)
    local t = tostring(value)
    screen.label(base + 3, 178 - (#t * 5), y + 5, t, 0xffffff)
    screen.box(base + 4, 210, y, 34, 26, 0x2c2c2e)
    screen.label(base + 5, 223, y + 5, "+", 0x30d158)
end

local function hideSettings()
    for b = 10, 30, 10 do
        for k = 0, 5 do screen.hide(b + k) end
    end
end

local function draw()
    if running or phase == "done" then
        hideSettings()
        screen.label(1, 8, 6, phase == "done" and "Done!" or ("Round " .. round .. " of " .. setRounds), 0x8e8e93)
        local col = (phase == "work") and 0x30d158 or (phase == "rest" and 0x0a84ff or 0xffd60a)
        local word = (phase == "work") and "WORK" or (phase == "rest" and "REST" or "FINISHED")
        screen.label(2, 120, 60, word, col)
        if phase ~= "done" then
            local t = tostring(secsLeft())
            screen.label(3, 150 - (#t * 5), 110, t, 0xffffff)
        else
            screen.hide(3)
        end
        screen.box(4, 90, 180, 140, 40, 0x2c2c2e)
        screen.label(5, 120, 192, phase == "done" and "AGAIN" or "STOP", 0xffffff)
    else
        screen.label(1, 8, 6, "Interval timer", 0x8e8e93)
        screen.hide(2)
        screen.hide(3)
        drawSetting(10, 40, "Work (s)", work)
        drawSetting(20, 76, "Rest (s)", rest)
        drawSetting(30, 112, "Rounds", setRounds)
        screen.box(4, 90, 180, 140, 40, 0x30d158)
        screen.label(5, 130, 192, "START", 0x000000)
    end
end

function on_open()
    restore()
    draw()
end

local function startRun()
    running = true
    phase = "work"
    round = 1
    phaseStart = device.time()
    device.beep(true)
end

function on_touch(x, y)
    -- the big button at the bottom
    if y >= 180 and y <= 220 and x >= 90 and x <= 230 then
        if running then
            running = false
            phase = "work"
            save()
        else
            startRun()
        end
        draw()
        return
    end

    if running or phase == "done" then return end

    -- settings rows: work / rest / rounds
    local row, base
    if y >= 40 and y < 66 then row, base = "work", 10
    elseif y >= 76 and y < 102 then row, base = "rest", 20
    elseif y >= 112 and y < 138 then row, base = "rounds", 30
    else return end

    local delta
    if x >= 120 and x < 154 then delta = -1
    elseif x >= 210 and x < 244 then delta = 1
    else return end

    -- seconds move in fives (fiddling one second at a time on a touchscreen is misery)
    if row == "work" then
        work = work + delta * 5
        if work < 5 then work = 5 end
        if work > 900 then work = 900 end
    elseif row == "rest" then
        rest = rest + delta * 5
        if rest < 0 then rest = 0 end
        if rest > 900 then rest = 900 end
    else
        setRounds = setRounds + delta
        if setRounds < 1 then setRounds = 1 end
        if setRounds > 99 then setRounds = 99 end
    end
    device.beep()
    save()
    draw()
end

function on_tick()
    if not running then return end
    if secsLeft() > 0 then
        draw()
        return
    end

    if phase == "work" then
        if rest > 0 then
            phase = "rest"
            phaseStart = device.time()
            device.beep()
        else
            round = round + 1
            phaseStart = device.time()
            device.beep()
        end
    else
        round = round + 1
        phase = "work"
        phaseStart = device.time()
        device.beep()
    end

    if round > setRounds then
        running = false
        phase = "done"
        device.beep(true)
    end
    draw()
end
