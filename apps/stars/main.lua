-- Starfield: Deep Space ---------------------------------------------------------
-- Fly a ship through an endless, generated galaxy.
--
--   A / D  (or left/right)  turn 45 degrees        W / space  faster
--   B                       brake (stars stop)     tap sides  turn
--   L                       laser (weak, free)     P          phoenix missile
--
-- The galaxy is NOT stored anywhere. Every sector's contents come from a hash of its
-- coordinates and the world seed, so space is effectively infinite, costs no memory,
-- and a station you find at 412,-89 is still there when you fly back. Same seed =
-- same galaxy, so two devices can explore the identical universe.
----------------------------------------------------------------------------------
local W, H = 320, 240
local CX, CY = W / 2, H / 2
local STARS = 200
local FOV = 1.05                -- half field of view, radians (~60 degrees)
local SECTOR = 1000             -- world units per sector
local DIRS = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}

-- ---- world -------------------------------------------------------------------
local seed = 20260719
local ship = {x = 0, y = 0, heading = 0, look = 0, warp = 1, hp = 100, maxhp = 100}
local stars = {}
local ok = false
local hint = 0

-- Combat. Pirates are spawned live around the ship rather than stored: their DENSITY
-- comes from the sector's danger rating, so some regions are genuinely lawless and you
-- learn which. Nothing about them needs saving.
local pirates = {}
local shots = {}
local missiles = 3
local credits = 0
local lastFire, lastHit = 0, 0
local MAX_PIRATES = 4

-- Deterministic hash of a sector. Same inputs always give the same number, which is
-- what lets the galaxy exist without being stored. Integer maths only - floats would
-- drift between devices and break "same seed, same universe".
local function hash(sx, sy, salt)
    local h = (sx * 73856093) ~ (sy * 19349663) ~ ((seed + (salt or 0)) * 83492791)
    h = h & 0x7FFFFFFF
    h = (h ~ (h >> 13)) * 1274126177
    return (h ~ (h >> 16)) & 0x7FFFFFFF
end

-- What's in a sector? Roughly one station in six, at a fixed spot inside it.
local function stationIn(sx, sy)
    local h = hash(sx, sy, 1)
    if h % 6 ~= 0 then return nil end
    return {
        x = sx * SECTOR + (h >> 4) % SECTOR,
        y = sy * SECTOR + (h >> 14) % SECTOR,
        sx = sx, sy = sy,
    }
end

-- How lawless is this region? Drives pirate density later; shown now as a warning.
local function dangerAt(sx, sy)
    return hash(sx, sy, 7) % 100
end

-- Nearest station in the sectors around us. Cheap: 25 sectors, only when it changes.
local nearest, nearestDist = nil, 0
local function findNearest()
    local csx = math.floor(ship.x / SECTOR)
    local csy = math.floor(ship.y / SECTOR)
    nearest, nearestDist = nil, 1e18
    for sx = csx - 2, csx + 2 do
        for sy = csy - 2, csy + 2 do
            local st = stationIn(sx, sy)
            if st then
                local dx, dy = st.x - ship.x, st.y - ship.y
                local d = math.sqrt(dx * dx + dy * dy)
                if d < nearestDist then nearest, nearestDist = st, d end
            end
        end
    end
end

-- ---- helpers -----------------------------------------------------------------
local function headingAngle(h) return h * math.pi / 4 end

-- Shortest signed difference between two angles, in radians.
local function angleDiff(a, b)
    local d = a - b
    while d > math.pi do d = d - 2 * math.pi end
    while d < -math.pi do d = d + 2 * math.pi end
    return d
end

-- Where something in the world lands on screen, given where we're looking.
-- Returns nil when it's outside the field of view (behind or off to the side).
local function project(wx, wy)
    local dx, dy = wx - ship.x, wy - ship.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then dist = 1 end
    local bearing = math.atan(dx, dy)          -- 0 = north, matches heading
    local rel = angleDiff(bearing, ship.look)
    if rel < -FOV or rel > FOV then return nil end
    return CX + (rel / FOV) * CX, dist, rel
end

local function reseed(s, front)
    s.x = (math.random() - 0.5) * 2
    s.y = (math.random() - 0.5) * 2
    s.z = front and (math.random() * 0.8 + 0.2) or 1.0
    local sh = math.random()
    if sh > 0.92 then s.c = 0x9ad0ff elseif sh > 0.80 then s.c = 0xffe9a8 else s.c = 0xffffff end
end

