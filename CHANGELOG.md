# Changelog

## [0.1.4] - 2026-10-11

- Fix: confirming Japanese (or other input method) text with Return could insert
  a line break. Autosave mistook its own write for an outside change and reloaded
  the editor mid-typing
- Change: brackets and quotes are paired only where nothing follows on the line,
  and quotes aren't paired right after a letter or digit
- New: Shift-Tab removes one level of indentation
- New: macOS text replacements (System Settings → Keyboard) work in the editor
- New: when another app rewrites the file, ⌘Z brings back the previous text
- Fix: lists — Return at the start of an item no longer doubles the marker, the
  caret lands on the new item in numbered lists, renumbering continues past
  nested items, Return on an empty nested item moves it up a level, and
  Backspace right after a marker removes the whole marker
- Fix: typing ``` no longer produces four backticks

## [0.1.3] - 2026-09-28

- Fix: in tables, a row where text was removed no longer shifts its cells
  one column to the right

## [0.1.2] - 2026-09-27

- New: Markdown files get a MarkPanther document icon
- New: a file icon beside the title — drag it to move or copy the file,
  ⌘-click for the folder path
- Fix: the title bar area now drags the window (it used to select text in
  the document underneath)
- Fix: the path menu shows folder and file icons again

## [0.1.1] - 2026-09-27

- Fix: About MarkPanther showed version 1.0 instead of the real version

## [0.1.0] - 2026-09-23

First public release.

- Live reload that follows atomic replaces, with changed blocks highlighted
- Preview ⇄ editor toggle (⌘E) with autosave
- Outline, find, Quick Open, zoom, copy button on code blocks
- GFM, syntax highlighting, Mermaid, KaTeX, frontmatter, `[TOC]`, footnotes
- Background change notifications
- Quick Look and thumbnail extensions
- Siri and Shortcuts actions: Open Markdown Document, Show Changes
- `markp` command-line tool, installable from the app menu
