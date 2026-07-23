-- GPS Test  —  a plain readout of the device.gps() door.
-- Black screen, green text. Purely for checking the GPS works; not a real app.

local GREEN = 0x33ff66
local AMBER = 0xffb020
local DIM   = 0x2c7a4a
local RED   = 0xff5555

-- device.gps() only exists once the firmware with the GPS door is flashed. Guard for it so
-- this app shows a clear message instead of erroring on older firmware.
local function hasGps() return type(device.gps) == "function" end

function on_open()
  screen.label(1, 98, 16, "= GPS TEST =", GREEN)
  screen.label(2, 46, 42, "for testing purposes only", AMBER)

  if not hasGps() then
    screen.label(3, 20, 96,  "device.gps() isn't in this", RED)
    screen.label(4, 20, 124, "firmware yet - flash the", RED)
    screen.label(5, 20, 152, "update, then reopen this.", RED)
    return
  end

  screen.label(3, 20, 92,  "Status:      ---", GREEN)
  screen.label(4, 20, 124, "Satellites:  ---", GREEN)
  screen.label(5, 20, 156, "Latitude:    ---", GREEN)
  screen.label(6, 20, 188, "Longitude:   ---", GREEN)
end

local last = -99999
function on_tick()
  if not hasGps() then return end
  local now = device.time()
  if now - last < 1000 then return end -- refresh once a second
  last = now

  local lat, lon, sats = device.gps()
  sats = sats or 0

  if lat then
    screen.label(3, 20, 92,  "Status:      CONNECTED", GREEN)
    screen.label(4, 20, 124, "Satellites:  " .. sats, GREEN)
    screen.label(5, 20, 156, string.format("Latitude:    %.6f", lat), GREEN)
    screen.label(6, 20, 188, string.format("Longitude:   %.6f", lon), GREEN)
  else
    -- No fix yet, but the satellite count still climbs as the receiver finds them.
    screen.label(3, 20, 92,  "Status:      searching...", AMBER)
    screen.label(4, 20, 124, "Satellites:  " .. sats, GREEN)
    screen.label(5, 20, 156, "Latitude:    ---", DIM)
    screen.label(6, 20, 188, "Longitude:   ---", DIM)
  end
end
