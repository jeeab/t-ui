# T-UI changelog

Every release, newest first. Written for people using the device, not developers.

Install the latest from **<https://jeeab.github.io/t-ui/>**.


## A ruler on the map, and your height above sea level

**2026.09.30.4** · 2026-09-30

- A ruler on the map, left of the magnifying glass: tap it, tap one point, tap another, and it draws a line between them with the straight-line distance and direction - "0.93 mi NW from Home". Tap near a pin and it snaps to the pin, so pin to pin is two taps. The line moves with the map. Tap the ruler again to put it away.
- Your height above sea level, from the GPS, now shows in the bottom-left corner of the map whenever there is a solid fix (four satellites or more). GPS height can be out by 30 to 60 feet.
- Distances read more easily: feet only up to 1,000 ft, then miles with two decimals ("0.93 mi" rather than "4903 ft"). Same in kilometres if you use them.


## Pins shows all your pins again after a search

**2026.09.30.3** · 2026-09-30

- Fixes the Pins button showing only your last search's results. The magnifier and Pins share one search box, and Pins kept whatever you had searched for - search for a lake, and Pins showed only matches for that lake instead of your pins. Pins now always opens on all of them.


## Search for places on the map, offline - plus a real Maps settings menu

**2026.09.30.2** · 2026-09-30

