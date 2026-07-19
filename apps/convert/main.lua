-- Unit Converter for T-UI ------------------------------------------------------
-- Type a number on the keypad and read the answer. Tap the units at the top to
-- change what you're converting, and tap the arrow to swap the direction.
--
-- Covers the four you actually reach for: distance, temperature, weight, volume.
-- Apps can't use the physical keyboard yet, hence the on-screen keypad.
----------------------------------------------------------------------------------
local UNITS = {
    {a = "mi",  b = "km", to = function(v) return v * 1.609344 end,      back = function(v) return v / 1.609344 end},
    {a = "F",   b = "C",  to = function(v) return (v - 32) * 5 / 9 end,  back = function(v) return v * 9 / 5 + 32 end},
    {a = "lb",  b = "kg", to = function(v) return v * 0.45359237 end,    back = function(v) return v / 0.45359237 end},
    {a = "gal", b = "L",  to = function(v) return v * 3.785411784 end,   back = function(v) return v / 3.785411784 end},
    {a = "ft",  b = "m",  to = function(v) return v * 0.3048 end,        back = function(v) return v / 0.3048 end},
    {a = "in",  b = "cm", to = function(v) return v * 2.54 end,          back = function(v) return v / 2.54 end},
}

local unit = 1
local flipped = false      -- false: a -> b, true: b -> a
local entry = ""

local KEYS = {"7", "8", "9", "4", "5", "6", "1", "2", "3", ".", "0", "C"}

local function save() store.write("convert.txt", unit .. "," .. (flipped and 1 or 0)) end

local function restore()
    local s = store.read("convert.txt")
    if not s then return end
    local v = {}
    for x in s:gmatch("%d+") do v[#v + 1] = tonumber(x) end
    if v[1] and v[1] >= 1 and v[1] <= #UNITS then unit = v[1] end
    flipped = (v[2] == 1)
end

local function fromUnit() return flipped and UNITS[unit].b or UNITS[unit].a end
local function toUnit()   return flipped and UNITS[unit].a or UNITS[unit].b end

-- Trim to something readable: 2 decimals, no trailing zeros, no "-0". Big numbers drop
-- the decimals entirely — two decimal places on a million-something is noise, and a long
-- string would run off the edge of the readout panel.
local function fmt(x)
    if x ~= x then return "-" end                       -- not a number
    local s = string.format((x >= 100000 or x <= -100000) and "%.0f" or "%.2f", x)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end

local function result()
    local v = tonumber(entry)
    if not v then return "" end
    local u = UNITS[unit]
    return fmt(flipped and u.back(v) or u.to(v))
end

-- keypad geometry
local KX, KY, KW, KH, KGAP = 8, 64, 48, 38, 4
local function keyRect(i)
    local col = (i - 1) % 3
    local row = math.floor((i - 1) / 3)
    return KX + col * (KW + KGAP), KY + row * (KH + KGAP), KW, KH
end

local function draw()
    screen.label(1, 8, 6, fromUnit() .. "  >  " .. toUnit(), 0x30d158)
    screen.label(2, 150, 6, "swap", 0x0a84ff)
    screen.label(3, 240, 6, "units >", 0x8e8e93)

    -- keypad
    for i = 1, 12 do
        local x, y, w, h = keyRect(i)
        local b = 10 + i * 2
        local isClear = KEYS[i] == "C"
        screen.box(b, x, y, w, h, isClear and 0x3a2c2e or 0x2c2c2e)
        screen.label(b + 1, x + math.floor(w / 2) - 4, y + 11, KEYS[i], isClear and 0xff453a or 0xffffff)
    end

    -- readout panel
    screen.box(4, 168, 64, 144, 80, 0x1c1c20)
    local shown = entry == "" and "0" or entry
    screen.label(5, 176, 74, shown, 0xffffff)
    screen.label(6, 176, 92, fromUnit(), 0x8e8e93)
    local r = result()
    screen.label(7, 176, 112, r == "" and "-" or r, 0x30d158)
    screen.label(8, 176, 130, toUnit(), 0x8e8e93)
end

function on_open()
    restore()
    draw()
end

function on_touch(x, y)
    -- header: swap direction, or move to the next unit pair
    if y < 24 then
        if x >= 140 and x < 210 then
            flipped = not flipped
        elseif x >= 230 then
            unit = unit + 1
            if unit > #UNITS then unit = 1 end
            flipped = false
        else
            return
        end
        device.beep()
        save()
        draw()
        return
    end

    -- keypad
    for i = 1, 12 do
        local kx, ky, kw, kh = keyRect(i)
        if x >= kx and x < kx + kw and y >= ky and y < ky + kh then
            local k = KEYS[i]
            if k == "C" then
                entry = ""
            elseif k == "." then
                if not entry:find("%.") and #entry < 9 then
                    entry = (entry == "" and "0" or entry) .. "."
                end
            else
                if #entry < 9 then entry = entry .. k end
            end
            device.beep()
            draw()
            return
        end
    end
end
