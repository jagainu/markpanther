# Contributing

Thanks for helping make MarkPanther better. English or Japanese are both fine.
/ 日本語でも大丈夫です。

- **Bug reports** — [open an issue](https://github.com/jagainu/markpanther/issues/new?template=bug_report.yml).
  Include your macOS version, the MarkPanther version (MarkPanther → About),
  and steps to reproduce. A sample `.md` file that shows the problem is gold.
- **Feature requests** — [open an issue](https://github.com/jagainu/markpanther/issues/new?template=feature_request.yml)
  and describe what you're trying to do, not only the feature you have in mind.
- **Questions** — use [Discussions](https://github.com/jagainu/markpanther/discussions).
- **Pull requests** — small fixes are welcome as-is. For anything larger, please
  open an issue first so we can agree on the approach.

## Development

Requires Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and
[Bun](https://bun.sh). The Xcode project is generated from `project.yml` and
is not committed.

```sh
make run        # generate the project, build (Debug) and launch
make install    # install to /Applications and ~/.local/bin/markp
make test       # Core (swift test) + web (bun test)
make test-ui    # XCUITest — takes over the keyboard and mouse while it runs
make vendor     # rebuild App/Resources/preview/vendor from web/'s dependencies
```

Layout:

- `Packages/MarkPantherCore` — UI-independent logic (file watching, document
  session, recent documents, fuzzy matching, formatting, highlighting)
- `App/` — the AppKit shell. The preview is a WKWebView that can only load
  resources through the `markp://` scheme
- `App/Resources/preview/` — the preview's HTML/JS/CSS. `vendor/` is generated
  by `make vendor` and committed
- `web/` — tests and a dev server for the preview renderer
- `QuickLook/`, `Thumbnail/` — Finder extensions
- `scripts/markp` — the command-line tool bundled with the app

Builds from source use the bundle ID `dev.nijizo.markpanther.dev`. Only the
official, notarized releases use `dev.nijizo.markpanther`.

If you update a library under `web/`, run `make vendor` and update
`THIRD_PARTY_NOTICES.md`.
