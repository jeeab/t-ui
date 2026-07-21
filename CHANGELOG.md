# T-UI changelog

Every release, newest first. Written for people using the device, not developers.

Install the latest from **<https://jeeab.github.io/t-ui/>**.


## Apps reopen reliably, and a lock on/off switch

**2026.07.20.1** · 2026-07-20

- Fixes apps that wouldn't reopen until you rebooted. After playing a big app like Deep Space for a while, closing it, and tapping its icon again, nothing would happen until a restart. Every app used to ask for one 96 KB run of memory in a single piece each time it opened; once memory got broken up into scattered gaps there was no run that big, so the app quietly failed with nothing on screen (a reboot cleared the gaps, which is why a restart fixed it). Apps now claim their memory once and keep it, and only ask for exactly the size they need - so reopening works every time.
- New setting: you can turn the lock screen off completely. Go to Settings and scroll to 'Lock screen'. With it off, the device boots straight to Home and never asks for a PIN. The screen still dims on its own to save battery - only the PIN pad goes away. It's on by default, so nothing changes unless you switch it off.
- If an app ever fails to open, it now says why in the device log instead of showing a blank screen.
- App tiles can show a proper title. Deep Space's tile said 'Stars' because that's its folder name on the card; installing or updating an app from Get Apps now saves its real name for the tile.
- Apps can now be up to 192 KB, doubled from 96 KB - so bigger games like Deep Space have room to keep growing. Now that an app only reserves the memory it actually uses, raising the ceiling is free until something really is that big.
- Deep Space: the station menus are solid now instead of see-through, so the choices are easier to read.
- Deep Space v16: text no longer runs off the edge of the screen. The game was measuring every letter as the same width when the screen's font is actually proportional - a capital W is nearly three times the width of an i - so nine of the twelve things the station keepers say ran off the right-hand side mid-sentence, and the buying menus sat too far right and crowded their own buttons. Everything is measured properly now, and the keeper's greeting wraps onto two lines.
- Deep Space v16: red space is genuinely dangerous. Lawless sectors were allowed several pirates but only rolled for a new one every eight seconds or so, which meant a rough neighbourhood took the best part of a minute to fill up - and you had usually flown out the other side by then. Sectors now fill up in a few seconds, so a red patch on the map is busy the moment you arrive.
- Deep Space v16: cruising speed halved. Flat out used to cross a whole sector in under two seconds, which is why space felt empty - the galaxy went past faster than anything could happen in it. The map is effectively twice the size now, and the stars still streak past at the old rate so it doesn't feel sluggish.
- Deep Space v16: money comes from fighting now, not from salvage. Stripping a derelict paid better than killing anything, which made the safest job in the galaxy also the best paid - it was possible to get rich without ever being in danger. Wrecks now pay in Parts for repairing your hull, bounties pay real money, and a marauder is worth serious credits. Upgrade prices have gone up to match, so the best guns are a long haul rather than an afternoon.


## Bigger apps, and installs that don't fail

**2026.07.19.15** · 2026-07-19

- Installing an app from Get Apps no longer fails on larger apps. It used to load the whole file into memory in one piece before saving it, and once an app got past about 46 KB there often wasn't a single free block that big - so the download just said it failed. It now writes straight to the SD card as it arrives.
- Apps can be up to 96 KB, doubled from 48 KB.
- The map credit line at the bottom of the Maps screen is now white instead of grey, so it's readable over any map.


## The screen stays on while you play

**2026.07.19.14** · 2026-07-19

- Playing a game with the keyboard no longer lets the screen dim and go to sleep underneath you. The device was counting only taps as 'someone's using this', so a game you played entirely on the keys looked idle even while you were mid-game.


## Map credits

**2026.07.19.13** · 2026-07-19

- The Maps screen now credits where the map data came from. TopPlusOpen is open data from Germany's mapping agency and its licence requires the credit to be shown wherever the maps are, so it belongs on the device and not just on this page.


## Get Apps tells you about updates

**2026.07.19.12** · 2026-07-19

- Get Apps now shows an orange Update button when an app you've installed has a newer version, and says how many updates are waiting when you open it.
- It checks every time you open the screen, so you don't have to go looking.


## Room for bigger games

