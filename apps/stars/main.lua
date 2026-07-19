-- Starfield: Deep Space ---------------------------------------------------------
-- Fly a ship through an endless, generated galaxy.
--
--   A / D  turn one compass point   W faster / S slower (S all the way = stop)
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
-- A 16-point compass. You steer one point at a time, so every heading has a name and
-- every tap is a definite, repeatable course change - not a nudge you have to eyeball.
local DIRS = {"N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
              "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"}
local STEP = math.pi / 8        -- 22.5 degrees: one point of the compass

-- ---- world -------------------------------------------------------------------
local seed = 20260719
-- heading is always one of the 16 compass points (radians, 0 = north) and changes the
-- instant you tap - there is no drifting or coasting round. look is the VIEW angle,
-- which eases over to meet the heading; that lag is the swing you actually see. turn is
-- how fast the view is swinging, and only drives the picture (star sweep, ship bank).
-- Shields sit in front of the hull and come back on their own, so a scrape you fly away
-- from costs you nothing but time. The HULL is the expensive part: it only comes back at
-- a station, and only if you have Parts. That's what makes a bad fight actually matter.
local ship = {x = 0, y = 0, heading = 0, look = 0, turn = 0, warp = 1,
              hp = 100, maxhp = 100, sh = 50, maxsh = 50}
local SHIELD_REGEN_MS = 900      -- one point per this long, once you've been left alone
local SHIELD_CALM_MS = 3000      -- how long since the last hit before it starts coming back
-- ONE number for "close enough to deal with": it decides both when you can dock and when
-- a station's name is up on screen. Keeping them the same means the name appearing is
-- exactly the signal that you're in range, and the two can never drift apart.
local DOCK_RANGE = 260
local WRECK_RANGE = 240
local REPAIR_COST = 10           -- Parts for a full hull repair
local SALVAGE_PARTS = 5          -- Parts per derelict
local MISSILE_COST = 10          -- credits per missile - exactly one pirate's bounty
local PIRATE_BOUNTY = 10         -- credits per kill
local PARTS_PACK = 5             -- Parts you get for buying a pack at a station
local PARTS_COST = 40            -- deliberately poor value: a way out, not a shortcut
local PIRATE_PARTS = 2           -- salvaged off a kill, when a kill gives anything
local PIRATE_PARTS_CHANCE = 0.34 -- how often a wreck is worth stripping
local lastRegen = 0
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
local parts = 0              -- salvaged from derelicts; the only thing that repairs a hull
local lastFire, lastHit = 0, 0
local incoming = {}          -- pirate shots on their way to you, so you can SEE them coming
local blasts = {}            -- pirate death explosions: world position + when it started
local docked, dockedOn = false, nil
local dockedWreck = nil      -- the derelict we're alongside, so Salvage knows what to strip
local hitFrom = 0            -- bearing of the last hit, so the flash shows WHERE from
local showMap = false
-- One popup line, shared by station names and pickups. Sharing it means a "+2 PARTS"
-- never fights a station name for the same strip of screen, and the newest thing to
-- happen is always the thing you're being told about.
local popText, popUntil = nil, 0
local salvaged = {}          -- "sx,sy" of hulks already stripped; bounded, saved with the game

local function popup(t, ms)
    popText, popUntil = t, device.time() + (ms or 2600)
end

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

-- Station names. Built from the sector hash, so a station has the SAME name every time
-- you find it, on any device, without a single byte being stored. Naming the places you
-- visit is what turns a coordinate into somewhere you remember going.
local NAME_A = {"Vor", "Zan", "Kal", "Neb", "Ish", "Tar", "Ory", "Xen",
                "Cru", "Mal", "Sil", "Dra", "Ael", "Qir", "Hro", "Umb"}
local NAME_B = {"an", "ex", "is", "or", "ux", "ai", "en", "yr"}
local NAME_C = {"Station", "Outpost", "Anchorage", "Reach", "Terminal",
                "Halo", "Spire", "Deepdock"}

local function stationName(sx, sy)
    local h = hash(sx, sy, 21)
    return NAME_A[(h % 16) + 1] .. NAME_B[((h >> 5) % 8) + 1]
           .. " " .. NAME_C[((h >> 9) % 8) + 1]
end

