#!/usr/bin/env python3
"""
Chunk a plain .txt file into the format the T-Deck reader app expects, for
a specific book id, and register it in that folder's books.txt manifest so
it shows up in the library screen.

Usage:
    python3 chunk_book.py mybook.txt output_folder/ --id shelter --title "Shelter Basics"

This writes, into output_folder/:
    shelter-0001.txt, shelter-0002.txt, ...  (the chunked text)
    shelter-meta.txt                          (chunk count)
    books.txt                                 (adds/updates the "shelter|Shelter Basics" line)

Re-running with the same --id updates that book's chunks/title in place
(old chunk files from a previous run of the same id, if there are now
fewer chunks, are left behind -- delete the output folder's old
<id>-NNNN.txt files first if you've shrunk a book significantly).

output_folder/ should be the same folder you copy to /apps/reader/ on the
SD card (alongside main.lua) -- every book's files live flat in that one
folder, distinguished by their id prefix.

Input format: separate paragraphs with a blank line. Single newlines
within a paragraph are treated as regular spaces (so you can hard-wrap
your source file for editing convenience without it affecting output).
"""

import argparse
import os
import re

MAX_CHARS = 3500  # stay comfortably under the 4KB store.write limit
ID_PATTERN = re.compile(r"^[a-z0-9_-]{1,40}$")


def read_text_file(path):
    """Try a few common encodings before giving up, since .txt files from
    varied sources (Word exports, older ebooks, etc.) aren't always UTF-8."""
    encodings_to_try = ["utf-8-sig", "utf-8", "cp1252", "latin-1"]
    for enc in encodings_to_try:
        try:
            with open(path, "r", encoding=enc) as f:
                return f.read()
        except UnicodeDecodeError:
            continue
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def load_paragraphs(path):
    raw = read_text_file(path)
    blocks = raw.split("\n\n")
    paragraphs = []
    for block in blocks:
        collapsed = " ".join(block.split())
        if collapsed:
            paragraphs.append(collapsed)
    return paragraphs


def split_oversized_paragraph(paragraph, max_chars):
    parts = []
    while len(paragraph) > max_chars:
        cut = paragraph.rfind(" ", 0, max_chars)
        if cut <= 0:
            cut = max_chars
        parts.append(paragraph[:cut])
        paragraph = paragraph[cut:].lstrip()
    parts.append(paragraph)
    return parts


def chunk_paragraphs(paragraphs, max_chars):
    chunks = []
    current = []
    current_len = 0

    def flush():
        nonlocal current, current_len
        if current:
            chunks.append("\n".join(current))
            current = []
            current_len = 0

    for para in paragraphs:
        pieces = [para] if len(para) <= max_chars else split_oversized_paragraph(para, max_chars)
        for piece in pieces:
            added_len = len(piece) + (1 if current else 0)
            if current_len + added_len > max_chars:
                flush()
            current.append(piece)
            current_len += len(piece) + (1 if len(current) > 1 else 0)
    flush()
    return chunks


def update_manifest(outdir, book_id, title):
    path = os.path.join(outdir, "books.txt")
    entries = []
    seen = False
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line:
                    continue
                parts = line.split("|", 1)
                if len(parts) == 2:
                    eid, etitle = parts
                    if eid == book_id:
                        entries.append((eid, title))
                        seen = True
                    else:
                        entries.append((eid, etitle))
    if not seen:
        entries.append((book_id, title))
    with open(path, "w", encoding="utf-8") as f:
        for eid, etitle in entries:
            f.write(f"{eid}|{etitle}\n")


def main():
    parser = argparse.ArgumentParser(description="Chunk a .txt file for the T-Deck reader app.")
    parser.add_argument("input", help="Source .txt file")
    parser.add_argument("output_folder", help="Folder to write chunk files + manifest into")
    parser.add_argument("--id", required=True, help="Book id: lowercase letters/digits/-/_ only, e.g. 'shelter'")
    parser.add_argument("--title", required=True, help="Display title shown in the library screen")
    args = parser.parse_args()

    if not ID_PATTERN.match(args.id):
        print(f"Error: --id '{args.id}' must be 1-40 chars, lowercase letters/digits/-/_ only.")
        raise SystemExit(1)

    os.makedirs(args.output_folder, exist_ok=True)

    paragraphs = load_paragraphs(args.input)
    chunks = chunk_paragraphs(paragraphs, MAX_CHARS)

    for i, chunk_text in enumerate(chunks, start=1):
        fname = os.path.join(args.output_folder, f"{args.id}-{i:04d}.txt")
        with open(fname, "w", encoding="utf-8") as f:
            f.write(chunk_text)

    with open(os.path.join(args.output_folder, f"{args.id}-meta.txt"), "w", encoding="utf-8") as f:
        f.write(str(len(chunks)))

    update_manifest(args.output_folder, args.id, args.title)

    print(f"Wrote {len(chunks)} chunk(s) for '{args.id}' + updated books.txt in {args.output_folder}/")


if __name__ == "__main__":
    main()