**2026.07.19.11** · 2026-07-19

- Apps can now be up to 48 KB instead of 16 KB, so a full game fits.
- Deep Space: the starfield is now a galaxy you can explore - a compass heading, coordinates, generated stations you can fly back to, pirates to fight or outrun, health, credits and a saved game.


## Keyboard, sprites, smoother maps

**2026.07.19.10** · 2026-07-19

- Apps can use the physical keyboard, and can draw proper artwork instead of just shapes. New app: Starfield - fly your ship through 220 stars.
- The map now follows your finger when you drag it, instead of jumping a third of a screen per swipe.
- Pins work differently: open Pins, tap Add pin, then tap the map where you want it. Holding the map no longer does anything - it was too easy to trigger by accident while panning.
- Turning Wi-Fi on or off now tells you the device is about to restart, instead of looking like a crash.
- You can remove apps from the device in Get Apps - no more taking the SD card to a computer.
- New: add a Meshtastic channel from a link saved in channel.txt on the SD card (Settings - Add channel).


## Remove apps from the device

**2026.07.19.3** · 2026-07-19

- Apps you've installed now have a Remove button in Get Apps - no more taking the SD card out to a computer to delete one. It asks before removing, because it deletes saved high scores and settings too.


## Real graphics for games

**2026.07.19.2** · 2026-07-19

- Apps can now draw pixels directly instead of arranging a limited number of shapes, which makes proper games possible.
- New app: Starfield - fly through 220 stars, drag to steer, tap WARP for speed.
- The app-maker's guide now explains how to use it.


## A clock, and tidier apps

**2026.07.19.1** · 2026-07-19

- The time now shows at the top of the home screen, taken from the GPS satellites.
- New Time zone setting - pick yours in Settings or the clock will read UTC.
- Get Apps has All / Games / Tools tabs.
- The five new tools have proper icons instead of a generic tile.


## Five new tools

**2026.07.19** · 2026-07-19

- Score Keeper - keep score for 2 to 4 players, saved as you go.
- Tally - four counters that remember their totals.
- Convert - miles, temperature, weight and volume, with a keypad.
- Intervals - repeating work/rest timer with beeps.
- Breathe - box breathing, follow the square.


## GPS fixed

**2026.07.18.6** · 2026-07-18

- The GPS could sit for half an hour without finding satellites, and turning it off and on again in Settings was the only cure. It now keeps itself searching, including after the device sleeps.
- Get Apps no longer leaves Wi-Fi switched on (and the battery draining) if you left the screen with the trackball instead of the Back button.


## Get Apps, and map fixes

**2026.07.18.3** · 2026-07-18

- New Get Apps tile - browse add-on apps and install them straight to the device over Wi-Fi. No computer, no card reader, and they appear on the home screen immediately.
- Map downloads can now go to detail level 18 (the default stays at 15 - each level is roughly four times the tiles).
- Your chosen map style now survives a reboot properly.
- The map download screen tells you to stay on the screen while it runs. Letting the device sleep is fine.


## Version number

**2026.07.18.1** · 2026-07-18

- The version now shows at the bottom of Settings, so you can tell what you're running.


## Maps stopped being laggy

**2026.07.16.7** · 2026-07-17

- Panning the map could freeze for seconds at a time while it fetched missing tiles from the internet. It never fetches while your finger is on the screen now, and gave up waiting on slow servers.
- Zooming back out is instant - twice as many decoded tiles are kept ready.


## Choose your map source

**2026.07.16.6** · 2026-07-17

- Pick between USGS Topo (US) and TopPlusOpen (Europe).
- Zoom level badge on the map, and a proper gear icon.
- Fixed: asking for detail 1-15 actually downloaded levels 10-24.


## Crash fixed

**2026.07.16.4** · 2026-07-17

- Fixed a boot crash-loop introduced by the previous build.
- The GPS switch in Settings now genuinely turns the GPS on and off, and remembers it.
- Both pinball flippers can be held at once.


## Download maps on the device

**2026.07.16.3** · 2026-07-16

- Maps gets a gear menu: switch map styles, and download a region of USGS Topo over Wi-Fi right on the device.
- Frame the area, pick the detail, see the size estimate before you start. It resumes where it stopped, and the screen can sleep while it works.
