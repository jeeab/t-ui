-- Weather — current conditions plus a 7-day forecast, from Open-Meteo (free, no account,
-- no API key).
--
-- Location: uses the GPS if you already have a fix (most precise), otherwise looks up your
-- rough location from your Wi-Fi connection (your city/area) — so you never have to wait for
-- satellites. Set up Wi-Fi in Settings first.
--
-- The forecast is SAVED on the card. Opening the app shows the saved one straight away, with
-- no waiting and no Wi-Fi. It only goes and gets fresh weather when you tap Refresh.
--
-- Temperatures are always FETCHED and SAVED in Fahrenheit and converted when drawn, so the
-- C/F button switches instantly, works on the saved forecast, and never needs the internet.
--
-- Bringing Wi-Fi up drops the Bluetooth connection to the phone app until the next reboot.

local BLUE  = 0x5ac8fa
local WHITE = 0xffffff
local GREEN = 0x33ff66
local AMBER = 0xffb020
local DIM   = 0x8e8e93
local BTN   = 0x1c3a4a
local SUN   = 0xffd60a
local CLOUD = 0xd8d8dd
local GREY  = 0x6e6e73

local CACHE = "forecast.txt"
local CACHE_VER = "3" -- bumped: temperatures are now stored raw, not pre-rounded
local UNITS_FILE = "units.txt"

local state = "idle" -- idle / locating / fetching / ok / error / nowifi / oldfw
local temp, wind, desc = nil, nil, nil -- temp/wind kept as raw numbers (F, mph)
local code = nil
local days = {}       -- up to 7 of { date=, code=, hi=, lo= }  (hi/lo raw numbers, F)
local fromCache = false
local lat0, lon0 = nil, nil
local useC = false

local function hasNet() return type(net) == "table" and type(net.fetch) == "function" end

-- WMO weather codes -> a short plain description.
local function codeDesc(c)
  c = tonumber(c) or -1
  if c == 0 then return "Clear sky" end
  if c <= 3 then return "Partly cloudy" end
  if c == 45 or c == 48 then return "Fog" end
  if c >= 51 and c <= 57 then return "Drizzle" end
  if c >= 61 and c <= 67 then return "Rain" end
  if c >= 71 and c <= 77 then return "Snow" end
  if c >= 80 and c <= 82 then return "Rain showers" end
  if c >= 85 and c <= 86 then return "Snow showers" end
  if c >= 95 then return "Thunderstorm" end
  return "Code " .. c
end

-- Shorter still, for the forecast rows where there's less room.
local function codeShort(c)
  c = tonumber(c) or -1
  if c == 0 then return "Clear", SUN end
  if c <= 3 then return "Cloudy", WHITE end
  if c == 45 or c == 48 then return "Fog", DIM end
  if c >= 51 and c <= 57 then return "Drizzle", BLUE end
  if c >= 61 and c <= 67 then return "Rain", BLUE end
  if c >= 71 and c <= 77 then return "Snow", WHITE end
  if c >= 80 and c <= 82 then return "Showers", BLUE end
  if c >= 85 and c <= 86 then return "Snow shwr", WHITE end
  if c >= 95 then return "Storm", AMBER end
  return "-", DIM
end