- Maps can now find places with no signal: towns, cities, lakes, ponds, rivers, peaks, passes, springs, campgrounds and more, across the whole of the USA and Europe. Tap the new magnifying glass beside the cog and start typing. Go shows the place on the map with a yellow ring; Pin keeps it as a pin you can share. Local spellings work too: "Wien" finds Vienna, "München" finds Munich.
- Suggestions as you type: from the second letter, the biggest matching cities come up - type "san" and San Diego, San Jose and San Francisco appear - with everything nearby listed underneath. When something nearby is exactly what you typed, it goes on top instead.
- Getting the names onto the card: "Download this area" now brings the place names for the area along with the map. Already have your maps? Gear > Place names for search > Near the map, All of the USA, or All of Europe. The nearest areas come first, anything already on the card is skipped, and it can be stopped and carried on later. On a home connection the whole of the USA takes roughly half an hour. The website also has each region as one download to unzip onto the card.
- The cog on the map opens a proper settings menu: map style, download this area, place names, units (miles or kilometres - the same switch as the weather's F/C), where the map opens when there is no GPS fix (the last place you looked at, or home), set home to the spot on screen, nodes on the map, and the coverage recorder.
- Without a GPS fix the map used to put the blue "you are here" dot on your home spot, as if it knew where you were. It doesn't any more.
- Pin and node names on the map now show accented letters and emoji (they used a font with plain English letters only, so "Köln" came out as "Kln").
- Fixes the map freezing for many seconds at a time on Wi-Fi when you look at an area that isn't downloaded. It was fetching every missing square back to back, each with a brand-new secure connection, and gave up on any square that took more than a moment to start arriving - so it had to fetch it all over again. It now fetches one square at a time between screen refreshes, over one connection that it hangs up as soon as the squares stop coming. Map and place-name downloads use one connection too.


## A crash fix, smoother maps when zoomed past your downloaded detail, and Mail fixes

**2026.09.30.1** · 2026-09-30

- Fixes a crash that could happen when a new node was heard while Maps or Chess was using a lot of memory. Every time the device hears a new node it saves its node list, and part of that save needs one large block of memory; if Maps or Chess had just taken most of it, the save failed and took the device down with it. The save now waits for the next time instead, and Maps and Chess both leave room for everything else - Maps hands its memory back when you close it, and Chess picks a smaller thinking table when memory is short. Found by stress-testing the device over the USB cable.
- Maps are much smoother at the deepest zoom levels. When you zoom in further than the map you downloaded, each square is filled with an enlarged piece of the square above it - and before, every square on screen was redrawing that whole enlarged picture, stacked on top of each other, on every frame while you panned. Each square now cuts out just its own piece once. Measured at the same spot and zoom: frames came about 2.5 times faster. It also stops trying to download map squares from the internet at zoom levels the map service does not have - on wi-fi, every one of those attempts froze the screen for a moment.
- Fixes Chess (and Gemini) losing the bar across the top of the screen after being opened many times in one day, with everything on the screen shifting up.
- Mail: long subject lines that were written in another character set now show as words instead of "=?UTF-8?...".
- Mail: Reply now opens with the cursor at the top, ready to type, instead of scrolled down to the bottom of the quoted message.
- Mail: the "Who?" list leaves out noreply addresses, which nobody reads.


## Chess, Mail and Gemini, a lock screen that shows who messaged you, and far fewer crashes

**2026.09.29.1** · 2026-09-29

- Fixes the crashes that happened when moving from app to app. Opening Maps took a large slice of the device's small, fast memory for its markers and never gave it back, and every app opened after that took a little more, until the device ran out and restarted. Those now live in the large, plentiful memory instead. In testing, the fast memory now stays level through every app, Maps included, where before it ran down to almost nothing.
- Fixes new mesh messages not reaching the screen. A safety limit meant to protect memory was set above where the device normally sits, so a minute or so after starting up it stopped passing messages to the screen and Meshtastic threw them away. The limit now watches the memory those messages are actually kept in.
- Fixes restarts when the device fetches something over a weak wi-fi connection - the lock-screen weather, Get Apps, Gemini, Mail or a map download. A secure connection could wait up to two minutes for an answer, longer than the device's own safety timer allows. It now gives up after 15 seconds and tries again later.
- Starts up about 15 seconds faster. It no longer reads through the SD card's entire table of contents at startup just to show how full the card is - the screen, the card and the radio were all waiting while it did. The Meshtastic home screen now shows the card's size without the "used" figure.
- New: Chess. Play the device at six levels from Beginner to Max. It thinks on its own processor core, so the screen and radio carry on while it does, saves your game after every move, and gives its memory back when you close it. You are always White; if you leave or the device restarts while it is thinking, it picks up its move when you come back.
- New: Mail, for Gmail. Read your inbox, open messages, write, reply and forward. You sign in with a Google "app password" typed on the device - it is kept only on your SD card, never written to the log, and screenshots are refused while the sign-in form is on screen. The "Who?" button offers people you have written to and recent senders.
- New: Gemini. Ask Google's Gemini a question over wi-fi and read the answer. It needs your own free key; the ? button explains how to get one.
- New: Nodes, Favorites and Chats. A node list with a favourite star and a button on every row to message, show on the map, trace the route or ask for a position; a Favorites list; and one list of your conversations with the latest line of each.
- New lock screen: the time, date, weather and who has messaged you, with slide to unlock (or an Unlock button, or a double-click). Unlocking takes you back to the app you were in. Settings let you choose how often it asks for your PIN.
- Notifications: a pop-up and a sound when a message arrives, whatever you are doing, and a list of recent ones - tap the count at the top of the screen. Unread counts are kept per conversation.
- A bar across the top of most screens with the time, battery and notification count.
- Maps: zoom in past the detail you have downloaded (the nearest map square is enlarged), I and O zoom from the keyboard, and a coverage mapper can record where you heard the mesh and draw it as a heat map.
- The Stopwatch app becomes Clock, with a wake-up alarm.
- A trackball cursor: an on-screen arrow you can steer with the trackball, with speed settings.
- Emoji that people send you now appear instead of being invisible.
- Save a screenshot to the SD card, and send your location right away from Settings.
- Settings has headings and a Back button you can reach, and the weather can show F or C.
- The Weather app (update it from Get Apps) now says which place the forecast is for.


## Removes the power saving option

**2026.09.04.1** · 2026-09-04

- Removes the "Power saving" setting added in the previous release. It slowed the processor down while the screen was off and locked, and it could crash the device when you woke it up and typed your PIN. The cause was timing rather than speed - the processor speed was being changed a fraction of a second into drawing the PIN screen, while the display was still being written to. It was fixable, but the setting was saving very little in the first place: it stood aside whenever wi-fi or Bluetooth was in use, which on a device you actually carry is most of the time. Battery life is fine without it, so it has been taken out entirely rather than patched.
- If you had switched it on, there is nothing to do - the setting is simply gone and the device runs at its normal speed.


## Runs out of memory far less often, and tells you why things fail

**2026.09.03.1** · 2026-09-03

- Fixes the crashes that happened at seemingly random moments, most often when moving between the Maps app and the Meshtastic app. The device keeps its own record of how little memory it has had free, and reading that back showed it getting down to under a thousand bytes - effectively empty, at which point the next thing that needs memory fails and the device falls over. Two chunks of the scarce, fast memory were being held permanently for jobs that only last a few seconds (copying a file, and an app reading its saved data); both now borrow the slower, plentiful memory only while they are actually working.
- The map tile store was reserving almost all of the spare memory for itself - so much that there was often no room left to unpack the next tile it wanted to store. It now keeps a full screen of tiles plus a few, which leaves room for everything else and makes maps more reliable rather than less.
- Downloading maps now tells you WHY a tile failed instead of just counting failures. "427 failed" could equally mean the wi-fi dropped, the connection was refused, or the server said no, and there was no way to tell them apart. It also rebuilds its connection after several failures in a row - if the server closed the connection partway through, every remaining tile used to fail for the rest of the download.
- Satellite imagery is now one of the sources you can download from on the device itself, alongside the topographic map. The detail settings also stop at the level each map service actually has - asking for more used to start a download that quietly fetched nothing.
- The PIN screen now turns itself off after ten seconds untouched. Before, waking the device and walking away left the screen lit until the battery ran down.
- Fixes apps not appearing after you install them. The launcher only ever looked at the first twelve app folders on the card, and because folders come back in the order they were created, the app that disappeared was always the one you had just added. It now handles 26, and newly installed apps appear at the front where you can find them.
- Fixes the map style list offering "0", "1", "12" and so on as if they were map styles, where picking one left you with a blank map. Those are zoom-level folders, not styles - they show up when map tiles are copied straight into the maps folder rather than into a folder of their own.
- Adds a "Show password" tick box when typing a Wi-Fi password, which also lets a long password wrap onto more than one line so you can read the end of it.
- Adds optional power saving, switched off by default: it slows the processor down while the screen is off and locked, and stands aside entirely whenever wi-fi or Bluetooth is in use.
- Removes the trackball navigation switches added in the previous release. They could not be made to work without destabilising the device, and a switch that does nothing is worse than no switch. Holding the trackball to go Home, and double-clicking to go Home, both still work as before.


## Backspace erases again when you are typing a Wi-Fi password

**2026.08.30.1** · 2026-08-30

- Fixes backspace in the boxes that pop up over the screen when you type something in. The worst one: entering a Wi-Fi password. The erase key doubles as a Back button on this device, and it was supposed to stop doing that while you are typing - but in these particular pop-up boxes it did not. One typo in a long password and the erase key threw the whole box away and sent you back, so you had to start the password from the beginning.
- The same fix covers the other pop-up boxes that had it: the Wi-Fi network name, renaming a map pin, and naming a new folder in Files. Typing anywhere else - the Notes editor, a mesh message, the lock PIN - was never affected and is unchanged.


## Share a pin with someone, and a map that stays smooth with a hundred nodes on it

**2026.08.26.1** · 2026-08-26

- You can share a map pin with one person or with a whole channel. Open Maps, tap Pins, and each pin now has a Share button next to its name. Pick who it goes to and it appears on their device. It is sent as an ordinary Meshtastic waypoint, so it also turns up for people running stock firmware or looking at the phone app - not just other T-UI devices.
- Every pin says where it stands, in plain English, on the line under its name: "Not shared", "Shared with Nick", "Shared to LongFast", or "From Nick" for one somebody sent you. On the map, a pin you dropped is a solid dot and a pin somebody shared with you is a hollow ring - the same rule the node markers use, so there is only one thing to remember: solid means yours.
- Sharing and unsharing both ask first. Choosing who to share with no longer sends the moment you tap a name; a box comes up telling you exactly who is about to get it. The unshare box tells you the thing that is easy to get wrong - unsharing is a request, not a command, and anyone out of range when it goes out keeps their copy.
- Unsharing no longer gives up after one try. Before, it was a single message sent once into the air: if the person was out of range or switched off at that moment, it was simply lost and their copy of your pin was permanent - while your own screen said "Not shared". Now the device remembers and keeps asking. It re-sends twice in the first couple of minutes, then after 5, 15 and 30 minutes, an hour, and then every couple of hours for a week. Much more usefully, the moment it hears anything at all from someone the unshare is aimed at - which proves they are in range right now - it fires it straight at them. The reminder survives deleting the pin and survives switching the device off, and the Pins list shows "still asking" until it is done.
- The Nodes on/off switch has moved onto the map itself - a pill in the bottom right next to the settings cog, instead of being buried in the Pins list. Tapping it now tells you what happened: "Nodes on - 3 on the map", or "none have sent a position yet", which is usually the real reason you cannot see anybody. A node only appears on a map once it has broadcast its position, and plenty never do.
- Makes the map far smoother when there are a lot of nodes on it - tested with 121. Every marker used to be drawn among the map tiles, which meant that on every single redraw, every marker had to be pushed back to the front so the newly loaded tiles would not cover it. With 121 nodes that was hundreds of reorders per frame while you dragged the map, each one forcing part of the screen to be redrawn and re-sent to the display. Markers now sit in their own layer above the tiles, where nothing has to be reordered at all. On top of that, a marker is only moved or hidden when it has actually changed, and node name tags come off when you zoom out - which is exactly when all of them are on screen and the names are unreadable anyway.


## Apps can reach the internet properly - Weather works, and quickly

**2026.08.05.5** · 2026-08-05

- Fixes apps not being able to reach the internet - the Weather app would say it couldn't get the weather even with Wi-Fi connected and working. This is the same memory problem fixed in the last release, in a place it was missed. Downloading over a secure connection needs one unbroken stretch of the chip's fast memory, and the last release set that memory aside and handed it to Get Apps. But there are four separate places in the firmware that download things, and only two of them were given it. Apps had their own way onto the internet, and it was still starving. All four now use the same reserved memory.
- Fixes map downloads failing the same way. Nobody had reported this one - it was found by checking every place that downloads something, rather than waiting for it to go wrong. On a device that had been running a while, downloading map tiles would have failed exactly like Get Apps did.
- Weather now draws a little picture next to each day - sun, cloud, rain, snow, fog or a storm - so you can read the week at a glance without reading every word.
- Weather has a C/F button in the bottom right. It switches instantly and works on the saved forecast, because temperatures are stored one way and converted when they're drawn - so changing units never needs the internet. Your choice is remembered.
- Makes the Weather app fast. It was taking tens of seconds, and the reason was that the firmware switched Wi-Fi off after every single download - so an app that fetches twice (Weather asks where you are, then what the weather is) sat waiting for a whole Wi-Fi reconnection in the middle, for no reason. Worse, it was switching off Wi-Fi that the device had connected itself, which is what made the connection drop and reconnect repeatedly. It now reuses a connection that's already up, only switches off what it switched on, and holds the connection briefly in case another download follows. Measured on the device: the second download went from a full reconnect to 1.2 seconds.


## Get Apps can reach the app list again, and apps can now use the internet

**2026.08.05.3** · 2026-08-05

- Fixes Get Apps saying it couldn't reach the app list. This was not the server and not your Wi-Fi - the device was running out of memory in a way that doesn't look like running out of memory. Downloading over a secure connection needs one unbroken stretch of the chip's small pool of fast memory, about 34 KB of it, and it has to be one continuous piece. There was plenty free in total (79 KB) but by the time you opened Get Apps it had been broken into scattered pieces, the largest only 16 KB, so the download could never start. Nothing had broken it: the device just accumulates more to keep track of over time (233 radios on the mesh now), the memory got more scattered, and one day it crossed the line. The firmware now sets one clean stretch of memory aside in its very first instruction at startup, before anything can break it up, and hands it over whenever a download needs it. The device also gives the server 12 seconds to answer instead of 4, and switches Bluetooth off before downloading, which frees more room on devices that do have it on.
- Apps can use the internet. An app can now fetch information from the web - weather, tides, whatever it needs - without freezing while it waits. Wi-Fi has to be set up in Settings first. The new Weather app in Get Apps is the first one to use it.
- Apps can bring their own icon. Until now every app icon had to be drawn into the firmware, so a new app in Get Apps arrived as a plain coloured square unless the firmware was updated too. An app can now ship its own little picture and it appears on the home screen the moment it's installed - no firmware update needed.
- Apps can keep the erase key. The erase key normally backs you out of an app. In a game with controls next to it that meant a fumbled key quit the game. An app can now ask to keep that key for itself, and Stars does. A trackball double-click still gets you out of anything.
- The Weather app has a proper icon on the home screen.
- Weather now shows a 7-day forecast - the day, the high and low, and what it's doing - underneath the current conditions. It saves the forecast on the card, so opening the app shows it straight away with no waiting and without switching Wi-Fi on. It only fetches new weather when you tap the Refresh button in the top right, so a stray tap can't send it off to the internet.
- Fixes Weather never finding your location when you don't have a GPS fix. It asks the internet roughly where you are instead, but a subtle slip meant it only ever read the latitude and threw the longitude away, so it gave up every time and said it couldn't get the weather.


## Fixes from the first outside reports, GPS for apps, and a Deep Space icon

**2026.07.22.3** · 2026-07-22

- Fixes a screen that couldn't be turned back on. Holding the gear icon on the Meshtastic screens was meant to switch the screen off, and the way back was a tap on a hidden panel - but on the T-Deck the firmware dims the backlight instead of ever showing that panel, so there was nothing to tap and every attempt to wake the device was undone a moment later. The screen stayed dark until the power was cut. It now switches off the same way a double-tap on the trackball does, which wakes properly.
- Fixes rearranging your apps. Holding an app tile opens 'Arrange apps', but the new order was thrown away about a tenth of a second later, as soon as the home grid redrew. The order was only ever remembered by writing it to the SD card, so on a T-Deck with no card in it there was nowhere to write it and nothing ever stuck. The order is now kept in memory too, so rearranging works with or without a card - and still survives a reboot when a card is in.
- The erase key now works as Back - it steps you out of any app, the same as a trackball double-click. If you're typing, it stays a normal backspace. On the home screen a single press does nothing, but a double-tap of erase puts the device to sleep (just like double-clicking the trackball), which helps if your trackball is stiff.
- New option: a 24-hour clock. Settings has a switch to show the clock as 14:30 instead of 2:30 PM, and it changes the moment you flip it.
- Settings now shows the Meshtastic version as well as this launcher's version, at the bottom of the screen. They're two different things, and there was previously nowhere to look up the Meshtastic one.
- The keyboard backlight is turned on and off with the keyboard's own Alt+B shortcut, and Settings now points that out so it's easier to find.
- Apps can now read the GPS. There's a new GPS Test app in Get Apps that shows whether you have a fix, how many satellites it's using, and your coordinates - the first of several new things apps will be able to do (Wi-Fi and the long-range radio are coming next).
- Deep Space has its own icon on the home grid - your ship climbing up through a starfield - instead of a plain coloured tile.
- Deep Space v19: Earth now genuinely exists at the centre of the galaxy (X0 Y0) and patches your hull up cheap; dying tows you home and costs you half your credits and all your Parts; lasers lock onto the enemy you're aiming at, with the beam actually reaching them; enemy fire is colour-coded by the ship that shot it; a bracket marks whatever you're locked onto; and there's a calmer patch of space around home so the swarms are something you fly out to meet. Update it from Get Apps.


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
