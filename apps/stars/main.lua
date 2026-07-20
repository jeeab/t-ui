-- Starfield: Deep Space ---------------------------------------------------------
-- Fly a ship through an endless, generated galaxy.
--
--   A / D  turn one compass point   W faster / S slower (S all the way = stop)
--   L  laser - eight tiers, green up to a shock ball, and the beam colour tells you which
--   P  phoenix missile (one shot, one kill, whatever it hits)
--   M  map of nearby space      tap sides to turn
--
-- Stop beside a STATION to meet the harbourmaster: repair, exchange (sell salvage, buy
-- missiles and Parts), or UPGRADES - the shelf of named gear this particular station
-- happens to stock. Nothing can shoot you while you're tied up alongside.
-- Stop beside a DERELICT to salvage it - out in the open, where you CAN still be shot.
--
-- TWO axes of difficulty, and they work differently on purpose. DANGER is scattered about
-- the map, so a bad sector is something you can look at and go around. DEPTH - how far
-- out from where you started - only ever goes up, and it raises the number of raiders,
-- their toughness, and the share of them that are purple marauders. The good gear is only
-- sold out there, so the game asks you to go somewhere that will hurt to get it.
--
-- The galaxy is NOT stored anywhere. Every sector's contents come from a hash of its
-- coordinates and the world seed, so space is effectively infinite, costs no memory,
-- and a station you find at 412,-89 is still there when you fly back. Same seed =
-- same galaxy, so two devices can explore the identical universe.
----------------------------------------------------------------------------------
local W, H = 320, 240
local CX, CY = W / 2, H / 2
local STARS = 200

-- ---- how wide is that text, really? -------------------------------------------
-- The screen's font is PROPORTIONAL: a 'W' is 18 pixels and an 'i' is 4.5. This code
-- used to assume a flat 7 pixels for every character, which was wrong in both
-- directions and wrong by a lot - capitals actually average 11.6. Two visible bugs came
-- out of that one guess: long lines (the harbourmaster's greeting especially) ran off
-- the right-hand edge of the screen, and every "centred" caption was measured short and
-- so sat too far right, crowding or spilling past the edge of its own button.
--
-- These are the real advance widths of the firmware's font, in QUARTER-pixels so the
-- whole table fits in one byte per character with no meaningful rounding error. Index is
-- the ASCII code minus 31; anything outside 32..126 is measured as a space.
local GLYPH_Q = "\017\017\025\045\040\054\044\014\022\022\026\037\014\024\014"
                .. "\022\043\024\037\036\043\037\040\038\041\040\014\014\037\037"
                .. "\037\037\066\047\048\046\053\043\041\050\052\020\033\046\038"
                .. "\061\052\054\046\054\046\040\038\050\046\072\043\042\042\021"
                .. "\022\021\037\032\038\044\044\036\044\039\022\044\044\018\018"
                .. "\040\018\068\044\041\044\044\026\032\026\043\036\058\035\036"
                .. "\033\022\019\022\037"

local function textW(s)
    s = tostring(s)
    local n = 0
    for i = 1, #s do
        local c = s:byte(i)
        if c < 32 or c > 126 then c = 32 end
        n = n + GLYPH_Q:byte(c - 31)
    end
    return n / 4
end

-- Left-hand x that puts text of this width centred inside a box. One helper so the
-- drawing code can never centre one thing correctly and another thing by eye.
local function centreX(s, x, w)
    return x + math.floor((w - textW(s)) / 2)
end

-- Break a line so each piece fits in maxw pixels. Only ever returns two pieces, because
-- that's all the room there is beside the harbourmaster's head - a third line would run
-- into the shop buttons underneath. Splits on spaces; a single word too long to fit is
-- left alone rather than chopped mid-word, since every line in the game is written to
-- fit and a broken word would look worse than a slight overhang.
local function wrap2(s, maxw)
    if textW(s) <= maxw then return s, nil end
    local best = nil
    for i = 1, #s do
        if s:sub(i, i) == " " and textW(s:sub(1, i - 1)) <= maxw then best = i end
    end
    if not best then return s, nil end
    return s:sub(1, best - 1), s:sub(best + 1)
end
local FOV = 1.05                -- half field of view, radians (~60 degrees)
local SECTOR = 1000             -- world units per sector
-- World units per frame at ONE notch of throttle; top notch is three times this. It ran
-- at 6 (so 18 a frame flat out), which crossed a whole 1000-unit sector in under two
-- seconds - the galaxy went by faster than it could fill up with anything. At 3 the same
-- crossing takes about four seconds and the map is effectively twice the size. This is
-- the ONE number to change if cruising still feels wrong: lower is slower.
-- Deliberately NOT applied to the starfield, which still streaks at the old rate off the
-- throttle notch, so flat out still LOOKS fast - it just covers less ground.
local WARP_SPEED = 3
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
              hp = 100, maxhp = 100, sh = 50, maxsh = 50,
              -- What you're flying WITH. All three start at mark 1 and only ever go up:
              -- there is no selling your gun back, so every station visit is a decision
              -- you can't undo by wandering into a worse shop later.
              laser = 1, shieldMk = 1, hullMk = 1}
local SHIELD_CALM_MS = 3000      -- how long since the last hit before it starts coming back

