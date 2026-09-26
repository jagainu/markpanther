#!/usr/bin/env bash
# GitHub Releases にリリースを出す。make publish から呼ぶ。
#
# 1. project.yml の MARKETING_VERSION を版とし、CHANGELOG.md にその版の節があるか確かめる
# 2. make dist（署名 → 公証 → staple → zip）
# 3. vX.Y.Z のタグを打って push し、zip を添付した Release を作る
#
#   DRY_RUN=1     何も作らず、版・タグ・Release 本文だけ見せて止まる
#   SKIP_BUILD=1  build/dist/MarkPanther.zip を作り直さずに使う（公証済みのものがある前提）
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="${REPO:-jagainu/markpanther}"
ZIP=build/dist/MarkPanther.zip

die() { echo "publish: $*" >&2; exit 1; }

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)
[ -n "$VERSION" ] || die "project.yml から MARKETING_VERSION が読めない"
TAG="v$VERSION"

# CHANGELOG の「## [x.y.z]」節を Release の本文にする。無ければ出さない
NOTES=$(awk -v v="$VERSION" '
  /^## / { if (on) exit; if (index($0, "[" v "]")) { on = 1; next } }
  on' CHANGELOG.md)
[ -n "$(echo "$NOTES" | tr -d '[:space:]')" ] || die "CHANGELOG.md に [$VERSION] の節が無い"

if [ -n "${DRY_RUN:-}" ]; then
  echo "=== $REPO に $TAG を出す（$(git rev-parse --short HEAD) から）==="
  echo "$NOTES"
  exit 0
fi

[ -z "$(git status --porcelain)" ] || die "作業ツリーが汚れている。コミットしてから出す"
git fetch --quiet origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse '@{u}')" ] || die "origin と揃っていない。push してから出す"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  die "$TAG はもう出ている。project.yml の版を上げる"
fi

[ -n "${SKIP_BUILD:-}" ] || make dist
[ -f "$ZIP" ] || die "$ZIP が無い"

git tag -a "$TAG" -m "MarkPanther $VERSION"
git push --quiet origin "$TAG"
gh release create "$TAG" "$ZIP" --repo "$REPO" --verify-tag \
  --title "MarkPanther $VERSION" --notes "$NOTES"

echo "出しました: https://github.com/$REPO/releases/tag/$TAG"
