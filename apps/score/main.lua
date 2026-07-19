-- Score Keeper for T-UI ---------------------------------------------------------
-- Keeps score for 2 to 4 players. Tap + or - under a player to change their score.
-- Tap the number of players at the top to switch between 2, 3 and 4. Everything is
-- saved as you go, so closing the app (or the battery dying) doesn't lose the game.
-- "New game" needs a second tap to confirm, so a stray finger can't wipe the score.
----------------------------------------------------------------------------------
local W, H = 320, 240
local players = 2
local score = {0, 0, 0, 0}
local confirmReset = false
local confirmUntil = 0

-- ids: 1-9 chrome, 10s per-player boxes, 20s names, 30s scores, 40s +, 50s -
local COL = {0x30d158, 0x0a84ff, 0xff9f0a, 0xbf5af2}
local NAMES = {"P1", "P2", "P3", "P4"}

local function save()
    -- one short line: player count then the four scores
    store.write("score.txt", table.concat({players, score[1], score[2], score[3], score[4]}, ","))
end

local function restore()
    local s = store.read("score.txt")
    if not s then return end
    local v = {}
    for n in s:gmatch("-?%d+") do v[#v + 1] = tonumber(n) end
    if #v >= 5 then
        players = v[1]
        if players < 2 or players > 4 then players = 2 end
        for i = 1, 4 do score[i] = v[i + 1] or 0 end
    end
end

-- Each player gets a vertical column; width depends on how many are playing.
local function colX(i)
    local w = W / players
    return math.floor((i - 1) * w), math.floor(w)
end

local function draw()
    screen.label(1, 8, 6, players .. " players (tap)", 0x8e8e93)
    screen.label(2, 210, 6, confirmReset and "Sure? tap" or "New game", confirmReset and 0xff453a or 0x8e8e93)

    for i = 1, 4 do
        local base = i * 10
        if i <= players then
            local x, w = colX(i)
            screen.box(base, x + 3, 26, w - 6, 150, 0x1c1c20)
            screen.label(base + 1, x + 10, 32, NAMES[i], COL[i])
            -- the score itself, roughly centred in the column
            local txt = tostring(score[i])
            local tx = x + math.floor(w / 2) - (#txt * 5)
            screen.label(base + 2, tx, 90, txt, 0xffffff)
            -- + and - buttons
            screen.box(base + 3, x + 8, 182, w - 16, 24, 0x2c2c2e)
            screen.label(base + 4, x + math.floor(w / 2) - 4, 187, "+", 0x30d158)
            screen.box(base + 5, x + 8, 210, w - 16, 24, 0x2c2c2e)
            screen.label(base + 6, x + math.floor(w / 2) - 4, 215, "-", 0xff453a)
        else
            for k = 0, 6 do screen.hide(base + k) end
        end
    end
end

function on_open()
    restore()
    draw()
end

function on_touch(x, y)
    -- top row: player count on the left, new game on the right
    if y < 24 then
        if x > 200 then
            if confirmReset and device.time() < confirmUntil then
                for i = 1, 4 do score[i] = 0 end
                confirmReset = false
                device.beep(true)
            else
                confirmReset = true
                confirmUntil = device.time() + 4000
                device.beep()
            end
        else
            players = players + 1
            if players > 4 then players = 2 end
            confirmReset = false
            device.beep()
        end
        save()
        draw()
        return
    end

    confirmReset = false

    -- which column was tapped
    local w = W / players
    local i = math.floor(x / w) + 1
    if i < 1 or i > players then return end

    if y >= 182 and y < 206 then
        score[i] = score[i] + 1
        device.beep()
    elseif y >= 210 then
        score[i] = score[i] - 1
        device.beep()
    else
        return
    end
    save()
    draw()
end

function on_tick()
    -- let the "Sure?" prompt lapse on its own
    if confirmReset and device.time() >= confirmUntil then
        confirmReset = false
        draw()
    end
end
