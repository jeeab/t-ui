-- Starfield: Deep Space ---------------------------------------------------------
-- Fly a ship through an endless, generated galaxy.
--
--   A / D  turn 45 degrees      W faster / S slower (S all the way = stop)
--   L  laser (3 hits to kill)   P  phoenix missile (one shot, one kill)
--   M  map of nearby space      tap sides to turn
--
-- Stop beside a STATION to repair, and tap to buy missiles.
-- Stop beside a DERELICT to salvage it.
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
-- heading is a free angle in radians (0 = north). turn is the current rate of swing:
-- each nudge adds to it and it bleeds off, so you can ease round or spin hard depending
-- on how much you press. Nothing is snapped - point anywhere and fly at it.
local ship = {x = 0, y = 0, heading = 0, look = 0, turn = 0, warp = 1, hp = 100, maxhp = 100}
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
local MAX_PIRATES = 3
local incoming = {}          -- pirate shots on their way to you, so you can SEE them coming
local docked, dockedOn = false, nil
local hitFrom = 0            -- bearing of the last hit, so the flash shows WHERE from
local showMap = false
local salvaged = {}          -- "sx,sy" of hulks already stripped; bounded, saved with the game

local function salvageKey(sx, sy) return sx .. "," .. sy end

local function isSalvaged(sx, sy)
    for i = 1, #salvaged do
        if salvaged[i] == salvageKey(sx, sy) then return true end
    end
    return false
end