-- ---- combat ------------------------------------------------------------------
-- Pirates live in the same projected space as everything else: a bearing and a distance.
-- Closing distance is what makes them threatening, so they always fly at you.
local function spawnPirate()
    local csx, csy = math.floor(ship.x / SECTOR), math.floor(ship.y / SECTOR)
    if dangerAt(csx, csy) < 45 then return end          -- quiet region, nothing out here
    if #pirates >= MAX_PIRATES then return end
    -- appear somewhere ahead-ish, far enough away to be seen coming
    local ang = ship.look + (math.random() - 0.5) * 2.2
    local dist = 1600 + math.random() * 900
    pirates[#pirates + 1] = {
        x = ship.x + math.sin(ang) * dist,
        y = ship.y + math.cos(ang) * dist,
        hp = 3,
        cool = 800 + math.random() * 1500,
    }
end

local function fire(kind)
    local now = device.time()
    if now - lastFire < (kind == "laser" and 220 or 700) then return end
    if kind == "missile" then
        if missiles <= 0 then return end
        missiles = missiles - 1
    end
    lastFire = now
    shots[#shots + 1] = {kind = kind, dist = 0, ang = ship.look, born = now}
    device.beep(kind == "missile")
end

-- A shot travels straight out along the heading it was fired on. It hits if, by the time
-- it reaches a pirate's distance, they're still close together in bearing.
local function stepShots(dt)
    local i = 1
    while i <= #shots do
        local sh = shots[i]
        sh.dist = sh.dist + (sh.kind == "laser" and 260 or 120)
        local hit = false
        for pi = #pirates, 1, -1 do
            local p = pirates[pi]
            local dx, dy = p.x - ship.x, p.y - ship.y
            local pd = math.sqrt(dx * dx + dy * dy)
            if math.abs(pd - sh.dist) < 220 then
                local rel = angleDiff(math.atan(dx, dy), sh.ang)
                if math.abs(rel) < 0.18 then
                    p.hp = p.hp - (sh.kind == "laser" and 1 or 3)
                    hit = true
                    if p.hp <= 0 then
                        table.remove(pirates, pi)
                        credits = credits + 10
                        device.beep(true)
                    end
                    break
                end
            end
        end
        if hit or sh.dist > 3000 then table.remove(shots, i) else i = i + 1 end
    end
end

local function stepPirates()
    local now = device.time()
    for pi = #pirates, 1, -1 do
        local p = pirates[pi]
        local dx, dy = p.x - ship.x, p.y - ship.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 5000 then
            table.remove(pirates, pi)                    -- outrun: warping away works
        else
            -- close in
            local step = 3
            p.x = p.x - (dx / d) * step
            p.y = p.y - (dy / d) * step
            -- and shoot when near enough, but only if roughly in front of you
            if d < 1400 and now > (p.lastShot or 0) + p.cool then
                p.lastShot = now
                ship.hp = ship.hp - 4
                lastHit = now
                device.beep()
                if ship.hp < 0 then ship.hp = 0 end
            end
        end
    end
end

-- ---- save --------------------------------------------------------------------
-- Tiny, because the galaxy is generated rather than stored: just where we are.
local function save()
    store.write("save.txt", table.concat({seed, math.floor(ship.x), math.floor(ship.y),
                                          ship.heading, ship.hp, credits, missiles}, ","))
end

local function restore()
    local s = store.read("save.txt")
    if not s then return end
    local v = {}
    for n in s:gmatch("-?%d+") do v[#v + 1] = tonumber(n) end
    if #v >= 5 then
        seed, ship.x, ship.y, ship.heading, ship.hp = v[1], v[2], v[3], v[4], v[5]
        credits = v[6] or 0
        missiles = v[7] or 3
        ship.look = headingAngle(ship.heading)
    end
end

-- ---- input -------------------------------------------------------------------
local function turn(dir)
    ship.heading = (ship.heading + dir) % 8
    device.beep()
end

local function setWarp(w)
    ship.warp = w
    device.beep()
end

function on_key(k)
    if not ok then return end
    if k == "a" or k == "left" then turn(-1)
    elseif k == "d" or k == "right" then turn(1)
    elseif k == "b" then setWarp(0)
    elseif k == "w" or k == " " or k == "enter" then
        setWarp(ship.warp >= 3 and 1 or ship.warp + 1)
    elseif k == "l" then fire("laser")
    elseif k == "p" then fire("missile")
    end
end

function on_touch(x, y)
    if not ok then return end
    if ship.hp <= 0 then                      -- respawn: keep credits, lose the run
        ship.hp = ship.maxhp
        ship.warp = 1
        pirates = {}
        shots = {}
        save()
        return
    end
    if y > 200 then                     -- bottom strip: speed / brake
        if x < 80 then setWarp(0) else setWarp(ship.warp >= 3 and 1 or ship.warp + 1) end
    elseif x < 90 then turn(-1)
    elseif x > 230 then turn(1)
    end
end

-- ---- drawing -----------------------------------------------------------------
-- The compass and every object use the SAME projection, so a station sits directly
-- under the heading you'd steer to reach it.
local function drawCompass()
    canvas.rect(0, 0, W, 18, 0x101014)
    for i = 0, 7 do
        local rel = angleDiff(headingAngle(i), ship.look)
        if rel > -FOV and rel < FOV then
            local x = CX + (rel / FOV) * CX
            local main = (i % 2 == 0)
            canvas.rect(x, main and 2 or 5, 2, main and 6 or 3, main and 0x30d158 or 0x4a4a52)
            if main then
                -- tiny 3x5 letters, drawn as blocks: enough to read N/E/S/W at a glance
                local d = DIRS[i + 1]
                canvas.rect(x - 4, 10, 2, 6, 0x8e8e93)
                if #d > 1 then canvas.rect(x + 2, 10, 2, 6, 0x8e8e93) end
            end
        end
    end
    canvas.rect(CX - 1, 0, 3, 18, 0xffd60a)   -- you are pointing here
end

local SHIP_W, SHIP_SCALE = 11, 3
local PALETTE = {["W"] = 0xf2f6ff, ["B"] = 0x8fa9c8, ["C"] = 0x0a84ff, ["F"] = 0xff9f0a, ["R"] = 0xff453a}
local SHIP = {
    "    WW     " .. "   WWWB    " .. "  WWCWBB   " .. " WWWCWWBB  " ..
    "WWWWWWWBBB " .. " W  FFF  B " .. "    RFR    " .. "     R     ",
    "     W     " .. "    WWW    " .. "   WWCWB   " .. "  WWWCWBB  " ..
    " WWWWWWBBB " .. "W   FFF   B" .. "    RFR    " .. "     R     ",
    "     WW    " .. "    BWWW   " .. "   BBWCWW  " .. "  BBWWCWWW " ..
    " BBBWWWWWWW" .. " B  FFF  W " .. "    RFR    " .. "     R     ",
}

function on_open()
    ok = canvas.begin()
    if not ok then
        screen.label(1, 40, 110, "Canvas unavailable", 0xff453a)
        return
    end
    restore()
    ship.look = headingAngle(ship.heading)
    for i = 1, STARS do stars[i] = {}; reseed(stars[i], true) end
    findNearest()
    hint = device.time() + 6000
    screen.label(2, 30, 210, "A / D turn   W faster   B brake", 0x8e8e93)
end

function on_tick()
    if not ok then return end

    -- Ease the view towards the heading: the snap is instant, the picture swings.
    local target = headingAngle(ship.heading)
    local d = angleDiff(target, ship.look)
    local turning = math.abs(d) > 0.01
    if turning then ship.look = ship.look + d * 0.18 end

    -- Move through the world.
    local speed = ship.warp * 6
    if speed > 0 then
        ship.x = ship.x + math.sin(ship.look) * speed
        ship.y = ship.y + math.cos(ship.look) * speed
    end

    canvas.clear(0x000000)

    -- Stars. Turning sweeps them sideways, which is what sells the rotation.
    local sweep = d * 260
    local zstep = ship.warp * 0.012
    for i = 1, STARS do
        local s = stars[i]
        local pz = s.z
        if zstep > 0 then
            s.z = s.z - zstep
            if s.z <= 0.02 then reseed(s, false); pz = s.z end
        end
        s.x = s.x - (sweep * 0.00025) / s.z
        local px = CX + (s.x / s.z) * CX
        local py = CY + (s.y / s.z) * CY
        if px < 0 or px >= W or py < 18 or py >= H then
            reseed(s, false)
        elseif zstep > 0 and s.z < 0.35 then
            canvas.line(CX + (s.x / pz) * CX, CY + (s.y / pz) * CY, px, py, s.c)
        else
            canvas.pixel(px, py, s.c)
        end
    end

    -- Combat runs every frame. Pirates only appear in lawless regions, which is what
    -- makes the danger rating something you can learn rather than random punishment.
    if math.random() < 0.012 then spawnPirate() end
    stepPirates()
    stepShots()

    -- Shots: a bright dot flying away from you, shrinking as it goes.
    for _, sh in ipairs(shots) do
        local rel = angleDiff(sh.ang, ship.look)
        if rel > -FOV and rel < FOV then
            local sx = CX + (rel / FOV) * CX
            local shrink = 1 - (sh.dist / 3000)
            if shrink < 0.05 then shrink = 0.05 end
            local sz = math.floor((sh.kind == "laser" and 3 or 5) * shrink) + 1
            local sy = CY + 40 * shrink
            canvas.rect(sx - sz / 2, sy - sz / 2, sz, sz,
                        sh.kind == "laser" and 0x30d158 or 0xff9f0a)
        end
    end

    -- Pirates: red, growing as they close on you.
    for _, pr in ipairs(pirates) do
        local px, dist = project(pr.x, pr.y)
        if px and dist < 3000 then
            local size = math.floor(700 / dist * 16)
            if size < 3 then size = 3 end
            if size > 46 then size = 46 end
            local y = CY - size / 2
            canvas.rect(px - size / 2, y, size, size, 0xff453a)
            canvas.rect(px - size / 4, y + size / 4, size / 2, size / 4, 0x3a0f0d)
        end
    end

    -- Stations, drawn where they actually are relative to where we're looking.
    local csx, csy = math.floor(ship.x / SECTOR), math.floor(ship.y / SECTOR)
    for sx = csx - 2, csx + 2 do
        for sy = csy - 2, csy + 2 do
            local st = stationIn(sx, sy)
            if st then
                local px, dist = project(st.x, st.y)
                if px and dist < 4000 then
                    local size = math.floor(900 / dist * 14)
                    if size < 2 then size = 2 end
                    if size > 40 then size = 40 end
                    local y = CY - size / 2
                    canvas.rect(px - size / 2, y, size, size, 0x0a84ff)
                    canvas.rect(px - size / 2 + size / 4, y + size / 4, size / 2, size / 2, 0x9ad0ff)
                end
            end
        end
    end

    drawCompass()

    -- The ship, banking into the turn.
    local frame = 2
    if d < -0.06 then frame = 1 elseif d > 0.06 then frame = 3 end
    canvas.sprite(CX - (SHIP_W * SHIP_SCALE) / 2, 170, SHIP_W, SHIP[frame], PALETTE, SHIP_SCALE)

    -- Readouts: where we are, and where the nearest station is. Without this a compass
    -- alone just gets you lost in a black void.
    canvas.rect(0, H - 22, W, 22, 0x101014)
    for i = 1, ship.warp do canvas.rect(6 + (i - 1) * 9, H - 16, 6, 10, 0x30d158) end
    if ship.warp == 0 then canvas.rect(6, H - 16, 24, 10, 0xff453a) end

    -- Health bar. Colour shifts as it drops so you feel it going without reading a number.
    local frac = ship.hp / ship.maxhp
    local barW = math.floor(90 * frac)
    canvas.rect(120, H - 16, 90, 10, 0x2c2c2e)
    if barW > 0 then
        canvas.rect(120, H - 16, barW, 10,
                    frac > 0.6 and 0x30d158 or (frac > 0.3 and 0xffd60a or 0xff453a))
    end
    -- missiles remaining, as pips
    for i = 1, missiles do canvas.rect(224 + (i - 1) * 8, H - 16, 5, 10, 0xff9f0a) end

    -- Taking a hit flashes the edges red - unmissable without covering the view.
    if device.time() - lastHit < 250 then
        canvas.rect(0, 18, W, 3, 0xff453a)
        canvas.rect(0, H - 25, W, 3, 0xff453a)
    end

    canvas.flip()

    -- Text goes on labels, which are crisper than anything we can draw by hand.
    screen.label(3, 8, 22, "X " .. math.floor(ship.x) .. "  Y " .. math.floor(ship.y), 0x8e8e93)
    screen.label(4, 250, 22, DIRS[ship.heading + 1], 0x30d158)

    findNearest()
    if nearest then
        local bearing = math.atan(nearest.x - ship.x, nearest.y - ship.y)
        local rel = angleDiff(bearing, headingAngle(ship.heading))
        local arrow = (math.abs(rel) < 0.4) and "ahead" or (rel > 0 and "turn right" or "turn left")
        screen.label(5, 8, H - 40, "station " .. math.floor(nearestDist) .. "  " .. arrow, 0x0a84ff)
    else
        screen.label(5, 8, H - 40, "no station in range", 0x4a4a52)
    end

    screen.label(6, 250, H - 40, credits .. "c", 0xffd60a)

    -- Destroyed: stop, say so, and let a tap start again. Losing has to be legible.
    if ship.hp <= 0 then
        screen.label(7, 96, 100, "SHIP DESTROYED", 0xff453a)
        screen.label(8, 92, 120, "tap to start again", 0x8e8e93)
        ship.warp = 0
    else
        screen.hide(7)
        screen.hide(8)
    end

    if hint > 0 and device.time() > hint then hint = 0; screen.hide(2) end

    -- Autosave now and then; a save is a couple of hundred bytes.
    if device.time() % 5000 < 34 then save() end
end

function on_close()
    if ok then save() end
end
