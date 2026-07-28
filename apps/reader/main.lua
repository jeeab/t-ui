-- T-Deck Reader (with library screen)
-- Books are pre-chunked text files named "<bookid>-0001.txt", "<bookid>-0002.txt", ...
-- plus "<bookid>-meta.txt" (chunk count) and "<bookid>-pos.txt" (bookmark).
-- A manifest file "books.txt" lists installed books, one per line as "id|Title".
-- Use chunk_book.py (on your computer) to generate all of this from a plain .txt file.

------------------------------------------------------------
-- TUNABLES -- adjust these after testing on real hardware --
------------------------------------------------------------
local CHARS_PER_LINE = 33   -- guess for the built-in font; verify on device
local LINE_HEIGHT    = 16   -- pixels between lines
local LINES_PER_PAGE = 11   -- how many text lines fit on screen
local TEXT_START_Y   = 21   -- first text line's y position
local LEFT_MARGIN    = 8
local HEADER_Y        = 1
local FOOTER_Y        = 219
local HEADER_BAND     = 20  -- y < this = header tap band
local FOOTER_BAND     = 219 -- y >= this = footer tap band
local LIBRARY_ROW_Y   = 30
local LIBRARY_ROW_H   = 18
local MAX_LIBRARY_ROWS = 12
------------------------------------------------------------

-- element ids
-- element ids
local READING_MENU_ID    = 1
local READING_INFO_ID    = 2
local READING_START_ID   = 3
local READING_END_ID     = 4
local READING_PAGENUM_ID = 5
local TITLE_MAX_CHARS    = 18  -- truncate long titles so they can't collide with the page number
local PAGENUM_X          = 250 -- fixed x for the page-number label (no text-measurement API to right-align exactly)
local READING_LINE_BASE = 10 -- 10 .. 10+LINES_PER_PAGE-1
local LIBRARY_TITLE_ID = 39
local LIBRARY_ROW_BASE = 40  -- 40 .. 40+MAX_LIBRARY_ROWS-1

-- built-in help book: always available, even with no books.txt installed yet
local HELP_BOOK_ID = "help"
local HELP_TITLE = "How to Add Books"
local HELP_TEXT = [[
Welcome to Reader! This app shows plain text as pages you flip through, like an e-reader.
Controls: tap the right side of the screen to go forward a page, the left side to go back. The middle does nothing yet.
Up top, [Menu] on the left returns you to this book list. The title and page count are shown on the same line.
Down at the bottom, |<< Start jumps to the very beginning of the current book, and End >>| jumps to the very end.
Your page in each book is saved automatically, so closing the app and reopening it picks up where you left off.
To add your own books, you need a small helper script called chunk_book.py, which turns a plain .txt file into the format this app reads. It is included alongside this app in its source repository, or ask whoever gave you this app for a copy.
On your computer, with chunk_book.py and your book's .txt file in the same folder, run a command shaped like this:
python3 chunk_book.py mybook.txt output_folder/ --id shelter --title "Shelter Basics"
The --id should be short, lowercase, no spaces (letters, numbers, dashes and underscores only). The --title is what shows up in this book list, so keep it readable.
That command creates a few small files in output_folder/. Copy all of them into this app's folder on the SD card, alongside main.lua, then reopen the app. Your new book will appear in this list.
You can repeat this for as many books as you like. Each one just adds itself to the list without disturbing the others.
]]



-- state
local screenState = "library"  -- "library" | "reading"
local books = {}                -- { {id=..., title=...}, ... }
local currentBookId = nil
local totalChunks = 1
local currentChunk = 1
local lineOffset = 0
local wrappedLines = {}

------------------------------------------------------------
-- text helpers
------------------------------------------------------------

local function splitLines(text)
  local out = {}
  local start = 1
  while true do
    local nl = text:find("\n", start, true)
    if not nl then
      table.insert(out, text:sub(start))
      break
    end
    table.insert(out, text:sub(start, nl - 1))
    start = nl + 1
  end
  return out
end

