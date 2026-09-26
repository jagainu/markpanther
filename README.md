<p align="center">
  <img src="assets/icon.png" width="128" alt="MarkPanther icon">
</p>

<h1 align="center">MarkPanther</h1>

<p align="center">
  A Markdown viewer and editor for macOS, built to sit beside Claude Code.<br>
  <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <a href="https://github.com/jagainu/markpanther/releases/latest"><b>Download the latest release</b></a>
</p>

---

When an AI agent rewrites the file you're reading, MarkPanther shows the new
version instantly — and highlights what changed.

- **Live reload that survives atomic writes.** It watches the parent directory,
  so tools that save by replacing the file (as Claude Code does) never break the
  connection.
- **See what changed.** Added blocks are marked in the margin; removed ones
  leave a marker you can hover to see what was there.
- **One pane, two modes.** Switch between preview and editor with ⌘E. The
  scroll position carries over.
- **Autosave.** Edits save 0.5 s after you stop typing. If the file changed on
  disk in the meantime, a banner asks which version to keep.

## Requirements

macOS 15 Sequoia or later. Free to use.

## Install

1. Download `MarkPanther.zip` from the
   [latest release](https://github.com/jagainu/markpanther/releases/latest) and
   unzip it.
2. Move `MarkPanther.app` to your **Applications** folder and open it.
   The app is signed with a Developer ID and notarized by Apple.
3. To get the `markp` command, choose
   **MarkPanther → Install ‘markp’ Command Line Tool…** from the menu.

```sh
markp notes.md      # open (creates the file if it doesn't exist)
markp -g notes.md   # open in the background without stealing focus
```

If `markp` isn't found, add `~/.local/bin` to your `PATH`.

## Open files as Claude Code writes them

Add a hook to `~/.claude/settings.json` (or a project's `.claude/settings.json`):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "f=$(jq -r '.tool_input.file_path // empty'); case \"$f\" in *.md|*.markdown) markp -g \"$f\";; esac"
          }
        ]
      }
    ]
  }
}
```

**File → Open Latest Claude Plan** (⌥⌘L) opens the newest plan in
`~/.claude/plans`.

## Features

- GitHub Flavored Markdown, syntax highlighting, Mermaid, KaTeX, YAML
  frontmatter, `[TOC]`, footnotes, task lists
- Outline (⌃⌘S), jump to heading (⌥⌘J), find (⌘F, works in preview too), zoom
- Quick Open of recent files (⌘O)
- Copy button on code blocks
- Notifications when a file changes while MarkPanther is in the background —
  bursts of writes are grouped into one
- Quick Look: press Space on a `.md` file in Finder to see it rendered
- Siri and Shortcuts: **Open Markdown Document** and **Show Changes** actions
- Custom CSS: put `*.css` in `~/Library/Application Support/MarkPanther/Styles/`
  and pick it in Settings → Rendering

## Feedback

Found a bug or have an idea? Please
[open an issue](https://github.com/jagainu/markpanther/issues/new/choose).
Questions and general discussion go to
[Discussions](https://github.com/jagainu/markpanther/discussions).

## Building from source

Requires Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and
[Bun](https://bun.sh).

```sh
brew install xcodegen
make run        # build (Debug) and launch
make install    # install to /Applications and ~/.local/bin/markp
make test       # Swift package tests + web renderer tests
```

Builds from source use the bundle ID `dev.nijizo.markpanther.dev`, so they can
live next to the official release without mixing up notifications or settings.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout.

## License

[MIT](LICENSE). Bundled third-party libraries are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

Made by Makoto Taguchi · NIJIZO · [nijizo.dev](https://nijizo.dev)