-- Which day of the week is a date? There's no os library here, so work it out with Sakamoto's
-- method. Takes "2026-08-05" and gives "Wed". Checked against a known date (2000-01-01 = Sat).
local DAYNAME = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MONTHOFF = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
local function dayName(iso)
  local y, m, d = iso:match("(%d+)%-(%d+)%-(%d+)")
  if not y then return "?" end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m < 3 then y = y - 1 end
  local w = (y + y // 4 - y // 100 + y // 400 + MONTHOFF[m] + d) % 7
  return DAYNAME[w + 1]
end

local MONNAME = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local function shortDate(iso)
  local _, m, d = iso:match("(%d+)%-(%d+)%-(%d+)")
  m, d = tonumber(m), tonumber(d)
  if not m or not MONNAME[m] then return iso end
  return MONNAME[m] .. " " .. d
end

-- Everything is stored in Fahrenheit; this is the only place units are decided.
local function degrees(f)
  f = tonumber(f)
  if not f then return "--" end
  if useC then f = (f - 32) * 5 / 9 end
  return tostring(math.floor(f + 0.5))
end

local function jsonArray(body, key)
  local inner = body:match('"' .. key .. '":%[(.-)%]')
  if not inner then return nil end
  local t = {}
  for item in inner:gmatch("[^,]+") do
    t[#t + 1] = (item:gsub('"', ""))
  end
  return t
end

-- ---------------------------------------------------------------- saving

local function saveCache()
  local out = { CACHE_VER, (temp or "") .. "|" .. (code or "") .. "|" .. (wind or "") }
  for i = 1, #days do
    local d = days[i]
    out[#out + 1] = d.date .. "|" .. d.code .. "|" .. d.hi .. "|" .. d.lo
  end
  store.write(CACHE, table.concat(out, "\n"))
end

local function loadCache()
  local raw = store.read(CACHE)
  if not raw then return false end
  local lines = {}
  for line in raw:gmatch("[^\n]+") do lines[#lines + 1] = line end
  if #lines < 2 or lines[1] ~= CACHE_VER then return false end
  local t, c, w = lines[2]:match("([^|]*)|([^|]*)|([^|]*)")
  if not t or t == "" then return false end
  temp, code, wind = t, c, (w ~= "" and w or nil)
  desc = codeDesc(code)
  days = {}
  for i = 3, #lines do
    local date, cd, hi, lo = lines[i]:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)")
    if date then days[#days + 1] = { date = date, code = cd, hi = hi, lo = lo } end
  end
  return true
end

-- ---------------------------------------------------------------- drawing

-- Ids: 1 title, 2-3 Refresh, 4 now-line, 5 note, 6 rule, 7-8 units button,
-- then 5 per forecast row from 10: text, description, and 3 for the little picture.
local ROW_Y = { 74, 96, 118, 140, 162, 184, 206 }
local ICON_X = 108
local DESC_X = 132

-- Small weather pictures, drawn from blocks and lines because apps can't load images onto the
-- screen. Deliberately capped at THREE elements each: at 7 rows that is 21 of the 64 elements
-- an app is allowed, and the rest of the screen needs the remainder. Any ids not used by a
-- given picture are hidden, so a sunny day doesn't leave yesterday's raindrops behind.
local function drawIcon(base, y, c)
  c = tonumber(c) or -1
  local used = 0
  local function box(x, yy, w, h, col)
    screen.box(base + used, x, yy, w, h, col); used = used + 1
  end
  local function line(x1, y1, x2, y2, th, col)
    screen.line(base + used, x1, y1, x2, y2, th, col); used = used + 1
  end

  if c == 0 then                              -- clear: a sun
    box(ICON_X + 2, y + 3, 13, 13, SUN)
  elseif c <= 3 then                          -- partly cloudy: sun peeking behind cloud
    box(ICON_X, y + 2, 9, 9, SUN)
    box(ICON_X + 5, y + 8, 14, 8, CLOUD)
  elseif c == 45 or c == 48 then              -- fog: stacked bars
    line(ICON_X, y + 5, ICON_X + 17, y + 5, 2, GREY)
    line(ICON_X, y + 9, ICON_X + 17, y + 9, 2, GREY)
    line(ICON_X, y + 13, ICON_X + 17, y + 13, 2, GREY)
  elseif c >= 95 then                         -- storm: cloud + bolt
    box(ICON_X, y + 3, 17, 8, GREY)
    line(ICON_X + 9, y + 11, ICON_X + 5, y + 18, 2, SUN)
  elseif (c >= 71 and c <= 77) or (c >= 85 and c <= 86) then -- snow: cloud + flakes
    box(ICON_X, y + 3, 17, 8, CLOUD)
    line(ICON_X + 4, y + 13, ICON_X + 6, y + 15, 2, WHITE)
    line(ICON_X + 11, y + 13, ICON_X + 13, y + 15, 2, WHITE)
  else                                        -- drizzle / rain / showers: cloud + drops
    box(ICON_X, y + 3, 17, 8, CLOUD)
    line(ICON_X + 4, y + 12, ICON_X + 3, y + 17, 2, BLUE)
    line(ICON_X + 12, y + 12, ICON_X + 11, y + 17, 2, BLUE)
  end

  for k = used, 2 do screen.hide(base + k) end -- clear whatever this picture didn't need
end

local function drawRows()
  for i = 1, 7 do
    local d = days[i]
    local base = 10 + (i - 1) * 5
    if d then
      local short, col = codeShort(d.code)
      -- Day and temperatures in ONE label: day names are always 3 characters, so the columns
      -- still line up, and it frees an element per row for the picture.
      screen.label(base, 12, ROW_Y[i], dayName(d.date) .. "  " .. degrees(d.hi) .. "/" .. degrees(d.lo),
        (i == 1) and WHITE or DIM)
      screen.label(base + 1, DESC_X, ROW_Y[i], short, col)
      drawIcon(base + 2, ROW_Y[i], d.code)
    else
      for k = 0, 4 do screen.hide(base + k) end
    end
  end
end

local function draw()
  screen.label(1, 12, 4, "WEATHER", BLUE)
  screen.box(2, 226, 0, 90, 24, BTN)
  screen.label(3, 240, 4, "Refresh", WHITE)
  -- Units button, bottom right. Sits to the right of the last row's short description, so it
  -- shares that line without colliding with it.
  screen.box(7, 252, 214, 64, 24, BTN)
  screen.label(8, 268, 218, useC and "C" or "F", WHITE)

  local now, note, nowCol = "", "", WHITE

  if state == "oldfw" then
    now, nowCol = "Needs the latest update", AMBER
    note = "Reflash from the installer."
  elseif state == "nowifi" then
    now, nowCol = "Set up Wi-Fi in Settings", AMBER
    note = "Then tap Refresh."
  elseif state == "locating" then
    now, nowCol = "Finding your location...", AMBER
    note = "(from Wi-Fi - no GPS needed)"
  elseif state == "fetching" then
    now, nowCol = "Getting the forecast...", AMBER
    note = "Wi-Fi is on for a moment."
  elseif state == "error" then
    now, nowCol = "Couldn't get the weather", AMBER
    note = (#days > 0) and "Showing the last saved one." or "Check Wi-Fi, then tap Refresh."
  elseif state == "ok" then
    now = degrees(temp) .. (useC and "C  " or "F  ") .. (desc or "")
    nowCol = WHITE
    if wind then note = "Wind " .. tostring(math.floor(tonumber(wind) + 0.5)) .. " mph" else note = "" end
    if fromCache and days[1] then
      note = note .. ((note ~= "") and "   " or "") .. "Saved " .. shortDate(days[1].date)
    end
  else
    now, nowCol = "Tap Refresh for the weather", GREEN
  end

  screen.label(4, 12, 26, now, nowCol)
  screen.label(5, 12, 48, note, DIM)
  screen.line(6, 12, 68, 308, 68, 2, 0x333333)
  drawRows()
end

-- ---------------------------------------------------------------- fetching

-- NOTE: keep this URL under 255 characters — the firmware's fetch buffer is 256 bytes and
-- truncates silently past that. "forecast_days=7" is deliberately left off: 7 days is the
-- default, and adding it pushes the URL to 263 characters at worst-case coordinates.
-- Always fahrenheit: the C/F button converts on the way to the screen.
local function fetchWeather(lat, lon)
  lat0, lon0 = lat, lon
  local url = string.format(
    "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f" ..
    "&current=temperature_2m,weather_code,wind_speed_10m" ..
    "&daily=weather_code,temperature_2m_max,temperature_2m_min" ..
    "&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto",
    lat, lon)
  if not net.fetch(url) then
    state = "nowifi"; draw(); return
  end
  state = "fetching"; draw()
end

local function refresh()
  if state == "locating" or state == "fetching" then return end
  if not hasNet() then
    state = "oldfw"; draw(); return
  end
  fromCache = false
  local lat, lon = device.gps()
  if lat then
    fetchWeather(lat, lon)
  elseif lat0 then
    fetchWeather(lat0, lon0)
  else
    if not net.fetch("https://ipapi.co/latlong/") then
      state = "nowifi"; draw(); return
    end
    state = "locating"; draw()
  end
end

local function parseWeather(body)
  temp = body:match('"temperature_2m":([%-%d%.]+)')
  code = body:match('"weather_code":(%d+)')
  wind = body:match('"wind_speed_10m":([%d%.]+)')
  desc = codeDesc(code)
  if not temp then return false end

  local dates = jsonArray(body, "time")
  local codes = jsonArray(body, "weather_code")
  local his   = jsonArray(body, "temperature_2m_max")
  local los   = jsonArray(body, "temperature_2m_min")
  days = {}
  if dates and codes and his and los then
    for i = 1, math.min(7, #dates, #codes, #his, #los) do
      days[#days + 1] = { date = dates[i], code = codes[i], hi = his[i], lo = los[i] }
    end
  end
  return true
end

-- ---------------------------------------------------------------- lifecycle

function on_open()
  useC = (store.read(UNITS_FILE) == "C")
  if loadCache() then
    fromCache = true
    state = "ok"
    draw()
  else
    draw()
    refresh()
  end
end

function on_touch(x, y)
  if not x or not y then return end
  -- Units button, bottom right. Costs nothing and needs no internet: everything is stored in
  -- Fahrenheit and converted as it's drawn, so this works on the saved forecast too.
  if x >= 246 and y >= 208 then
    useC = not useC
    store.write(UNITS_FILE, useC and "C" or "F")
    draw()
    return
  end
  if state == "locating" or state == "fetching" then return end
  -- Only Refresh fetches. A stray tap anywhere else does nothing, so the app can't quietly
  -- turn Wi-Fi on behind your back.
  if x >= 220 and y <= 30 then
    refresh()
  end
end

function on_tick()
  if state == "locating" then
    local s = net.status()
    if s == "done" then
      local body = net.body()
      -- Do NOT write this as `local lat, lon = body and body:match(...)`. In Lua, `x and f()`
      -- yields exactly ONE value, so lon would always be nil and this path could never work.
      local lat, lon
      if body then lat, lon = body:match("([%-%d%.]+)%s*,%s*([%-%d%.]+)") end
      if lat and lon then
        fetchWeather(tonumber(lat), tonumber(lon))
      else
        state = "error"; draw()
      end
    elseif s == "error" then
      net.reset(); state = "error"; draw()
    end
  elseif state == "fetching" then
    local s = net.status()
    if s == "done" then
      local body = net.body()
      if body and parseWeather(body) then
        state = "ok"
        fromCache = false
        saveCache()
      else
        state = "error"
      end
      draw()
    elseif s == "error" then
      net.reset(); state = "error"; draw()
    end
  end
end