local function wrapParagraph(text, width)
  local lines = {}
  local cur = ""
  for word in text:gmatch("%S+") do
    if cur == "" then
      cur = word
    elseif #cur + 1 + #word <= width then
      cur = cur .. " " .. word
    else
      table.insert(lines, cur)
      cur = word
    end
  end
  table.insert(lines, cur)
  return lines
end

local function buildWrappedLines(chunkText)
  local out = {}
  local paras = splitLines(chunkText)
  for i, p in ipairs(paras) do
    local plines = wrapParagraph(p, CHARS_PER_LINE)
    for _, l in ipairs(plines) do table.insert(out, l) end
    if i < #paras then table.insert(out, "") end
  end
  return out
end

------------------------------------------------------------
-- manifest / book loading
------------------------------------------------------------

local function loadManifest()
  books = { { id = HELP_BOOK_ID, title = HELP_TITLE } }
  local raw = store.read("books.txt")
  if not raw then return end
  local lines = splitLines(raw)
  for _, line in ipairs(lines) do
    if line ~= "" then
      local id, title = line:match("^([^|]+)|(.*)$")
      if id and id ~= HELP_BOOK_ID then
        table.insert(books, { id = id, title = title })
      end
    end
  end
end

local function chunkFilename(bookId, n)
  return string.format("%s-%04d.txt", bookId, n)
end

local function metaFilename(bookId)
  return bookId .. "-meta.txt"
end

local function posFilename(bookId)
  return bookId .. "-pos.txt"
end

local function loadChunk(n)
  local raw
  if currentBookId == HELP_BOOK_ID then
    raw = HELP_TEXT
  else
    raw = store.read(chunkFilename(currentBookId, n)) or ""
  end
  wrappedLines = buildWrappedLines(raw)
end

local function savePosition()
  store.write(posFilename(currentBookId), currentChunk .. "|" .. lineOffset)
end

------------------------------------------------------------
-- clearing / hiding elements between screens
------------------------------------------------------------

local function clearReadingScreen()
  screen.hide(READING_MENU_ID)
  screen.hide(READING_INFO_ID)
  screen.hide(READING_START_ID)
  screen.hide(READING_END_ID)
  screen.hide(READING_PAGENUM_ID)
  for i = 0, LINES_PER_PAGE - 1 do
    screen.hide(READING_LINE_BASE + i)
  end
end

local function clearLibraryScreen()
  screen.hide(LIBRARY_TITLE_ID)
  for i = 0, MAX_LIBRARY_ROWS - 1 do
    screen.hide(LIBRARY_ROW_BASE + i)
  end
end

------------------------------------------------------------
-- library screen
------------------------------------------------------------

local function renderLibrary()
  screen.label(LIBRARY_TITLE_ID, LEFT_MARGIN, 6, "Select a Book", 0xffffff)

  if #books == 0 then
    screen.label(LIBRARY_ROW_BASE, LEFT_MARGIN, LIBRARY_ROW_Y, "No books installed yet.", 0x8e8e93)
    for i = 1, MAX_LIBRARY_ROWS - 1 do
      screen.hide(LIBRARY_ROW_BASE + i)
    end
    return
  end

  for i = 1, MAX_LIBRARY_ROWS do
    local id = LIBRARY_ROW_BASE + i - 1
    local book = books[i]
    if book then
      screen.label(id, LEFT_MARGIN, LIBRARY_ROW_Y + (i - 1) * LIBRARY_ROW_H, book.title, 0xffffff)
    else
      screen.hide(id)
    end
  end
end

local function openBook(bookId)
  currentBookId = bookId
  if bookId == HELP_BOOK_ID then
    totalChunks = 1
  else
    totalChunks = tonumber(store.read(metaFilename(bookId)) or "1") or 1
  end

  currentChunk = 1
  lineOffset = 0
  local pos = store.read(posFilename(bookId))
  if pos then
    local c, o = pos:match("(%d+)|(%d+)")
    if c and o then
      currentChunk = tonumber(c)
      lineOffset = tonumber(o)
    end
  end
  if currentChunk > totalChunks then currentChunk = totalChunks end
  if currentChunk < 1 then currentChunk = 1 end

  loadChunk(currentChunk)
  if lineOffset > #wrappedLines then lineOffset = 0 end

  clearLibraryScreen()
  screenState = "reading"
  renderReadingPage()
