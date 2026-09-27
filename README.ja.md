<p align="center">
  <img src="assets/icon.png" width="128" alt="MarkPanther のアイコン">
</p>

<h1 align="center">MarkPanther</h1>

<p align="center">
  Claude Code の横に置く、macOS 用 Markdown ビューア/エディタ<br>
  <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/jagainu/markpanther/releases/latest"><b>最新版をダウンロード</b></a>
</p>

---

AI エージェントが書き換えたファイルを、その場で最新の姿に。どこが変わったかも光らせて見せます。

- **外部からの上書きを即反映。** 親ディレクトリごと監視しているので、Claude Code のように
  「ファイルを差し替えて保存する」ツールでも追従が切れません
- **変わった所が分かる。** 追加されたブロックは余白に印が付き、消えた所には印が残って、
  ホバーすると元の姿が見えます
- **1画面で2モード。** プレビューとエディタを ⌘E で切り替え。スクロール位置も引き継ぎます
- **自動保存。** 打鍵が止まって 0.5 秒で保存。その間に外で書き換えられていたら、
  どちらを残すかバナーで選べます

## 動作環境

macOS 15 Sequoia 以降。無料でお使いいただけます。

## インストール

1. [最新リリース](https://github.com/jagainu/markpanther/releases/latest) から
   `MarkPanther.zip` をダウンロードして展開
2. `MarkPanther.app` を**アプリケーション**フォルダに移して開く
   （Developer ID 署名・Apple の公証済み）
3. `markp` コマンドを使うなら、メニューの
   **MarkPanther → Install ‘markp’ Command Line Tool…**

```sh
markp notes.md      # 開く（無ければ作る）
markp -g notes.md   # フォーカスを奪わずに裏で開く
```

`markp` が見つからないときは、`~/.local/bin` を `PATH` に足してください。

## Claude Code が書いた md を自動で開く

`~/.claude/settings.json`（またはプロジェクトの `.claude/settings.json`）にフックを足します。

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

**File → Open Latest Claude Plan**（⌥⌘L）で `~/.claude/plans` の最新プランを開けます。

## 機能

- GFM / コードハイライト / Mermaid / KaTeX / YAML frontmatter / `[TOC]` / 脚注 / タスクリスト
- アウトライン（⌃⌘S）、見出しへジャンプ（⌥⌘J）、検索（⌘F、プレビューでも効く）、ズーム
- 最近開いたファイルから絞り込んで開く（⌘O）
- 標準の書類ウィンドウと同じタイトル：ファイル名の左のアイコンをドラッグでファイルを移動・コピー、
  ファイル名を ⌘クリックでフォルダの階層を表示
- コードブロックの Copy ボタン
- 裏にいるあいだに書き換えられたら通知（短時間の連続書き込みは1本にまとめる）
- Quick Look：Finder で `.md` をスペースキーで覗くと組版済みで表示
- Siri・ショートカット：**Open Markdown Document** / **Show Changes** アクション
- カスタム CSS：`~/Library/Application Support/MarkPanther/Styles/` に `*.css` を置き、
  Settings → Rendering で選択

## フィードバック

不具合や要望は [Issue](https://github.com/jagainu/markpanther/issues/new/choose) へ。
質問や雑談は [Discussions](https://github.com/jagainu/markpanther/discussions) へどうぞ（日本語で大丈夫です）。

## ソースからビルド

Xcode・[XcodeGen](https://github.com/yonaskolb/XcodeGen)・[Bun](https://bun.sh) が必要です。

```sh
brew install xcodegen
make run        # Debug ビルドして起動
make install    # /Applications と ~/.local/bin/markp に入れる
make test       # Swift パッケージのテスト + プレビュー描画のテスト
```

ソースからのビルドは Bundle ID が `dev.nijizo.markpanther.dev` になるので、公式版と同じ Mac に
入れても通知や設定が混ざりません。構成は [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

## ライセンス

[MIT](LICENSE)。同梱しているライブラリは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) に。

---

Made by Makoto Taguchi · NIJIZO · [nijizo.dev](https://nijizo.dev)