-- ---- outfitting ---------------------------------------------------------------
-- Eight lasers, and you can tell which one you're firing WITHOUT reading a number: the
-- beam changes colour as it gets stronger. Green is what you launch with and orange is
-- late-game, which is deliberately not the order a rainbow comes in - it's the order
-- these read as "hotter" on a black screen. The top tier stops being a beam at all and
-- fires a shock ball, so the last upgrade looks like an event rather than a brighter line.
--
-- Damage climbs faster than price does at the bottom and slower at the top, so the first
-- upgrade is a big obvious jump (it's the one that teaches you upgrades exist) and the
-- last is a long haul you fly a long way to afford.
local LASER = {
    {name = "GREEN",  dmg = 1,  cost = 0,     core = 0x8affc1, glow = 0x30d158},
    {name = "BLUE",   dmg = 2,  cost = 900,   core = 0x9ad0ff, glow = 0x0a84ff},
    {name = "YELLOW", dmg = 3,  cost = 1500,  core = 0xfff3a8, glow = 0xffd60a},
    {name = "RED",    dmg = 4,  cost = 2400,  core = 0xff9d95, glow = 0xff453a},
    {name = "PURPLE", dmg = 6,  cost = 3600,  core = 0xe0a8ff, glow = 0xbf5af2},
    {name = "ORANGE", dmg = 8,  cost = 5200,  core = 0xffd3a0, glow = 0xff9f0a},
    {name = "WHITE",  dmg = 11, cost = 7500,  core = 0xffffff, glow = 0xc7c7cc},
    {name = "SHOCK",  dmg = 15, cost = 11000, core = 0xaaffcc, glow = 0x30d158},
}

-- Shields get BOTH bigger and quicker to come back, because either one alone is a
-- disappointing purchase: a longer bar you wait ages to refill still means running away,
-- and a fast trickle on a small bar still pops in one exchange of fire.
local SHIELD = {
    {max = 50,  regen = 900, cost = 0},
    {max = 75,  regen = 750, cost = 1100},
    {max = 110, regen = 600, cost = 2500},
    {max = 150, regen = 450, cost = 4600},
    {max = 200, regen = 320, cost = 8000},
}

-- Hull is the expensive stat to actually use, since damage to it costs Parts to undo.
-- A bigger hull is therefore worth less than it looks - it buys you survival, not thrift.
local HULL = {
    {max = 100, cost = 0},
    {max = 140, cost = 1300},
    {max = 190, cost = 2900},
    {max = 250, cost = 5500},
    {max = 320, cost = 9500},
}

-- Marks decide the ceilings, so this has to run after anything that changes them AND
-- after a load. Current hull/shields are clamped rather than topped up: buying a bigger
-- hull gives you room to repair into, not a free repair.
local function applyMarks()
    ship.maxsh = SHIELD[ship.shieldMk].max
    ship.maxhp = HULL[ship.hullMk].max
    if ship.sh > ship.maxsh then ship.sh = ship.maxsh end
    if ship.hp > ship.maxhp then ship.hp = ship.maxhp end
end
-- ONE number for "close enough to deal with": it decides both when you can dock and when
-- a station's name is up on screen. Keeping them the same means the name appearing is
-- exactly the signal that you're in range, and the two can never drift apart.
local DOCK_RANGE = 260
local WRECK_RANGE = 240
local REPAIR_COST = 10           -- Parts for a full hull repair
local SALVAGE_PARTS = 5          -- Parts per derelict
local MISSILE_COST = 25          -- credits per missile - exactly one raider's bounty
-- Bounties now live per enemy type in PIRATE_KINDS: a marauder is worth four raiders,
-- which is what stops the tough ones from being purely a tax on flying outward.
local PARTS_PACK = 5             -- Parts you get for buying a pack at a station
local PARTS_COST = 150           -- deliberately poor value: a way out, not a shortcut
-- Selling MUST pay less per Part than buying, or the shop is a money printer: buy five
-- for 150, sell them back for more, repeat forever. 40 out against 150 in keeps the
-- trade honest - it turns a pile of salvage into missiles, it doesn't mint credits.
-- Kept deliberately LOW now that hulks no longer pay in credits: if a wreck's five parts
-- could be sold for real money, salvage would just go straight back to being the safest
-- way to get rich and the whole point of paying bounties properly would be lost. A
-- stripped hulk is worth about 45c all in; a marauder is worth 120c. Fighting wins.
local PARTS_SELL = 40            -- credits for selling a pack of PARTS_PACK
local PIRATE_PARTS = 2           -- salvaged off a kill, when a kill gives anything
local PIRATE_PARTS_CHANCE = 0.34 -- how often a wreck is worth stripping
-- Per-frame chance of another pirate turning up: a floor that always applies, plus a
-- share that only pays out while the sector is under its population cap. See the spawn
-- call for the arithmetic and the measured fill times.
local SPAWN_IDLE = 0.008
local SPAWN_URGE = 0.040
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
-- Which page of the station shop is up: the harbourmaster's greeting, or the counter.
-- Reset the moment you undock, so pulling away and coming back always starts at hello.
local dockMenu = "main"      -- "main" | "exchange"
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

-- How far out from where you started, in sectors. This is the OTHER axis of difficulty,
-- and the important thing about it is that it isn't random: danger is scattered about the
-- map so you can dodge a bad sector, but depth only goes up by flying, and it never lies.
-- Deep space is worse everywhere, so "go further" is a decision rather than a dice roll.
local function depthOf(sx, sy)
    return math.floor(math.sqrt(sx * sx + sy * sy))
end

-- What a station has ON THE SHELF, decided by where it is. A shop out in deep lawless
-- space stocks better gear than one round the corner from home, which is the whole reason
-- to fly somewhere frightening: the good guns are only sold in bad neighbourhoods.
-- Generated from the sector hash like everything else, so a station that had a purple
-- laser has that same purple laser when you fly back for it with the money.
local function stationGrade(sx, sy)
    local g = 1 + math.floor(dangerAt(sx, sy) / 24) + math.floor(depthOf(sx, sy) / 3)
    if g > 8 then g = 8 end
    return g
end

-- Which keeper runs this station, and what he says. Same trick as the name: the face and
-- the line are properties of the PLACE, so docking at a station always meets the same
-- alien saying the same thing, on any device, with nothing stored anywhere.
local function keeperOf(sx, sy)
    local h = hash(sx, sy, 41)
    return (h % 4) + 1, ((h >> 6) % 12) + 1
end

-- Three shelves: gun, shields, hull. Each is at the station's grade give or take a
-- little, and a station only stocks two of the three - a shop with everything makes the
-- next one pointless, and you want a reason to keep visiting.
local function stationStock(sx, sy)
    local g = stationGrade(sx, sy)
    local h = hash(sx, sy, 31)
    local skip = h % 3                     -- which shelf this station doesn't carry
    local items = {}
    -- Laser
    local ll = g + (((h >> 3) % 3) - 1)
    if ll < 2 then ll = 2 end
    if ll > 8 then ll = 8 end
    if skip ~= 0 then
        items[#items + 1] = {kind = "laser", lvl = ll, cost = LASER[ll].cost,
                             label = LASER[ll].name .. " LASER (" .. ll .. ")"}
    end
    -- Shields, on a 5-mark scale rather than 8, so the grade is squeezed down to fit
    local sl = 2 + math.floor((g - 1) * 4 / 7) + (((h >> 7) % 3) - 1)
    if sl < 2 then sl = 2 end
    if sl > 5 then sl = 5 end
    if skip ~= 1 then
        items[#items + 1] = {kind = "shield", lvl = sl, cost = SHIELD[sl].cost,
                             label = "SHIELD MK" .. sl .. " (" .. SHIELD[sl].max .. ")"}
    end
    -- Hull, same squeeze
    local hl = 2 + math.floor((g - 1) * 4 / 7) + (((h >> 11) % 3) - 1)
    if hl < 2 then hl = 2 end
    if hl > 5 then hl = 5 end
    if skip ~= 2 then
        items[#items + 1] = {kind = "hull", lvl = hl, cost = HULL[hl].cost,
                             label = "HULL MK" .. hl .. " (" .. HULL[hl].max .. ")"}
    end
    return items
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
-- Three things fly at you, and they want different answers from you rather than just
-- having different numbers. The raider is the baseline. The interceptor is FAST and
-- fragile - it closes before you've finished turning, so it punishes flying straight.
-- The marauder is the purple one: three times the hull, hits nearly twice as hard, and
-- slow enough that you can run - which is usually the right call until your gun is better.
-- Bounties carry the whole economy now. They used to be pocket change next to a derelict
-- (10c for a raider against ~70c for a hulk you could strip in total safety), which meant
-- the most profitable thing in the game was also the least dangerous one - the reason it
-- was possible to get rich and bored at the same time. Fighting is now where the money
-- is, and a marauder is worth roughly what a whole wreck used to be.
local PIRATE_KINDS = {
    {name = "raider",      hpMul = 1,  bounty = 25, dmg = 6,  speed = 3.0, cool = 1.0,
     w = 9,  h = 7, near = 2200},
    {name = "interceptor", hpMul = 0.5, bounty = 40, dmg = 4, speed = 5.5, cool = 0.55,
     w = 7,  h = 5, near = 1700},
    {name = "marauder",    hpMul = 3,  bounty = 120, dmg = 11, speed = 2.2, cool = 1.4,
     w = 11, h = 9, near = 2800},
}

local function maxPiratesHere()
    local csx, csy = math.floor(ship.x / SECTOR), math.floor(ship.y / SECTOR)
    local d = dangerAt(csx, csy)
    local depth = depthOf(csx, csy)
    local n = 0
    if d >= 62 then n = 3 + math.floor((d - 62) / 13) end
    -- Depth adds raiders on top of whatever the sector was already going to field, and it
    -- adds them to QUIET sectors too. That's the point: near home a peaceful sector is
    -- genuinely empty, but a long way out there is no such thing as empty space, so
    -- distance is felt as pressure rather than just as a bigger number on the position.
    n = n + math.floor(depth / 4)
    if n > 8 then n = 8 end
    return n
end

-- A station is a safe harbour: tied up alongside, nobody can touch you. This is not just
-- a kindness - reading a shop menu while bolts land is the one moment in the game where
-- you're being punished for something that isn't flying. A DERELICT is deliberately NOT
-- safe: stripping a hulk in open space should stay a risk you took, which is what makes
-- wrecks worth more than shopping.
local function safeHarbour()
    return docked and dockedOn == "station"
end

local function spawnPirate()
    if safeHarbour() then return end                    -- nobody jumps a station
    local csx, csy = math.floor(ship.x / SECTOR), math.floor(ship.y / SECTOR)
    local d = dangerAt(csx, csy)
    local depth = depthOf(csx, csy)
    -- The gate is now the population, not the danger rating on its own: deep space fields
    -- raiders even where the law is technically fine, so this has to ask the same question
    -- the cap does or quiet-but-deep sectors would stay empty forever.
    if #pirates >= maxPiratesHere() then return end
    -- appear somewhere ahead-ish, far enough away to be seen coming
    local ang = ship.look + (math.random() - 0.5) * 2.2
    local dist = 1600 + math.random() * 900

    -- Which sort turns up. Marauders are the reward for going somewhere stupid, so their
    -- share is driven mostly by DEPTH and only topped up by local lawlessness - that way
    -- a nasty sector near home stays survivable in a starting ship, and the purple ones
    -- are something you meet because you flew out to meet them.
    local marauder = depth * 0.02
    if d >= 62 then marauder = marauder + (d - 62) / 300 end
    if marauder > 0.40 then marauder = 0.40 end
    local r = math.random()
    local ki = 1
    if r < marauder then ki = 3
    elseif r < marauder + 0.22 then ki = 2 end
    local k = PIRATE_KINDS[ki]

    -- Base hull, then the kind's multiplier on top. Danger decides toughness where the law
    -- is thin; depth adds to it everywhere. A marauder deep out is genuinely a wall of a
    -- thing - which is exactly what the laser upgrades are for.
    local hp = 5
    if d >= 62 then hp = hp + math.floor((d - 62) / 13) end
    hp = hp + math.floor(depth / 6)
    if hp > 12 then hp = 12 end
    hp = math.floor(hp * k.hpMul)
    if hp < 2 then hp = 2 end

    pirates[#pirates + 1] = {
        x = ship.x + math.sin(ang) * dist,
        y = ship.y + math.cos(ang) * dist,
        hp = hp,
        kind = ki,
        cool = (800 + math.random() * 1500) * k.cool,
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
    -- The shot carries the gun's tier with it, so what's already in flight keeps the
    -- colour it was fired with even if you dock and buy a better one a second later.
    shots[#shots + 1] = {kind = kind, dist = 0, ang = ship.look, born = now,
                         tier = ship.laser}
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
                    -- The phoenix is one shot, one kill, and stays that way now a deep
                    -- marauder can carry 36 hull. Fixed damage would have quietly demoted
                    -- the missile to "a slightly better laser" the moment they got tougher.
                    -- The laser now asks the gun you actually own how hard it hits.
                    p.hp = p.hp - (sh.kind == "laser" and LASER[ship.laser].dmg or 99)
                    hit = true
                    if p.hp <= 0 then
                        local pk = PIRATE_KINDS[p.kind or 1]
                        -- Leave a blast behind at the pirate's own position, so the kill
                        -- happens out there in the world and stays put as you fly past it.
                        -- Big things blow up bigger; killing a marauder should look like
                        -- the achievement it was.
                        blasts[#blasts + 1] = {x = p.x, y = p.y, born = device.time(),
                                               big = pk.hpMul >= 3}
                        table.remove(pirates, pi)
                        credits = credits + pk.bounty
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
    -- Made it inside the perimeter. Bolts already in flight veer off rather than landing
    -- on a docked ship, so diving for a station is a genuine escape and not a trick that
    -- still costs you the last two hits.
    if safeHarbour() then
        for i = #incoming, 1, -1 do table.remove(incoming, i) end
        return
    end
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
            -- The bolt carries its own damage because a marauder's shot has to land
            -- harder than an interceptor's; older bolts with no figure on them fall back
            -- to the flat 6 this used to be.
            local dmg = b.dmg or 6
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
    local safe = safeHarbour()
    for pi = #pirates, 1, -1 do
        local p = pirates[pi]
        local dx, dy = p.x - ship.x, p.y - ship.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 5000 then
            table.remove(pirates, pi)                    -- outrun: warping away works
        elseif safe then
            -- Docked. They sheer away from the station's guns instead of hanging in the
            -- air politely not shooting - you can watch them give up, which tells you the
            -- harbour is doing something rather than the game having quietly paused.
            p.x = p.x + (dx / d) * 9
            p.y = p.y + (dy / d) * 9
        else
            -- close in, at whatever pace this sort flies. An interceptor covering ground
            -- nearly twice as fast as a raider is the whole of its threat - it is barely
            -- worth shooting, but it will be on you before you finish the turn.
            local k = PIRATE_KINDS[p.kind or 1]
            p.x = p.x - (dx / d) * k.speed
            p.y = p.y - (dy / d) * k.speed
            -- Shoot something you can actually see coming, rather than damaging you out
            -- of nowhere: the bolt is launched here and travels toward you over a second
            -- or so, growing as it closes. Getting hit should never be a surprise.
            if d < 1600 and now > (p.lastShot or 0) + p.cool then
                p.lastShot = now
                incoming[#incoming + 1] = {x = p.x, y = p.y, dist = d, dmg = k.dmg,
                                           kind = p.kind or 1}
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
    local wasDocked = docked
    docked, dockedOn, dockedWreck = false, nil, nil
    if ship.warp > 0 then
        if wasDocked then dockMenu = "main" end   -- pulled away: next visit starts at hello
        return                                    -- you dock by stopping
    end

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

-- Turning a pile of salvage into spending money. Sold as a pack rather than one at a
-- time so a hold full of Parts doesn't mean forty taps.
local function sellParts()
    if not docked or dockedOn ~= "station" then return false end
    if parts < PARTS_PACK then return false end
    parts = parts - PARTS_PACK
    credits = credits + PARTS_SELL
    popup("+" .. PARTS_SELL .. " CREDITS", 1400)
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
    -- A hulk is a source of PARTS, not of money. It used to hand over 25-64 credits on
    -- top of the parts, which quietly made salvage the best-paid job in the galaxy and
    -- left no reason to ever pick a fight. What's left is loose change - enough that
    -- stripping a wreck isn't nothing, not enough to live on.
    credits = credits + (hash(w.sx, w.sy, 5) % 11)
    if hash(w.sx, w.sy, 9) % 3 == 0 and missiles < 6 then missiles = missiles + 1 end
    w.done = true
    device.beep(true)
    return true
end

-- Which mark of a thing you're currently flying. One place that knows what "better" means
-- for each kind of gear, because the no-downgrade rule has to be enforced identically in
-- the shop list, the buy itself, and the greying - three answers would eventually disagree.
local function currentLevel(kind)
    if kind == "laser" then return ship.laser end
    if kind == "shield" then return ship.shieldMk end
    return ship.hullMk
end

-- Fitting new gear. There is no selling it back and nothing worse is ever offered, so a
-- ship only ever gets stronger. That's a deliberate design rule and not an oversight: the
-- whole point of a named item on a shelf ("PURPLE LASER (5)") is that you can look at it,
-- decide you can't afford it yet, and come back - which only works if leaving and
-- returning can't cost you anything.
local function buyUpgrade(item)
    return function()
        if not docked or dockedOn ~= "station" then return false end
        if item.lvl <= currentLevel(item.kind) then return false end
        if credits < item.cost then return false end
        credits = credits - item.cost
        if item.kind == "laser" then
            ship.laser = item.lvl
            popup(LASER[item.lvl].name .. " LASER FITTED", 2200)
        elseif item.kind == "shield" then
            ship.shieldMk = item.lvl
            applyMarks()
            -- A new generator arrives charged. It would refill itself for free anyway, so
            -- making you sit and wait for it would only be a tax on having just bought it.
            ship.sh = ship.maxsh
            popup("SHIELD MK" .. item.lvl .. " FITTED", 2200)
        else
            ship.hullMk = item.lvl
            applyMarks()
            -- Deliberately NOT a free repair: a bigger hull is room to repair into. If it
            -- healed you too it would be strictly better than paying Parts, and nobody
            -- would ever press REPAIR again.
            popup("HULL MK" .. item.lvl .. " FITTED", 2200)
        end
        device.beep(true)
        return true
    end
end

-- What you can actually do while docked. ONE list, read by both the drawing code and the
-- touch handler, so a button can never appear somewhere it isn't tappable (or worse, be
-- tappable where nothing is drawn). Sits in the middle band, clear of the turn thirds at
-- the screen edges and the throttle strip along the bottom.
local BTN_X, BTN_W, BTN_H = 92, 136, 26
-- The outfitter's rows are wider than the rest of the shop's, because the goods are NAMED.
-- "PURPLE LASER (5)  480c" is 22 characters and the whole value of naming it is lost if it
-- gets cut off, so that page gets nearly the full width of the screen.
local SHOP_X, SHOP_W = 30, 260
-- Where the harbourmaster's speech starts: clear of his portrait, which is drawn at x 8
-- and is ALIEN_W (11) at scale 4 = 44 pixels wide, so it ends at 52.
local SAY_X = 58
local BTN_SLOT = {20, 21, 22, 23}      -- label ids, well clear of the HUD's own slots
local function dockButtons()
    local b = {}
    local top, h = 62, BTN_H
    local bx, bw = BTN_X, BTN_W
    if not docked then return b end
    if dockedOn == "station" then
        if dockMenu == "upgrades" then
            -- The outfitter. Only things that BEAT what you're flying are listed, which is
            -- what makes the rule "you can't downgrade" invisible rather than a message
            -- you have to read. A shop you've outgrown says so plainly instead of
            -- appearing broken or empty.
            top, h, bx, bw = 56, 24, SHOP_X, SHOP_W
            local stock = nearest and stationStock(nearest.sx, nearest.sy) or {}
            local offered = 0
            for _, it in ipairs(stock) do
                if it.lvl > currentLevel(it.kind) and offered < 3 then
                    offered = offered + 1
                    b[#b + 1] = {text = it.label .. "  " .. it.cost .. "c",
                                 act = buyUpgrade(it), on = credits >= it.cost}
                end
            end
            if offered == 0 then
                b[#b + 1] = {text = "NOTHING BETTER HERE", on = false,
                             act = function() return false end}
            end
            b[#b + 1] = {text = "BACK", on = true,
                         act = function() dockMenu = "main"; device.beep(); return true end}
        elseif dockMenu == "exchange" then
            -- The counter. Four rows, so they start higher and sit tighter; the last one
            -- overlaps your own ship at y 170, which is fine because the buttons are drawn
            -- see-through and it reads as glass rather than as a collision.
            top, h = 62, 24
            b[#b + 1] = {text = "SELL " .. PARTS_PACK .. "p +" .. PARTS_SELL .. "c",
                         act = sellParts, on = parts >= PARTS_PACK}
            b[#b + 1] = {text = "REARM " .. MISSILE_COST .. "c", act = buyMissile,
                         on = credits >= MISSILE_COST and missiles < 6}
            b[#b + 1] = {text = "BUY " .. PARTS_PACK .. "p " .. PARTS_COST .. "c",
                         act = buyParts, on = credits >= PARTS_COST}
            b[#b + 1] = {text = "BACK", on = true,
                         act = function() dockMenu = "main"; device.beep(); return true end}
        else
            -- The greeting: three doors, each a different KIND of errand rather than a
            -- price list. Trade, outfit, repair. It sits low enough to leave the
            -- harbourmaster and his line of dialogue the top half of the screen, and the
            -- last row now stops exactly where your own ship starts.
            top, h = 106, 24
            b[#b + 1] = {text = "EXCHANGE", on = true,
                         act = function() dockMenu = "exchange"; device.beep(); return true end}
            b[#b + 1] = {text = "UPGRADES", on = true,
                         act = function() dockMenu = "upgrades"; device.beep(); return true end}
            b[#b + 1] = {text = "REPAIR " .. REPAIR_COST .. "p", act = repairHull,
                         on = parts >= REPAIR_COST and ship.hp < ship.maxhp}
        end
    elseif dockedOn == "wreck" and dockedWreck and not isSalvaged(dockedWreck.sx, dockedWreck.sy) then
        b[#b + 1] = {text = "SALVAGE +" .. SALVAGE_PARTS .. "p", act = salvageWreck, on = true}
    end
    for i, btn in ipairs(b) do
        btn.x, btn.y, btn.w, btn.h = bx, top + (i - 1) * (h + 4), bw, h
    end
    return b
end

-- ---- save --------------------------------------------------------------------
-- Tiny, because the galaxy is generated rather than stored: just where we are.
local function save()
    -- ship state, then the wrecks already stripped. Still tiny: the galaxy is generated.
    -- The three gear marks go on the END of the line rather than anywhere sensible,
    -- because the fields are read back by POSITION - appending is the only change that
    -- leaves every older save still loading correctly.
    store.write("save.txt", table.concat({seed, math.floor(ship.x), math.floor(ship.y),
                                          math.floor(ship.heading * 180 / math.pi), ship.hp, credits,
                                          missiles, parts, math.floor(ship.sh),
                                          ship.laser, ship.shieldMk, ship.hullMk}, ",")
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
        -- Gear marks. A save written before upgrades existed simply has no such fields, so
        -- it loads as a mark-one ship - which is precisely what it was. Clamped both ways
        -- because a corrupted digit here would otherwise index straight off the tables.
        ship.laser = math.min(math.max(v[10] or 1, 1), #LASER)
        ship.shieldMk = math.min(math.max(v[11] or 1, 1), #SHIELD)
        ship.hullMk = math.min(math.max(v[12] or 1, 1), #HULL)
        -- The ceilings have to exist BEFORE the saved shields are measured against them,
        -- or a ship with a mark-4 generator would reload capped at the mark-1 maximum.
        applyMarks()
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


-- The three raider sprites, indexed to match PIRATE_KINDS. Drawn at a scale that grows as
-- they close, so a distant contact is a speck and a close one fills a chunk of the screen.
-- They're told apart by COLOUR and SIZE before you can make out any detail, which matters
-- because the decision you need to make - fight it or run - has to happen while it's still
-- a smudge. Red is a fair fight, yellow is quick, purple means turn around.
local PIRATE_ART = {
    -- raider, 9x7: the baseline, red
    "   RRR   " ..
    "  RRRRR  " ..
    " RRWWWRR " ..
    "RRRWCWRRR" ..
    " RRWWWRR " ..
    "  R R R  " ..
    " F     F ",
    -- interceptor, 7x5: small and pointed, all engine
    "   Y   " ..
    "  YCY  " ..
    " YYCYY " ..
    "YYY YYY" ..
    " F   F ",
    -- marauder, 11x9: the purple one, twice the frontage of a raider
    "    PPP    " ..
    "  PPPPPPP  " ..
    " PPMMMMMPP " ..
    " PMMCWCMMP " ..
    "PPMMCWCMMPP" ..
    " PMMMMMMMP " ..
    " PP MMM PP " ..
    "PP   P   PP" ..
    " F   F   F ",
}
local PIRATE_PAL = {
    {["R"] = 0xff453a, ["W"] = 0x8a1f18, ["C"] = 0xffe9a8, ["F"] = 0xff9f0a},
    {["Y"] = 0xffd60a, ["C"] = 0xfff3a8, ["F"] = 0xff9f0a},
    {["P"] = 0xbf5af2, ["M"] = 0x6b2a8a, ["C"] = 0xe0a8ff, ["W"] = 0xffffff, ["F"] = 0xff9f0a},
}

-- The harbourmasters, 11x13, drawn big (scale 4) beside their own line of dialogue while
-- you're tied up at a station. Every other sprite in this game is something out in the
-- world seen at a distance; these are the only ones you meet face to face, so they get the
-- room. FOUR of them, picked by the station's own hash - so a station has the same
-- keeper every time you dock there, and the galaxy stops being staffed by one clone.
local ALIEN_W = 11
local ALIEN_ART = {
    -- the green four-eyed one, in a blue coat
    "   GGGGG   " ..
    "  GGGGGGG  " ..
    " GGGGGGGGG " ..
    " GGEEGGEEG " ..
    " GEKEGEKEG " ..
    " GGEEGGEEG " ..
    " GGGGGGGGG " ..
    "  GGGGGGG  " ..
    "   GGGGG   " ..
    "  SSSSSSS  " ..
    " SSSDDDSSS " ..
    " SS SSS SS " ..
    "  S     S  ",
    -- the cyclops: one wide eye across the whole face, orange coat
    "    CCC    " ..
    "   CCCCC   " ..
    "  CCCCCCC  " ..
    " CCEEEEECC " ..
    " CCEKKKECC " ..
    " CCEEEEECC " ..
    "  CCCCCCC  " ..
    "   CCCCC   " ..
    "  RRRRRRR  " ..
    " RRRDDDRRR " ..
    " RRRRRRRRR " ..
    " RR RRR RR " ..
    "  R     R  ",
    -- the wide tan one with three eyes in a row
    "  TTTTTTT  " ..
    " TTTTTTTTT " ..
    "TTTTTTTTTTT" ..
    "TTEKTEKTEKT" ..
    "TTTTTTTTTTT" ..
    " TTTTTTTTT " ..
    "  TTTTTTT  " ..
    "   TTTTT   " ..
    "  MMMMMMM  " ..
    " MMMKKKMMM " ..
    " MMMMMMMMM " ..
    " MM MMM MM " ..
    "  M     M  ",
    -- the pale tall one with two big dark eyes
    "    PPP    " ..
    "   PPPPP   " ..
    "   PPPPP   " ..
    "  PPPPPPP  " ..
    "  PKKPKKP  " ..
    "  PKKPKKP  " ..
    "  PPPPPPP  " ..
    "   PPPPP   " ..
    "    PPP    " ..
    "  VVVVVVV  " ..
    " VVVVVVVVV " ..
    " VV VVV VV " ..
    "  V     V  ",
}
local ALIEN_PAL = {
    {["G"] = 0x30d158, ["E"] = 0xf2f2f7, ["K"] = 0x101014,
     ["S"] = 0x5e5ce6, ["D"] = 0x3634a3},
    {["C"] = 0x64d2ff, ["E"] = 0xf2f2f7, ["K"] = 0x101014,
     ["R"] = 0xff9f0a, ["D"] = 0xc77700},
    {["T"] = 0xd08a4a, ["E"] = 0xf2f2f7, ["K"] = 0x101014, ["M"] = 0x4a4a52},
    {["P"] = 0xe8e0f0, ["K"] = 0x2a1a3a, ["V"] = 0xbf5af2},
}

-- What they say. Picked by the station's hash like the face is, so a keeper has his own
-- line as well as his own head. A few of them quietly teach the thing a new player would
-- otherwise have to work out for themselves - that the good guns are sold a long way out,
-- and that the purple ships are not a fair fight.
local ALIEN_SAY = {
    "ARRG! What can I do for you?",
    "Long way from home, aren't you?",
    "Credits first. Questions later.",
    "Best guns are sold out in the deep.",
    "You look like you've been shot at.",
    "Buy something or mind the airlock.",
    "Nice hull. Shame about the paint.",
    "Purple ones out there. Be careful.",
    "Cargo, guns, or gossip. Pick one.",
    "Still flying that old thing, eh?",
    "Deep space eats ships like yours.",
    "Welcome in. Don't touch anything.",
}

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
    -- Centred rather than pinned at x=14, where it overran the right edge by a couple of
    -- pixels and quietly clipped the "e" off "missile" - the very first thing the game
    -- ever shows you. At 308 pixels this is the widest line in the app; centring it
    -- leaves 6 clear either side and can't drift if the wording changes.
    local hintText = "A/D turn  W/S speed  L laser  P missile"
    screen.label(2, centreX(hintText, 0, W), 210, hintText, 0x8e8e93)
end

function on_tick()
    if not ok then return end

    -- Map is a full screen chart; the world pauses behind it. (This call was missing,
    -- which is why M appeared to do nothing at all.)
    if showMap then
        drawMap()
        for i = 2, 13 do screen.hide(i) end  -- text would float over the chart
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
    local speed = ship.warp * WARP_SPEED
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
    --
    -- The RATE, not the cap, was what made red space feel empty. This rolled a flat 0.4%
    -- once a frame - about one pirate every eight seconds at best - so a sector allowed
    -- five of them needed a solid minute of loitering to actually field five, and anyone
    -- flying through simply outran the spawner and saw nothing. Now the chance scales
    -- with how far UNDER its cap the sector is: somewhere hostile fills up fast and then
    -- idles, so a red region is busy the moment you arrive instead of half an hour later.
    -- Measured at the 30-a-second tick: a 5-pirate sector used to take 41 seconds to fill
    -- and now takes 6. Raise SPAWN_URGE for a rougher galaxy, lower it for a calmer one.
    local cap = maxPiratesHere()
    if #pirates < cap then
        local short = (cap - #pirates) / cap        -- 1.0 = empty, 0.2 = nearly full
        if math.random() < SPAWN_IDLE + SPAWN_URGE * short then spawnPirate() end
    end
    stepPirates()
    stepShots()
    stepIncoming()
    stepDocking()

    -- Shields creep back once nobody has hit you for a few seconds. Free, but slow enough
    -- that running away to heal is a real decision rather than an obvious one.
    local nowMs = device.time()
    if ship.sh < ship.maxsh and nowMs - lastHit > SHIELD_CALM_MS
       and nowMs - lastRegen > SHIELD[ship.shieldMk].regen then
        ship.sh = ship.sh + 1
        lastRegen = nowMs
    end

    -- Retire finished explosions.
    for i = #blasts, 1, -1 do
        if nowMs - blasts[i].born > 520 then table.remove(blasts, i) end
    end

    -- Shots receding from you. A laser is drawn as a BEAM rather than a dot: a streak
    -- trailing back toward the ship, because a bolt of light an eighth of a second long is
    -- what a laser looks like, and a single pixel gave no sense of it travelling. The
    -- streak shortens with distance along with everything else, so it still reads as
    -- going away. The missile keeps its chunky head - it's a physical object, not light.
    for _, sh in ipairs(shots) do
        local rel = angleDiff(sh.ang, ship.look)
        if rel > -FOV and rel < FOV then
            local sx = CX + (rel / FOV) * CX
            local shrink = 1 - (sh.dist / 3000)
            if shrink < 0.05 then shrink = 0.05 end
            local sy = CY + 40 * shrink
            if sh.kind == "laser" then
                -- The gun you're carrying decides the colour, so you can see what you're
                -- firing without reading a number off the HUD. The shot remembers the tier
                -- it was FIRED at rather than asking the ship now: buying a new gun while
                -- a bolt is in flight shouldn't repaint it mid-air.
                local t = LASER[sh.tier or 1]
                if (sh.tier or 1) >= 8 then
                    -- The top tier isn't a beam at all. A shock ball: a bright core inside
                    -- a ragged halo that pulses as it travels, so the last upgrade in the
                    -- game announces itself instead of just being a slightly better line.
                    local r = math.floor(9 * shrink) + 2
                    local cy = sy + r
                    canvas.circle(sx, cy, r, t.glow, true)
                    canvas.circle(sx, cy, math.max(1, r - 2), t.core, true)
                    -- Arcs flicking off the sides, on every other step of its flight. The
                    -- flicker is what makes it read as electrical rather than as a bead.
                    if (sh.dist // 130) % 2 == 0 then
                        canvas.rect(sx - r - 2, cy - 1, 2, 3, t.glow)
                        canvas.rect(sx + r, cy - 1, 2, 3, t.glow)
                        canvas.rect(sx - 1, cy - r - 2, 3, 2, t.glow)
                    end
                else
                    -- Trails DOWNWARD, toward your own ship at the bottom of the screen,
                    -- which is the direction it has just come from.
                    local len = math.floor(30 * shrink) + 3
                    canvas.line(sx, sy, sx, sy + len, t.core)        -- hot core
                    canvas.line(sx - 1, sy + 1, sx - 1, sy + len, t.glow)
                    canvas.line(sx + 1, sy + 1, sx + 1, sy + len, t.glow)
                end
            else
                local sz = math.floor(5 * shrink) + 1
                canvas.rect(sx - sz / 2, sy - sz / 2, sz, sz, 0xff9f0a)
            end
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
            -- A marauder's bolt comes in purple. That's not decoration: it hits for nearly
            -- twice what a raider's does, and the colour is the only warning you get in
            -- time to decide whether to take it on the shields or get out of the way.
            local heavy = (b.kind or 1) == 3
            canvas.rect(px - sz / 2, CY - sz / 2, sz, sz, heavy and 0xbf5af2 or 0xff9f0a)
            canvas.rect(px - sz / 4, CY - sz / 4, sz / 2, sz / 2,
                        heavy and 0xe0a8ff or 0xffe9a8)
        end
    end

    -- Raiders, growing as they close on you. Each sort has its own art, its own dimensions
    -- and its own sense of scale, so a marauder looms noticeably earlier than a raider at
    -- the same range and an interceptor stays a speck until it's nearly on top of you.
    for _, pr in ipairs(pirates) do
        local px, dist = project(pr.x, pr.y)
        if px and dist < 3000 then
            local k = PIRATE_KINDS[pr.kind or 1]
            local sc = math.floor(k.near / dist)
            if sc < 1 then sc = 1 end
            if sc > 7 then sc = 7 end
            canvas.sprite(px - (k.w * sc) / 2, CY - (k.h * sc) / 2,
                          k.w, PIRATE_ART[pr.kind or 1], PIRATE_PAL[pr.kind or 1], sc)
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
            -- A marauder goes up half again as big. Killing one is the hardest thing you
            -- can do out there, and it should look unmistakably different from swatting a
            -- raider - otherwise the win reads exactly like every other win.
            local r = math.floor((3 + age * 16) * sc / 2 * (b.big and 1.5 or 1))
            local col = (age < 0.25 and 0xffffff) or (age < 0.5 and 0xffe9a8)
                        or (age < 0.75 and 0xff9f0a) or 0xff453a
            -- ring: four blocks pushed out from the centre rather than a real circle,
            -- which is cheap and reads correctly at these sizes
            local t = math.max(2, math.floor(sc * 1.5))
            canvas.rect(px - r, CY - t / 2, r * 2, t, col)
            canvas.rect(px - t / 2, CY - r, t, r * 2, col)
            if age < 0.55 then
                -- Never smaller than a single pixel. A kill far enough away has a blast
                -- radius of 1, and seven tenths of that rounds to NOTHING - which asked
                -- the engine to draw a zero-sized rectangle. Harmless on screen, but it
                -- is exactly the sort of thing that is a real complaint on real hardware.
                local c = math.max(1, math.floor(r * 0.7))
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

    -- The ship, banking into the turn. Tied up at a station it drops to sit just above the
    -- HUD: the shop needs the middle band, and this stops the bottom row of buttons being
    -- drawn straight across your own hull. It reads as being moored below the window.
    local frame = 2
    if ship.turn < -0.012 then frame = 1 elseif ship.turn > 0.012 then frame = 3 end
    local shipY = (docked and dockedOn == "station") and 186 or 170
    canvas.sprite(CX - (SHIP_W * SHIP_SCALE) / 2, shipY, SHIP_W, SHIP[frame], PALETTE, SHIP_SCALE)

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
        -- At least one pixel of blue for any shielding at all. This only started
        -- mattering once shields could reach 200: a single point out of 200 is under half
        -- a pixel of a 90-wide bar, so it floored to zero and the bar claimed you had
        -- nothing left when you still had something. Bigger tanks made a rounding
        -- decision that was fine at 50 into a lie.
        canvas.rect(120, H - 20, math.max(1, math.floor(90 * shFrac)), 5, 0x0a84ff)
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

    -- The harbourmaster himself, on the greeting page only. Once you're at the counter the
    -- four buttons need the whole panel, and you've already been said hello to.
    if docked and dockedOn == "station" and dockMenu == "main" and nearest then
        local face = keeperOf(nearest.sx, nearest.sy)
        canvas.sprite(8, 50, ALIEN_W, ALIEN_ART[face], ALIEN_PAL[face], 4)
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

    -- Both currencies together: credits buy missiles, Parts fix hulls. RIGHT-ALIGNED to
    -- the edge rather than pinned at a fixed x, because the numbers grew: now that the
    -- shock laser costs 11000c this readout can be five digits wide, and from a fixed
    -- start it ran off the screen the moment you got rich. Measuring it each frame means
    -- it can never overflow again however big the pile gets.
    local purse = credits .. "c  " .. parts .. "p"
    screen.label(6, W - 6 - math.ceil(textW(purse)), H - 40, purse, 0xffd60a)

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
        screen.label(12, centreX(line, 0, W), 44, line, 0x9ad0ff)
    else
        screen.hide(12)
    end

    -- The docked indicator moved UP to the top bar, between the coordinates and the
    -- compass. It used to sit at y 152, which is now the middle of the shop; and the shop
    -- needs a "you are docked" signal on BOTH pages, not just the one where the
    -- harbourmaster is on screen saying hello. Top centre is empty on every screen.
    if docked then
        local cap = dockedOn == "wreck" and "DERELICT" or "DOCKED"
        screen.label(9, centreX(cap, 0, W), 22, cap, 0x30d158)
    else
        screen.hide(9)
    end

    -- His line of dialogue, beside his head, on the greeting page only: at the counter the
    -- four buttons need that space, and you've already been greeted. On the OUTFITTER page
    -- the same strip of screen earns its keep differently - it tells you what you're
    -- currently flying, which is the one fact you need while deciding whether a shelf is
    -- worth the money. One slot, two jobs, never both at once.
    if docked and dockedOn == "station" and dockMenu == "main" and nearest then
        local _, line = keeperOf(nearest.sx, nearest.sy)
        -- Two lines, wrapped to the gap between the alien's head and the right edge.
        -- Nine of the twelve greetings are too long for one line in the real font, which
        -- is why they used to disappear off the side of the screen mid-sentence.
        local a, b = wrap2(ALIEN_SAY[line], W - SAY_X - 6)
        screen.label(13, SAY_X, 60, a, 0x9ad0ff)
        if b then screen.label(14, SAY_X, 80, b, 0x9ad0ff) else screen.hide(14) end
    elseif docked and dockedOn == "station" and dockMenu == "upgrades" then
        screen.hide(14)
        screen.label(13, SHOP_X, 38, "NOW " .. LASER[ship.laser].name .. " (" .. ship.laser
                     .. ")  SH" .. ship.shieldMk .. "  HULL" .. ship.hullMk, 0x8e8e93)
    else
        screen.hide(13)
        screen.hide(14)
    end

    -- Button captions ride on top of the boxes drawn on the canvas, and every reserved
    -- slot gets hidden when there's nothing to offer - otherwise a caption from the last
    -- station you visited would still be sitting there in open space.
    local btns = dockButtons()
    for i, slot in ipairs(BTN_SLOT) do
        local b = btns[i]
        if b then
            -- Centred vertically from the button's own height, since the exchange page
            -- uses shorter rows than the greeting does.
            screen.label(slot, centreX(b.text, b.x, b.w),
                         b.y + math.floor((b.h - 12) / 2), b.text,
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
