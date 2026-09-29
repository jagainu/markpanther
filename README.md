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

## Update

The same steps work from any earlier version. Your settings, recent files and
notification permission carry over.

1. Quit MarkPanther (⌘Q).
2. Download `MarkPanther.zip` from the
   [latest release](https://github.com/jagainu/markpanther/releases/latest),
   unzip it, and move `MarkPanther.app` to **Applications**, choosing
   **Replace**.
3. Open it. **MarkPanther → About MarkPanther** shows the version.

Or from Terminal (the old version goes to the Trash):

```sh
osascript -e 'quit app id "dev.nijizo.markpanther"'
while pgrep -qf /Applications/MarkPanther.app/Contents/MacOS; do sleep 0.5; done
d=$(mktemp -d)
curl -fL -o "$d/MarkPanther.zip" https://github.com/jagainu/markpanther/releases/latest/download/MarkPanther.zip
ditto -x -k "$d/MarkPanther.zip" "$d"
mv /Applications/MarkPanther.app ~/.Trash/"MarkPanther $(date +%Y%m%d-%H%M%S).app"
mv "$d/MarkPanther.app" /Applications/
open /Applications/MarkPanther.app
```

You don't need to reinstall the `markp` command unless the release notes say
so. Version 0.1.0 shows "1.0" in About — a bug fixed in 0.1.1.

## Open files as your AI agent writes them

Both hooks below need [jq](https://jqlang.org) (`brew install jq`) and the
`markp` command.

### Claude Code

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

### Codex

Add a hook to `~/.codex/hooks.json` (or a project's `.codex/hooks.json`).
Codex edits files with `apply_patch`, so the hook reads the file paths out of
the patch:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "apply_patch",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.cwd as $d | (.tool_input.command // \"\") | split(\"\\n\")[] | capture(\"^\\\\*\\\\*\\\\* (Add File|Update File|Move to): (?<p>.+)$\")? | .p | if startswith(\"/\") then . else $d + \"/\" + . end' | grep -E '\\.(md|markdown)$' | while IFS= read -r f; do markp -g \"$f\"; done"
          }
        ]
      }
    ]
  }
}
```

Then run `/hooks` in Codex and trust the hook — Codex doesn't run a hook until
you have reviewed it, and asks again whenever it changes. A project's
`.codex/hooks.json` is loaded only when you trust that project. Files that
Codex writes through shell commands instead of `apply_patch` aren't picked up.

## Features

- GitHub Flavored Markdown, syntax highlighting, Mermaid, KaTeX, YAML
  frontmatter, `[TOC]`, footnotes, task lists
- Outline (⌃⌘S), jump to heading (⌥⌘J), find (⌘F, works in preview too), zoom
- Quick Open of recent files (⌘O)
- Title bar like a native document window: drag the file icon to move or copy
  the file, ⌘-click the title for its folder path
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
