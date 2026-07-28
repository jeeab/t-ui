# Reader

A paginated text reader for the T-Deck. Books are plain `.txt` files, pre-split
into small chunks on your computer and copied to the SD card alongside this app.

## What ships to the device

Only `main.lua` is loaded by the app engine (that's how the T-UI app system
works — a catalog entry just points at one Lua file). `main.lua` has a small
"How to Add Books" guide built directly into it as a first-run help book, so
the app is useful immediately even before you've added anything of your own.

## Controls

- Tap the right third of the screen to go forward a page, the left third to
  go back. The middle third is unused for now.
- `[Menu]` (top-left, while reading) returns to the book list.
- `|<< Start` and `End >>|` (bottom corners, while reading) jump to the
  beginning or end of the current book.
- Your position in each book is saved automatically and restored next time
  you open it.

## Adding your own books

`chunk_book.py`, included in this folder, is a small companion script that
runs on your computer (not on the device) and turns a plain `.txt` file into
the chunked format this app reads:

```
python3 chunk_book.py mybook.txt output_folder/ --id shelter --title "Shelter Basics"
```

- `--id` should be short, lowercase, letters/numbers/dashes/underscores only.
- `--title` is what shows up in the app's book list.

This writes a handful of small files into `output_folder/` (chunked text,
a chunk-count file, and an entry in a shared `books.txt` manifest). Copy
everything from `output_folder/` into this app's folder on the SD card,
alongside `main.lua`, and the new book appears in the list next time the
app opens. Run it again for each additional book — every run just adds
itself to the manifest without disturbing books already there.

`chunk_book.py` itself never touches the device — it's included here purely
as a reference/companion tool for anyone browsing this repo.