local function markSalvaged(sx, sy)
    salvaged[#salvaged + 1] = salvageKey(sx, sy)
    -- Keep the list bounded so the save stays small; the oldest wrecks eventually
    -- drift back, which is fine - they're a long way behind you by then.
    while #salvaged > 40 do table.remove(salvaged, 1) end
end

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

-- Derelict hulks: rarer than stations, and each one can only be stripped once (see the
-- salvaged list in the save). Free credits and sometimes a missile, for the detour.
local function derelictIn(sx, sy)
    local h = hash(sx, sy, 3)
    if h % 11 ~= 0 then return nil end
    return {x = sx * SECTOR + (h >> 5) % SECTOR, y = sy * SECTOR + (h >> 15) % SECTOR, sx = sx, sy = sy}
end

-- How lawless is this region? Drives pirate density, and is shown on screen so you can
-- decide to avoid a rough neighbourhood instead of blundering into one.
local function dangerAt(sx, sy)
    return hash(sx, sy, 7) % 100
end

-- Nearest station in the sectors around us. Cheap: 25 sectors, only when it changes.
local nearest, nearestDist = nil, 0
local wrecksNearby = {}
local function findNearest()
    local csx = math.floor(ship.x / SECTOR)
    local csy = math.floor(ship.y / SECTOR)
    nearest, nearestDist = nil, 1e18
    wrecksNearby = {}
    for sx = csx - 2, csx + 2 do
        for sy = csy - 2, csy + 2 do
            local st = stationIn(sx, sy)
            if st then
                local dx, dy = st.x - ship.x, st.y - ship.y
                local d = math.sqrt(dx * dx + dy * dy)
                if d < nearestDist then nearest, nearestDist = st, d end
            end
            local w = derelictIn(sx, sy)
            if w then
                w.done = isSalvaged(sx, sy)
                wrecksNearby[#wrecksNearby + 1] = w
            end
        end
    end
end

-- ---- helpers -----------------------------------------------------------------
local function headingAngle(h) return h * math.pi / 4 end

-- Nearest compass name for a free heading, for the readout.
local function headingName(a)
    local i = math.floor(((a % (2 * math.pi)) / (math.pi / 4)) + 0.5) % 8
    return DIRS[i + 1]
end

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
    if dangerAt(csx, csy) < 62 then return end          -- most space is quiet
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
            -- Generous on purpose. The target is a few pixels wide at range and you are
            -- aiming with a thumb on a 320-pixel screen; a tight box just feels broken.
            if math.abs(pd - sh.dist) < 420 then
                local rel = angleDiff(math.atan(dx, dy), sh.ang)
                if math.abs(rel) < 0.42 then
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

-- Enemy bolts close on you each frame. They only hurt when they arrive.
local function stepIncoming()
    for i = #incoming, 1, -1 do
        local b = incoming[i]
        b.dist = b.dist - 55
        -- keep the bolt aimed at where you are now, so it tracks toward the ship
        local dx, dy = b.x - ship.x, b.y - ship.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 1 then
            b.x = ship.x + (dx / d) * b.dist
            b.y = ship.y + (dy / d) * b.dist
        end
        if b.dist <= 60 then
            -- remember the bearing it arrived from, relative to where we're facing, so
            -- the flash can tell you which way to turn instead of just "you're hit"
            hitFrom = angleDiff(math.atan(b.x - ship.x, b.y - ship.y), ship.heading)
            table.remove(incoming, i)
            ship.hp = ship.hp - 6
            lastHit = device.time()
            if ship.hp < 0 then ship.hp = 0 end
            device.beep(true)
        end
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
            -- Shoot something you can actually see coming, rather than damaging you out
            -- of nowhere: the bolt is launched here and travels toward you over a second
            -- or so, growing as it closes. Getting hit should never be a surprise.
            if d < 1600 and now > (p.lastShot or 0) + p.cool then
                p.lastShot = now
                incoming[#incoming + 1] = {x = p.x, y = p.y, dist = d}
                device.beep()
            end
        end
    end
end

-- Stop next to a station and it patches you up. Braking is what docks you, which gives
-- the throttle a purpose beyond going fast, and gives credits somewhere to go.
local function stepDocking()
    docked, dockedOn = false, nil
    if ship.warp > 0 then return end          -- you dock by stopping

    -- A derelict close by? Strip it once, then it's an empty hull forever after.
    local csx, csy = math.floor(ship.x / SECTOR), math.floor(ship.y / SECTOR)
    for sx = csx - 1, csx + 1 do
        for sy = csy - 1, csy + 1 do
            local w = derelictIn(sx, sy)
            if w then
                local dx, dy = w.x - ship.x, w.y - ship.y
                if math.sqrt(dx * dx + dy * dy) < 300 then
                    docked, dockedOn = true, "wreck"
                    if not isSalvaged(sx, sy) then
                        markSalvaged(sx, sy)
                        local loot = 25 + (hash(sx, sy, 5) % 40)
                        credits = credits + loot
                        if hash(sx, sy, 9) % 3 == 0 and missiles < 6 then missiles = missiles + 1 end
                        device.beep(true)
                    end
                    return
                end
            end
        end
    end

    -- Otherwise a station: repair for free, missiles for money (tap to buy).
    if nearest and nearestDist <= 260 then
        docked, dockedOn = true, "station"
        if ship.hp < ship.maxhp then
            ship.hp = ship.hp + 1
            if ship.hp > ship.maxhp then ship.hp = ship.maxhp end
            if ship.hp % 20 == 0 then device.beep() end
        end
    end
end

-- The station shop: one tap, one missile, while you're stopped alongside.
local function buyMissile()
    if not docked or dockedOn ~= "station" then return false end
    if credits < 20 or missiles >= 6 then return false end
    credits = credits - 20
    missiles = missiles + 1
    device.beep(true)
    return true
end

-- ---- save --------------------------------------------------------------------
-- Tiny, because the galaxy is generated rather than stored: just where we are.
local function save()
    -- ship state, then the wrecks already stripped. Still tiny: the galaxy is generated.
    store.write("save.txt", table.concat({seed, math.floor(ship.x), math.floor(ship.y),
                                          math.floor(ship.heading * 180 / math.pi), ship.hp, credits, missiles}, ",")
                            .. ";" .. table.concat(salvaged, " "))
end

local function restore()
    local raw = store.read("save.txt")
    if not raw then return end
    local s, wrecks = raw:match("^([^;]*);?(.*)$")
    local v = {}
    for n in s:gmatch("-?%d+") do v[#v + 1] = tonumber(n) end
    salvaged = {}
    for w in (wrecks or ""):gmatch("[-%d,]+") do
        if w:find(",") then salvaged[#salvaged + 1] = w end
    end
    if #v >= 5 then
        seed, ship.x, ship.y, ship.hp = v[1], v[2], v[3], v[5]
        ship.heading = (v[4] or 0) * math.pi / 180
        credits = v[6] or 0
        missiles = v[7] or 3
        ship.look = ship.heading
    end
end

-- ---- input -------------------------------------------------------------------
-- The T-Deck keyboard sends ONE event per press - holding a key does not repeat. So a
-- tap can't be a small nudge or you'd be hammering the key to get anywhere. Each tap
-- adds a decent swing and the rate bleeds off slowly, which means two or three taps
-- give a proper sustained turn that settles by itself.
-- Tuned so ONE tap is a deliberate ~45 degree course change that settles in about a
-- second. Tap again mid-turn to keep swinging. (A slower bleed was tried and a single
-- tap spun you most of the way round before it stopped - unflyable.)
local function turn(dir)
    ship.turn = ship.turn + dir * 0.08
    if ship.turn > 0.20 then ship.turn = 0.20 end
    if ship.turn < -0.20 then ship.turn = -0.20 end
end

-- W and S step the throttle. Zero is a full stop, which is also how you dock.
local function setWarp(w)
    if w < 0 then w = 0 end
    if w > 3 then w = 3 end
    if w == ship.warp then return end
    ship.warp = w
    device.beep()
end

function on_key(k)
    if not ok then return end
    if k == "a" or k == "left" then turn(-1)
    elseif k == "d" or k == "right" then turn(1)
    elseif k == "b" then setWarp(0)
    elseif k == "w" or k == "up" then setWarp(ship.warp + 1)
    elseif k == "s" or k == "down" then setWarp(ship.warp - 1)
    elseif k == " " or k == "enter" then setWarp(ship.warp + 1)
    elseif k == "l" then fire("laser")
    elseif k == "p" then fire("missile")
    elseif k == "m" then
        showMap = not showMap
        device.beep()
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
    if showMap then showMap = false; return end     -- any tap closes the map
    if docked and dockedOn == "station" and y < 200 then
        if buyMissile() then return end
    end
    if y > 200 then                     -- bottom strip: slower on the left, faster on the right
        if x < 160 then setWarp(ship.warp - 1) else setWarp(ship.warp + 1) end
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
    -- Contacts on the strip, so it doubles as a radar. Anything behind you can't be
    -- placed on a forward-facing strip, so it gets pinned to the edge you'd turn toward.
    for _, pr in ipairs(pirates) do
        local rel = angleDiff(math.atan(pr.x - ship.x, pr.y - ship.y), ship.look)
        local x
        if rel > -FOV and rel < FOV then
            x = CX + (rel / FOV) * CX
        else
            x = (rel > 0) and (W - 4) or 2      -- off to the right / left, behind you
        end
        canvas.rect(x - 2, 1, 5, 5, 0xff453a)
    end
    for _, w in ipairs(wrecksNearby) do
        local rel = angleDiff(math.atan(w.x - ship.x, w.y - ship.y), ship.look)
        if rel > -FOV and rel < FOV then
            canvas.rect(CX + (rel / FOV) * CX - 1, 2, 3, 3, 0xbf5af2)
        end
    end

    canvas.rect(CX - 1, 0, 3, 18, 0xffd60a)   -- you are pointing here
end

-- ---- map ---------------------------------------------------------------------
-- A chart of the sectors around you. Navigating purely on a bearing is atmospheric but
-- hard work; this makes a big galaxy feel navigable. The sim pauses while it's open.
local function drawMap()
    canvas.clear(0x05050a)
    local SPAN = 4                       -- sectors either side
    local cell = 30
    local ox, oy = CX, CY
    local csx, csy = math.floor(ship.x / SECTOR), math.floor(ship.y / SECTOR)

    -- grid
    for i = -SPAN, SPAN do
        canvas.line(ox + i * cell, 20, ox + i * cell, H - 20, 0x16161e)
        canvas.line(20, oy + i * cell, W - 20, oy + i * cell, 0x16161e)
    end

    for sx = csx - SPAN, csx + SPAN do
        for sy = csy - SPAN, csy + SPAN do
            -- screen position: north is up, so sector y grows upward
            local px = ox + (sx - csx) * cell
            local py = oy - (sy - csy) * cell
            if px > 12 and px < W - 12 and py > 22 and py < H - 22 then
                if dangerAt(sx, sy) >= 62 then
                    canvas.rect(px - cell / 2, py - cell / 2, cell - 1, cell - 1, 0x2a0f10)
                end
                local st = stationIn(sx, sy)
                if st then canvas.rect(px - 4, py - 4, 8, 8, 0x0a84ff) end
                local wk = derelictIn(sx, sy)
                if wk then
                    canvas.rect(px - 3, py - 3, 6, 6,
                                isSalvaged(sx, sy) and 0x3a3a42 or 0xbf5af2)
                end
            end
        end
    end

    -- you, with a stub showing which way you're pointing
    canvas.circle(ox, oy, 4, 0x30d158, true)
    canvas.line(ox, oy, ox + math.sin(ship.heading) * 14, oy - math.cos(ship.heading) * 14, 0x30d158)
    canvas.flip()
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
    ship.look = ship.heading
    for i = 1, STARS do stars[i] = {}; reseed(stars[i], true) end
    findNearest()
    hint = device.time() + 6000
    screen.label(2, 14, 210, "A/D turn  W/S speed  L laser  P missile", 0x8e8e93)
end

function on_tick()
    if not ok then return end

    -- Map is a full screen chart; the world pauses behind it. (This call was missing,
    -- which is why M appeared to do nothing at all.)
    if showMap then
        drawMap()
        for i = 2, 9 do screen.hide(i) end   -- text would float over the chart
        return
    end

    -- Steering: the turn rate swings the heading and then bleeds away, so letting go
    -- settles you on a course instead of stopping dead.
    ship.heading = ship.heading + ship.turn
    ship.turn = ship.turn * 0.90
    if math.abs(ship.turn) < 0.0015 then ship.turn = 0 end

    -- The view follows the heading closely; the small lag is what makes the starfield
    -- sweep as you come round.
    local d = angleDiff(ship.heading, ship.look)
    ship.look = ship.look + d * 0.35

    -- Fly along the heading, not the eased view angle: the picture lags a little for
    -- looks, but the ship goes exactly where you pointed it.
    local speed = ship.warp * 6
    if speed > 0 then
        ship.x = ship.x + math.sin(ship.heading) * speed
        ship.y = ship.y + math.cos(ship.heading) * speed
    end

    canvas.clear(0x000000)

    -- Stars. Turning sweeps them sideways, which is what sells the rotation.
    local sweep = ship.turn * 900
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
    if math.random() < 0.004 then spawnPirate() end
    stepPirates()
    stepShots()
    stepIncoming()
    stepDocking()

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

    -- Incoming fire: orange bolts that swell as they reach you. Visible warning beats
    -- losing health for no apparent reason.
    for _, b in ipairs(incoming) do
        local px, dist = project(b.x, b.y)
        if px then
            local sz = math.floor(600 / math.max(dist, 60) * 5)
            if sz < 3 then sz = 3 end
            if sz > 26 then sz = 26 end
            canvas.rect(px - sz / 2, CY - sz / 2, sz, sz, 0xff9f0a)
            canvas.rect(px - sz / 4, CY - sz / 4, sz / 2, sz / 2, 0xffe9a8)
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
    if ship.turn < -0.012 then frame = 1 elseif ship.turn > 0.012 then frame = 3 end
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

    -- A hit flashes the edge it came FROM, so the damage tells you where to look. A
    -- flash on all four sides says "you're hurt"; one on the left says "turn left".
    if device.time() - lastHit < 350 then
        local a = hitFrom
        if a > -0.79 and a < 0.79 then
            canvas.rect(0, 18, W, 4, 0xff453a)                  -- dead ahead
        elseif a >= 0.79 and a < 2.36 then
            canvas.rect(W - 4, 18, 4, H - 44, 0xff453a)         -- from the right
        elseif a <= -0.79 and a > -2.36 then
            canvas.rect(0, 18, 4, H - 44, 0xff453a)             -- from the left
        else
            canvas.rect(0, H - 26, W, 4, 0xff453a)              -- from behind
        end
    end

    canvas.flip()

    -- Text goes on labels, which are crisper than anything we can draw by hand.
    screen.label(3, 8, 22, "X " .. math.floor(ship.x) .. "  Y " .. math.floor(ship.y), 0x8e8e93)
    screen.label(4, 250, 22, headingName(ship.heading), 0x30d158)

    findNearest()
    if nearest then
        local bearing = math.atan(nearest.x - ship.x, nearest.y - ship.y)
        local rel = angleDiff(bearing, ship.heading)
        local arrow = (math.abs(rel) < 0.4) and "ahead" or (rel > 0 and "turn right" or "turn left")
        screen.label(5, 8, H - 40, "station " .. math.floor(nearestDist) .. "  " .. arrow, 0x0a84ff)
    else
        screen.label(5, 8, H - 40, "no station in range", 0x4a4a52)
    end

    screen.label(6, 250, H - 40, credits .. "c", 0xffd60a)

    if docked then
        screen.label(9, 96, 60, ship.hp < ship.maxhp and "DOCKED - repairing" or
                     (missiles < 3 and credits >= 20 and "DOCKED - rearming" or "DOCKED"), 0x30d158)
    else
        screen.hide(9)
    end

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
