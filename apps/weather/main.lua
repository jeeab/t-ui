-- Weather — current conditions from Open-Meteo (free, no account, no API key).
--
-- Location: uses the GPS if you already have a fix (most precise), otherwise looks up your
-- rough location from your Wi-Fi connection (your city/area) — so you never have to wait for
-- satellites. Set up Wi-Fi in Settings first. Tap the screen to refresh.
--
-- Bringing Wi-Fi up drops the Bluetooth connection to the phone app until the next reboot.

local BLUE  = 0x5ac8fa
local WHITE = 0xffffff
local GREEN = 0x33ff66
local AMBER = 0xffb020
local DIM   = 0x8e8e93

local state = "idle" -- idle / locating / fetching / ok / error / nowifi / oldfw
local temp, wind, desc = nil, nil, nil

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
  return "Weather code " .. c
end

-- Fixed line ids, always set (blank when unused) so nothing lingers between states.
local function show(main, mainCol, sub, subCol, foot)
  screen.label(1, 116, 16, "WEATHER", BLUE)
  screen.label(2, 20, 78,  main or "", mainCol or WHITE)
  screen.label(3, 20, 118, sub or "",  subCol or DIM)
  screen.label(4, 20, 150, (wind and state == "ok") and ("Wind: " .. wind .. " mph") or "", DIM)
  screen.label(5, 20, 210, foot or "", DIM)
end

local function draw()
  if state == "idle" then
    show("Tap to get the weather", GREEN, "", DIM, "")
  elseif state == "oldfw" then
    show("Needs the latest update", AMBER, "Reflash from the installer to get", DIM, "the Wi-Fi-for-apps feature.")
  elseif state == "nowifi" then
    show("Set up Wi-Fi in Settings", AMBER, "Then come back and tap to try.", DIM, "")
  elseif state == "locating" then
    show("Finding your location...", AMBER, "(from Wi-Fi - no GPS needed)", DIM, "")
  elseif state == "fetching" then
    show("Fetching...", AMBER, "Wi-Fi is on for a moment.", DIM, "")
  elseif state == "error" then
    show("Couldn't get the weather", AMBER, "Check Wi-Fi. Tap to retry.", DIM, "")
  elseif state == "ok" then
    show((temp or "--") .. " F", WHITE, desc or "", GREEN, "Tap to refresh")
  end
end

-- Ask Open-Meteo for the weather at a location.
local function fetchWeather(lat, lon)
  local url = string.format(
    "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f" ..
    "&current=temperature_2m,weather_code,wind_speed_10m" ..
    "&temperature_unit=fahrenheit&wind_speed_unit=mph",
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
  local lat, lon = device.gps()
  if lat then
    fetchWeather(lat, lon) -- have a GPS fix: use it, it's the most precise
  else
    -- No GPS fix: get a rough location from the Wi-Fi connection (IP address). Plain-text
    -- "lat,lon" back. This is a first fetch; the weather is a second one once we have it.
    if not net.fetch("https://ipapi.co/latlong/") then
      state = "nowifi"; draw(); return
    end
    state = "locating"; draw()
  end
end

function on_open()
  draw()
  refresh()
end

function on_touch()
  if state ~= "locating" and state ~= "fetching" then refresh() end
end

function on_tick()
  if state == "locating" then
    local s = net.status()
    if s == "done" then
      local body = net.body() -- reading clears the result, freeing the door for the weather fetch
      local lat, lon = body and body:match("([%-%d%.]+)%s*,%s*([%-%d%.]+)")
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
      if body then
        temp = body:match('"temperature_2m":([%-%d%.]+)')
        local code = body:match('"weather_code":(%d+)')
        wind = body:match('"wind_speed_10m":([%d%.]+)')
        desc = codeDesc(code)
        if temp then
          temp = tostring(math.floor(tonumber(temp) + 0.5))
          if wind then wind = tostring(math.floor(tonumber(wind) + 0.5)) end
          state = "ok"
        else
          state = "error"
        end
      else
        state = "error"
      end
      draw()
    elseif s == "error" then
      net.reset(); state = "error"; draw()
    end
  end
end
