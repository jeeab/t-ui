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
-- Bringing Wi-Fi up drops the Bluetooth connection to the phone app until the next reboot.

local BLUE  = 0x5ac8fa
local WHITE = 0xffffff
local GREEN = 0x33ff66
local AMBER = 0xffb020
local DIM   = 0x8e8e93
local BTN   = 0x1c3a4a

local CACHE = "forecast.txt"
local CACHE_VER = "2" -- bump this if the saved layout below ever changes

local state = "idle" -- idle / locating / fetching / ok / error / nowifi / oldfw
local temp, wind, desc = nil, nil, nil
local days = {}       -- up to 7 of { date=, code=, hi=, lo= }
local fromCache = false
local lat0, lon0 = nil, nil

-- The Wi-Fi door (net.*) only exists on the latest firmware. Guard for it so this app shows a
-- clear message instead of erroring on an older build.
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
  if c == 0 then return "Clear", GREEN end
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

-- "Aug 5" from "2026-08-05", for the "saved" note.
local MONNAME = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local function shortDate(iso)
  local _, m, d = iso:match("(%d+)%-(%d+)%-(%d+)")
  m, d = tonumber(m), tonumber(d)
  if not m or not MONNAME[m] then return iso end
  return MONNAME[m] .. " " .. d
end

local function round(x)
  x = tonumber(x)
  if not x then return nil end
  return math.floor(x + 0.5)
end

-- Pull one JSON array out of the body: "key":[a,b,c] -> { "a", "b", "c" }. Requires the "[",
-- which is what keeps it from matching the single values in the "current" and "units" blocks.
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
  local out = { CACHE_VER, (temp or "") .. "|" .. (desc or "") .. "|" .. (wind or "") }
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
  local t, ds, w = lines[2]:match("([^|]*)|([^|]*)|([^|]*)")
  if not t or t == "" then return false end
  temp, desc, wind = t, ds, (w ~= "" and w or nil)
  days = {}
  for i = 3, #lines do
    local date, code, hi, lo = lines[i]:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)")
    if date then days[#days + 1] = { date = date, code = code, hi = hi, lo = lo } end
  end
  return true
end

-- ---------------------------------------------------------------- drawing

-- Ids: 1 title, 2-3 refresh button, 4 now-line, 5 note, 6 rule, 10.. forecast rows (3 each).
local ROW_Y = { 80, 102, 124, 146, 168, 190, 212 }

local function clearRows()
  for i = 1, 7 do
    screen.hide(10 + (i - 1) * 3)
    screen.hide(11 + (i - 1) * 3)
    screen.hide(12 + (i - 1) * 3)
  end
end

local function drawRows()
  for i = 1, 7 do
    local d = days[i]
    local base = 10 + (i - 1) * 3
    if d then
      local short, col = codeShort(d.code)
      screen.label(base, 12, ROW_Y[i], dayName(d.date), (i == 1) and WHITE or DIM)
      screen.label(base + 1, 70, ROW_Y[i], d.hi .. "/" .. d.lo, WHITE)
      screen.label(base + 2, 150, ROW_Y[i], short, col)
    else
      screen.hide(base); screen.hide(base + 1); screen.hide(base + 2)
    end
  end
end

local function draw()
  screen.label(1, 12, 6, "WEATHER", BLUE)
  -- The Refresh button. It is always there, so there is always a way to try again.
  screen.box(2, 226, 2, 90, 26, BTN)
  screen.label(3, 240, 7, "Refresh", WHITE)

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
    now = (temp or "--") .. "F  " .. (desc or "")
    nowCol = WHITE
    if wind then note = "Wind " .. wind .. " mph" else note = "" end
    if fromCache and days[1] then
      note = note .. ((note ~= "") and "   " or "") .. "Saved " .. shortDate(days[1].date)
    end
  else
    now, nowCol = "Tap Refresh for the weather", GREEN
  end

  screen.label(4, 12, 32, now, nowCol)
  screen.label(5, 12, 54, note, DIM)
  screen.line(6, 12, 74, 308, 74, 2, 0x333333)
  drawRows()
end

-- ---------------------------------------------------------------- fetching

-- Ask Open-Meteo for current conditions AND the 7-day forecast in one request.
-- NOTE: keep this URL under 255 characters — the firmware's fetch buffer is 256 bytes and
-- truncates silently past that. "forecast_days=7" is deliberately left off: 7 days is the
-- default, and adding it pushes the URL to 263 characters at worst-case coordinates.
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
    fetchWeather(lat, lon) -- have a GPS fix: use it, it's the most precise
  elseif lat0 then
    fetchWeather(lat0, lon0) -- already know roughly where we are; skip the lookup
  else
    -- No GPS fix: get a rough location from the Wi-Fi connection (IP address). Plain-text
    -- "lat,lon" back. This is a first fetch; the weather is a second one once we have it.
    if not net.fetch("https://ipapi.co/latlong/") then
      state = "nowifi"; draw(); return
    end
    state = "locating"; draw()
  end
end

-- Read the weather out of the reply. Returns true if we got at least a temperature.
local function parseWeather(body)
  temp = body:match('"temperature_2m":([%-%d%.]+)')
  local code = body:match('"weather_code":(%d+)')
  wind = body:match('"wind_speed_10m":([%d%.]+)')
  desc = codeDesc(code)
  if not temp then return false end
  temp = tostring(round(temp))
  if wind then wind = tostring(round(wind)) end

  local dates = jsonArray(body, "time")
  local codes = jsonArray(body, "weather_code")
  local his   = jsonArray(body, "temperature_2m_max")
  local los   = jsonArray(body, "temperature_2m_min")
  days = {}
  if dates and codes and his and los then
    for i = 1, math.min(7, #dates, #codes, #his, #los) do
      days[#days + 1] = {
        date = dates[i],
        code = codes[i],
        hi = tostring(round(his[i]) or "-"),
        lo = tostring(round(los[i]) or "-"),
      }
    end
  end
  return true
end

-- ---------------------------------------------------------------- lifecycle

function on_open()
  -- Show the saved forecast immediately: no waiting, no Wi-Fi, no Bluetooth drop. Only a tap
  -- on Refresh goes and gets new weather.
  if loadCache() then
    fromCache = true
    state = "ok"
    draw()
  else
    draw()
    refresh() -- nothing saved yet, so fetch once to get started
  end
end

function on_touch(x, y)
  if state == "locating" or state == "fetching" then return end
  -- Only the Refresh button refreshes. A stray tap anywhere else does nothing, so the app
  -- can't quietly turn Wi-Fi on behind your back.
  if x and x >= 220 and y and y <= 34 then
    refresh()
  end
end

function on_tick()
  if state == "locating" then
    local s = net.status()
    if s == "done" then
      local body = net.body() -- reading clears the result, freeing the door for the weather fetch
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
        saveCache() -- so the next open is instant, and survives a reboot
      else
        state = "error"
      end
      draw()
    elseif s == "error" then
      net.reset(); state = "error"; draw()
    end
  end
end