end

local function handleLibraryTouch(x, y)
  if y < LIBRARY_ROW_Y then return end
  local rowIndex = math.floor((y - LIBRARY_ROW_Y) / LIBRARY_ROW_H) + 1
  local book = books[rowIndex]
  if book then
    openBook(book.id)
  end
end

------------------------------------------------------------
-- reading screen
------------------------------------------------------------

function renderReadingPage()
  for i = 1, LINES_PER_PAGE do
    local idx = lineOffset + i
    local text = wrappedLines[idx] or ""
    screen.label(READING_LINE_BASE + i - 1, LEFT_MARGIN, TEXT_START_Y + (i - 1) * LINE_HEIGHT, text, 0xffffff)
  end

  screen.label(READING_MENU_ID, LEFT_MARGIN, HEADER_Y, "[Menu]", 0x0a84ff)

  local title = "Book"
  for _, b in ipairs(books) do
    if b.id == currentBookId then title = b.title end
  end
  if #title > TITLE_MAX_CHARS then
    title = title:sub(1, TITLE_MAX_CHARS - 3) .. "..."
  end
  screen.label(READING_INFO_ID, 90, HEADER_Y, title, 0x8e8e93)
  screen.label(READING_PAGENUM_ID, PAGENUM_X, HEADER_Y, currentChunk .. "/" .. totalChunks, 0x8e8e93)

  screen.label(READING_START_ID, LEFT_MARGIN, FOOTER_Y, "|<< Start", 0x8e8e93)
  screen.label(READING_END_ID, 230, FOOTER_Y, "End >>|", 0x8e8e93)
end

local function goToMenu()
  savePosition()
  clearReadingScreen()
  screenState = "library"
  renderLibrary()
end

local function jumpToStart()
  currentChunk = 1
  lineOffset = 0
  loadChunk(currentChunk)
  renderReadingPage()
  savePosition()
end

local function jumpToEnd()
  currentChunk = totalChunks
  loadChunk(currentChunk)
  lineOffset = math.floor(math.max(0, #wrappedLines - 1) / LINES_PER_PAGE) * LINES_PER_PAGE
  renderReadingPage()
  savePosition()
end

local function nextPage()
  if lineOffset + LINES_PER_PAGE < #wrappedLines then
    lineOffset = lineOffset + LINES_PER_PAGE
  elseif currentChunk < totalChunks then
    currentChunk = currentChunk + 1
    loadChunk(currentChunk)
    lineOffset = 0
  else
    device.beep()
    return
  end
  renderReadingPage()
  savePosition()
end

local function prevPage()
  if lineOffset > 0 then
    lineOffset = math.max(0, lineOffset - LINES_PER_PAGE)
  elseif currentChunk > 1 then
    currentChunk = currentChunk - 1
    loadChunk(currentChunk)
    lineOffset = math.floor(math.max(0, #wrappedLines - 1) / LINES_PER_PAGE) * LINES_PER_PAGE
  else
    device.beep()
    return
  end
  renderReadingPage()
  savePosition()
end

local function handleReadingTouch(x, y)
  if y < HEADER_BAND then
    if x < 90 then goToMenu() end
  elseif y >= FOOTER_BAND then
    if x < 320 / 3 then
      jumpToStart()
    elseif x > 320 * 2 / 3 then
      jumpToEnd()
    end
  else
    if x > 320 * 2 / 3 then
      nextPage()
    elseif x < 320 / 3 then
      prevPage()
    end
  end
end

------------------------------------------------------------
-- lifecycle
------------------------------------------------------------

function on_open()
  loadManifest()
  screenState = "library"
  renderLibrary()
end

function on_touch(x, y)
  if screenState == "library" then
    handleLibraryTouch(x, y)
  else
    handleReadingTouch(x, y)
  end
end