-- What's in a sector? Stations are deliberately uncommon - about one sector in twelve.
-- They were one in six and that made them ordinary; you want to be pleased to find one.
local function stationIn(sx, sy)
    local h = hash(sx, sy, 1)
    if h % 12 ~= 0 then return nil end
    return {
        x = sx * SECTOR + (h >> 4) % SECTOR,
        y = sy * SECTOR + (h >> 14) % SECTOR,
        sx = sx, sy = sy,
        kind = (h >> 24) % 3,             -- which of the three station designs
        name = stationName(sx, sy),
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
local function headingAngle(h) return h * STEP end

-- Snap an angle to the nearest of the 16 points. Everything that sets a heading goes
-- through here, so the ship can never end up pointing between two of them.
local function snapHeading(a)
    return (math.floor(a / STEP + 0.5) % 16) * STEP
end

local function headingName(a)
    return DIRS[(math.floor(a / STEP + 0.5) % 16) + 1]
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
-- How many raiders a region will field at once. Quiet space gets none; the worst places
-- get five. Tying it to the danger rating means "this sector is nasty" is something you
-- can actually feel arriving rather than just read off the map.
local function maxPiratesHere()
    local d = dangerAt(math.floor(ship.x / SECTOR), math.floor(ship.y / SECTOR))
    if d < 62 then return 0 end
    local n = 3 + math.floor((d - 62) / 13)
    if n > 5 then n = 5 end
    return n
end

local function spawnPirate()
    local csx, csy = math.floor(ship.x / SECTOR), math.floor(ship.y / SECTOR)
    if dangerAt(csx, csy) < 62 then return end          -- most space is quiet
    if #pirates >= maxPiratesHere() then return end
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
                        -- Leave a blast behind at the pirate's own position, so the kill
                        -- happens out there in the world and stays put as you fly past it.
                        blasts[#blasts + 1] = {x = p.x, y = p.y, born = device.time()}
                        table.remove(pirates, pi)
                        credits = credits + PIRATE_BOUNTY
                        -- Some wrecks are worth stripping. Deliberately less than a
                        -- derelict pays, so fighting tops your Parts up but hunting
                        -- derelicts is still the way to actually fund a repair.
                        if math.random() < PIRATE_PARTS_CHANCE then
                            parts = parts + PIRATE_PARTS
                            popup("+" .. PIRATE_PARTS .. " PARTS", 1400)
                        end
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
            -- Shields take it first and soak the whole hit if they can. Only what's left
            -- over reaches the hull, which is the damage you'll have to pay Parts to undo.
            local dmg = 6
            if ship.sh > 0 then
                local absorbed = math.min(ship.sh, dmg)
                ship.sh = ship.sh - absorbed
                dmg = dmg - absorbed
            end
            ship.hp = ship.hp - dmg
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

-- Braking is what docks you, which gives the throttle a purpose beyond going fast.
-- Nothing happens automatically any more: docking OFFERS you buttons and you choose.
-- Salvage used to fire off silently the moment you drifted close enough, which meant the
-- best moment in the game happened without you doing anything.
local function stepDocking()
    docked, dockedOn, dockedWreck = false, nil, nil
    if ship.warp > 0 then return end          -- you dock by stopping

    -- A derelict close by? Offer to strip it. Each hull can only be stripped once.
    local csx, csy = math.floor(ship.x / SECTOR), math.floor(ship.y / SECTOR)
    for sx = csx - 1, csx + 1 do
        for sy = csy - 1, csy + 1 do
            local w = derelictIn(sx, sy)
            if w then
                local dx, dy = w.x - ship.x, w.y - ship.y
                if math.sqrt(dx * dx + dy * dy) < WRECK_RANGE then
                    docked, dockedOn, dockedWreck = true, "wreck", w
                    return
                end
            end
        end
    end

    -- Otherwise a station. This was once much wider, to forgive the half-a-point of aim
    -- error that 22.5 degree steering allows. Tightened back down because docking from
    -- far enough away that the station is still a speck doesn't read as docking at all -
    -- you correct course on the way in anyway, so the slack wasn't buying much.
    if nearest and nearestDist <= DOCK_RANGE then
        docked, dockedOn = true, "station"
    end
end

-- Repairing the hull is the one thing Parts are for, and it's instant rather than the
-- old slow drip - you came all this way, you shouldn't then sit and wait.
local function repairHull()
    if not docked or dockedOn ~= "station" then return false end
    if ship.hp >= ship.maxhp or parts < REPAIR_COST then return false end
    parts = parts - REPAIR_COST
    ship.hp = ship.maxhp
    device.beep(true)
    return true
end

-- The station shop: one tap, one missile, while you're stopped alongside.
local function buyMissile()
    if not docked or dockedOn ~= "station" then return false end
    if credits < MISSILE_COST or missiles >= 6 then return false end
    credits = credits - MISSILE_COST
    missiles = missiles + 1
    device.beep(true)
    return true
end

-- Buying Parts is the way out of a dead end: hull wrecked, no Parts, no derelict in
-- reach. The rate is bad on purpose (8 credits a Part against free from a hulk) so it
-- rescues you without ever being the sensible way to stock up.
local function buyParts()
    if not docked or dockedOn ~= "station" then return false end
    if credits < PARTS_COST then return false end
    credits = credits - PARTS_COST
    parts = parts + PARTS_PACK
    popup("+" .. PARTS_PACK .. " PARTS", 1400)
    device.beep(true)
    return true
end

-- Salvage: now a button you press, and the payout is Parts rather than credits, because
-- Parts are what keep your hull alive. Wrecks are the reason to leave the shipping lanes.
local function salvageWreck()
    if not docked or dockedOn ~= "wreck" or not dockedWreck then return false end
    local w = dockedWreck
    if isSalvaged(w.sx, w.sy) then return false end
    markSalvaged(w.sx, w.sy)
    parts = parts + SALVAGE_PARTS
    credits = credits + 25 + (hash(w.sx, w.sy, 5) % 40)
    if hash(w.sx, w.sy, 9) % 3 == 0 and missiles < 6 then missiles = missiles + 1 end
    w.done = true
    device.beep(true)
    return true
end

-- What you can actually do while docked. ONE list, read by both the drawing code and the
-- touch handler, so a button can never appear somewhere it isn't tappable (or worse, be
-- tappable where nothing is drawn). Sits in the middle band, clear of the turn thirds at
-- the screen edges and the throttle strip along the bottom.
local BTN_X, BTN_W, BTN_H = 92, 136, 26
local BTN_SLOT = {20, 21, 22}          -- label ids, well clear of the HUD's own slots
local function dockButtons()
    local b = {}
    if not docked then return b end
    if dockedOn == "station" then
        if ship.hp < ship.maxhp then
            b[#b + 1] = {text = "REPAIR " .. REPAIR_COST .. "p", act = repairHull,
                         on = parts >= REPAIR_COST}
        end
        if missiles < 6 then
            b[#b + 1] = {text = "REARM " .. MISSILE_COST .. "c", act = buyMissile,
                         on = credits >= MISSILE_COST}
        end
        b[#b + 1] = {text = "BUY " .. PARTS_PACK .. "p " .. PARTS_COST .. "c",
                     act = buyParts, on = credits >= PARTS_COST}
    elseif dockedOn == "wreck" and dockedWreck and not isSalvaged(dockedWreck.sx, dockedWreck.sy) then
        b[#b + 1] = {text = "SALVAGE +" .. SALVAGE_PARTS .. "p", act = salvageWreck, on = true}
    end
    -- Stacked below the popup line (y 44) and above the DOCKED caption (y 152) and the
    -- ship itself (y 170). Three is the most ever offered, at a station with a damaged
    -- hull and room for missiles.
    for i, btn in ipairs(b) do
        btn.x, btn.y, btn.w, btn.h = BTN_X, 62 + (i - 1) * (BTN_H + 4), BTN_W, BTN_H
    end
    return b
end

-- ---- save --------------------------------------------------------------------
-- Tiny, because the galaxy is generated rather than stored: just where we are.
local function save()
    -- ship state, then the wrecks already stripped. Still tiny: the galaxy is generated.
    store.write("save.txt", table.concat({seed, math.floor(ship.x), math.floor(ship.y),
                                          math.floor(ship.heading * 180 / math.pi), ship.hp, credits,
                                          missiles, parts, math.floor(ship.sh)}, ",")
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
        -- Snapped on the way back in. The save rounds the heading to whole degrees, and
        -- 22.5 doesn't survive that - so re-snapping is what keeps a reloaded ship
        -- exactly on a compass point. It also quietly fixes saves from the older
        -- free-flight version, which could sit at any angle at all.
        ship.heading = snapHeading((v[4] or 0) * math.pi / 180)
        credits = v[6] or 0
        missiles = v[7] or 3
        -- Saves from before Parts and shields existed simply don't have these fields, so
        -- they fall back to sensible starting values rather than loading as zero.
        parts = v[8] or 0
        ship.sh = v[9] or ship.maxsh
        if ship.sh > ship.maxsh then ship.sh = ship.maxsh end
        ship.look = ship.heading
    end
end

-- ---- input -------------------------------------------------------------------
-- The T-Deck keyboard sends ONE event per press - holding a key does not repeat. That
-- rules out hold-to-turn, so a tap has to BE a whole course change on its own. One tap
-- is exactly one compass point: it lands immediately, it's the same every time, and
-- four taps is a right angle you can count out without watching the compass.
-- (An earlier version let the turn rate coast and bleed off. It looked nice and flew
-- badly - you could never stop on the heading you wanted.)
local function turn(dir)
    ship.heading = snapHeading(ship.heading + dir * STEP)
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
        ship.sh = ship.maxsh
        ship.warp = 1
        pirates = {}
        shots = {}
        save()
        return
    end
    if showMap then showMap = false; return end     -- any tap closes the map

    -- Dock buttons win over steering: they're only on screen while you're stopped, and a
    -- tap that lands on one should never also swing the ship round.
    for _, b in ipairs(dockButtons()) do
        if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            if b.on then b.act() else device.beep() end
            return
        end
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
    -- All 16 points get a tick, so every heading you can steer to is visible as a place
    -- to aim at. Only the 8 principal ones get a tall tick and letters, or the strip
    -- turns into a picket fence.
    for i = 0, 15 do
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


-- Pirate raider, 9x7. Drawn at a scale that grows as it closes, so a distant contact is
-- a speck and a close one fills a chunk of the screen.
local PIRATE_W = 9
local PIRATE_ART =
    "   RRR   " ..
    "  RRRRR  " ..
    " RRWWWRR " ..
    "RRRWCWRRR" ..
    " RRWWWRR " ..
    "  R R R  " ..
    " F     F "
local PIRATE_PAL = {["R"] = 0xff453a, ["W"] = 0x8a1f18, ["C"] = 0xffe9a8, ["F"] = 0xff9f0a}

-- Stations, 11x9. Built out of steel rather than glowing blue: plate (S), shadowed plate
-- (D) and structural dark (K), with lit windows (W) and a beacon (C) so they still read
-- as inhabited at a distance. Three designs, picked by the sector hash, so the same
-- station always looks the same but the galaxy isn't full of identical rings.
local STATION_W = 11
local STATION_ART = {
    -- ring station: a wheel with a lit hub
    "   SSSSS   " ..
    "  SD   DS  " ..
    " SD  W  DS " ..
    "SD  DKD  DS" ..
    "S  WKCKW  S" ..
    "SD  DKD  DS" ..
    " SD  W  DS " ..
    "  SD   DS  " ..
    "   SSSSS   ",
    -- spindle station: a long axis with docking arms
    "    SDS    " ..
    "   SDKDS   " ..
    " S SDWDS S " ..
    "SSSSDKDSSSS" ..
    "SDWDKCKDWDS" ..
    "SSSSDKDSSSS" ..
    " S SDWDS S " ..
    "   SDKDS   " ..
    "    SDS    ",
    -- platform station: a slab yard, lights along both decks
    "  SSSSSSS  " ..
    " SDDDDDDDS " ..
    "SDWDSDSDWDS" ..
    "SDDDDKDDDDS" ..
    "SSSSDCDSSSS" ..
    "SDDDDKDDDDS" ..
    "SDWDSDSDWDS" ..
    " SDDDDDDDS " ..
    "  SSSSSSS  ",
}
local STATION_PAL = {["S"] = 0x9aa3ad, ["D"] = 0x6b737c, ["K"] = 0x3f454b,
                     ["W"] = 0xffe9a8, ["C"] = 0x0a84ff}

-- Derelict hulk, 9x7: a broken station, dark and lopsided.
local WRECK_W = 9
local WRECK_ART =
    "  GG G   " ..
    " GG   GG " ..
    "GG  G  G " ..
    "G  GGG  G" ..
    " G  G  GG" ..
    " GG   GG " ..
    "   G GG  "
local WRECK_PAL = {["G"] = 0x6b5f7a}
local WRECK_DONE_PAL = {["G"] = 0x3a3a42}

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
        for i = 2, 12 do screen.hide(i) end  -- text would float over the chart
        for _, s in ipairs(BTN_SLOT) do screen.hide(s) end
        return
    end

    -- Steering is instant: the heading jumped to the new compass point the moment the
    -- key was pressed. What you SEE is the view chasing it - the stars sweep, the ship
    -- banks, and it settles about half a second later. The course is already correct
    -- throughout; only the picture is catching up.
    local d = angleDiff(ship.heading, ship.look)
    ship.turn = d * 0.18
    ship.look = ship.look + ship.turn
    if math.abs(d) < 0.002 then ship.look, ship.turn = ship.heading, 0 end

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

    -- Shields creep back once nobody has hit you for a few seconds. Free, but slow enough
    -- that running away to heal is a real decision rather than an obvious one.
    local nowMs = device.time()
    if ship.sh < ship.maxsh and nowMs - lastHit > SHIELD_CALM_MS
       and nowMs - lastRegen > SHIELD_REGEN_MS then
        ship.sh = ship.sh + 1
        lastRegen = nowMs
    end

    -- Retire finished explosions.
    for i = #blasts, 1, -1 do
        if nowMs - blasts[i].born > 520 then table.remove(blasts, i) end
    end

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
            local sc = math.floor(2200 / dist)
            if sc < 1 then sc = 1 end
            if sc > 7 then sc = 7 end
            canvas.sprite(px - (PIRATE_W * sc) / 2, CY - (7 * sc) / 2,
                          PIRATE_W, PIRATE_ART, PIRATE_PAL, sc)
        end
    end

    -- Explosions: a bright core that punches outward and fades through orange to red as
    -- it goes, with debris flung out around it. Sits in the world at the spot the pirate
    -- died, so it stays put and slides past properly as you keep flying.
    for _, b in ipairs(blasts) do
        local px, dist = project(b.x, b.y)
        if px and dist < 4000 then
            local age = (device.time() - b.born) / 520        -- 0 -> 1 over its life
            if age < 0 then age = 0 end
            local sc = math.floor(2200 / math.max(dist, 60))
            if sc < 1 then sc = 1 end
            if sc > 7 then sc = 7 end
            local r = math.floor((3 + age * 16) * sc / 2)
            local col = (age < 0.25 and 0xffffff) or (age < 0.5 and 0xffe9a8)
                        or (age < 0.75 and 0xff9f0a) or 0xff453a
            -- ring: four blocks pushed out from the centre rather than a real circle,
            -- which is cheap and reads correctly at these sizes
            local t = math.max(2, math.floor(sc * 1.5))
            canvas.rect(px - r, CY - t / 2, r * 2, t, col)
            canvas.rect(px - t / 2, CY - r, t, r * 2, col)
            if age < 0.55 then
                local c = math.floor(r * 0.7)
                canvas.rect(px - c / 2, CY - c / 2, c, c, age < 0.3 and 0xffffff or 0xffe9a8)
            end
            -- debris, thrown out along the diagonals
            if age > 0.15 then
                local d = math.floor(r * 0.8)
                local ds = math.max(1, sc)
                canvas.rect(px - d, CY - d, ds, ds, 0xff9f0a)
                canvas.rect(px + d, CY - d, ds, ds, 0xff9f0a)
                canvas.rect(px - d, CY + d, ds, ds, 0xff453a)
                canvas.rect(px + d, CY + d, ds, ds, 0xff453a)
            end
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
                    local sc = math.floor(2600 / dist)
                    if sc < 1 then sc = 1 end
                    if sc > 6 then sc = 6 end
                    canvas.sprite(px - (STATION_W * sc) / 2, CY - (9 * sc) / 2,
                                  STATION_W, STATION_ART[st.kind + 1], STATION_PAL, sc)
                end
            end
        end
    end

    -- Derelicts, drawn in space so you can spot one and go and take a look. A stripped
    -- hulk goes grey, which is how you tell at a glance you've already been here.
    for _, w in ipairs(wrecksNearby) do
        local px, dist = project(w.x, w.y)
        if px and dist < 3000 then
            local sc = math.floor(2000 / dist)
            if sc < 1 then sc = 1 end
            if sc > 6 then sc = 6 end
            canvas.sprite(px - (WRECK_W * sc) / 2, CY - (7 * sc) / 2, WRECK_W, WRECK_ART,
                          w.done and WRECK_DONE_PAL or WRECK_PAL, sc)
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

    -- Two bars, stacked: shields on top in blue, hull underneath. Keeping them separate
    -- and adjacent is the whole point - you can see at a glance whether the damage you
    -- just took will heal itself or is going to cost you Parts.
    local shFrac = ship.sh / ship.maxsh
    canvas.rect(120, H - 20, 90, 5, 0x2c2c2e)
    if shFrac > 0 then
        canvas.rect(120, H - 20, math.floor(90 * shFrac), 5, 0x0a84ff)
    end
    local frac = ship.hp / ship.maxhp
    local barW = math.floor(90 * frac)
    canvas.rect(120, H - 13, 90, 7, 0x2c2c2e)
    if barW > 0 then
        canvas.rect(120, H - 13, barW, 7,
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

    -- Dock buttons, drawn from the same list the touch handler reads. A button you can't
    -- afford still shows, greyed - "REPAIR 10p" when you have 4 Parts tells you what to
    -- go and do, where hiding it would just look like the station was broken.
    --
    -- SEE-THROUGH: the canvas has no alpha - every colour is fully opaque - so the fill
    -- is painted as alternating single-pixel rows. The gaps let the starfield and
    -- anything moving out there show through, which matters because you can be shot at
    -- while parked. Cheap too: 13 rows a button instead of thousands of pixels. The
    -- caption is a real label drawn on top, so the text stays perfectly solid.
    for _, b in ipairs(dockButtons()) do
        local edge = b.on and 0x0a84ff or 0x3a3a42
        local fill = b.on and 0x1c3a5e or 0x24242a
        for yy = b.y + 2, b.y + b.h - 3, 2 do
            canvas.rect(b.x, yy, b.w, 1, fill)
        end
        canvas.rect(b.x, b.y, b.w, 2, edge)
        canvas.rect(b.x, b.y + b.h - 2, b.w, 2, edge)
        canvas.rect(b.x, b.y, 2, b.h, edge)
        canvas.rect(b.x + b.w - 2, b.y, 2, b.h, edge)
    end

    canvas.flip()

    -- Text goes on labels, which are crisper than anything we can draw by hand.
    screen.label(3, 8, 22, "X " .. math.floor(ship.x) .. "  Y " .. math.floor(ship.y), 0x8e8e93)
    screen.label(4, 250, 22, headingName(ship.heading), 0x30d158)

    findNearest()
    if nearest then
        local bearing = math.atan(nearest.x - ship.x, nearest.y - ship.y)
        local rel = angleDiff(bearing, ship.heading)
        -- Now that every heading has a name and a tap lands on one exactly, the readout
        -- can give a real instruction instead of a vague "turn left": it names the point
        -- to steer to, and you tap until the compass agrees. "ahead" means it genuinely
        -- is - within half a point, so nothing you could steer to aims at it better.
        local arrow = (math.abs(rel) < STEP / 2) and "ahead" or ("steer " .. headingName(bearing))
        screen.label(5, 8, H - 40, "station " .. math.floor(nearestDist) .. "  " .. arrow, 0x0a84ff)
    else
        screen.label(5, 8, H - 40, "no station in range", 0x4a4a52)
    end

    -- Both currencies together: credits buy missiles, Parts fix hulls.
    screen.label(6, 228, H - 40, credits .. "c  " .. parts .. "p", 0xffd60a)

    -- One line, two jobs, resolved by priority. A pickup ("+2 PARTS") takes it for a
    -- second or so because it just happened; otherwise, whenever you're inside docking
    -- range of a station, its name simply stays up until you leave. So the name on screen
    -- IS the "you can dock here" indicator rather than a separate thing to learn.
    local nowT = device.time()
    local line = nil
    if popText and nowT < popUntil then
        line = popText
    elseif nearest and nearestDist <= DOCK_RANGE then
        line = nearest.name
    end
    if line then
        screen.label(12, math.floor((W - #line * 7) / 2), 44, line, 0x9ad0ff)
    else
        screen.hide(12)
    end

    if docked then
        local cap = dockedOn == "wreck" and "DERELICT" or "DOCKED"
        screen.label(9, math.floor((W - #cap * 7) / 2), 152, cap, 0x30d158)
    else
        screen.hide(9)
    end

    -- Button captions ride on top of the boxes drawn on the canvas, and every reserved
    -- slot gets hidden when there's nothing to offer - otherwise a caption from the last
    -- station you visited would still be sitting there in open space.
    local btns = dockButtons()
    for i, slot in ipairs(BTN_SLOT) do
        local b = btns[i]
        if b then
            screen.label(slot, b.x + math.floor((b.w - #b.text * 7) / 2), b.y + 7, b.text,
                         b.on and 0xffffff or 0x6a6a72)
        else
            screen.hide(slot)
        end
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
