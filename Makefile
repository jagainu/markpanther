APP      := MarkPanther
BUILD    := build
BIN_DIR  ?= $(HOME)/.local/bin
CORE     := Packages/MarkPantherCore
DIST     := $(BUILD)/dist

# 署名。既定は ad-hoc で、手元で動かすぶんにはこれで足りる。
# 配る物は Developer ID で署名して公証する — signed / notarize / dist を使う。
# Team ID と公証プロファイル名はリポジトリに置かない。メンテナの手元では private/Signing.local.mk
# （非公開の入れ子リポジトリ）から読む。それ以外の人は make dist TEAM_ID=... NOTARY_PROFILE=... で渡す
-include private/Signing.local.mk
SIGN_ID        ?= -
TEAM_ID        ?=
HARDENED       ?= NO
# xcrun notarytool store-credentials で作った名前
NOTARY_PROFILE ?=

# 配布ビルドだけで要るもの。ad-hoc 署名には署名時刻を付けられないので既定は空にしておく
TIMESTAMP      ?=
# Xcode は既定で com.apple.security.get-task-allow（デバッガ接続を許す）を注入する。
# 公証はこれが入っていると必ず落ちる
INJECT_DEBUG_ENTITLEMENTS ?= YES

# 公式の配布物だけが本物の Bundle ID を名乗る。既定は project.yml の dev.nijizo.markpanther.dev
OFFICIAL_BUNDLE_ID := dev.nijizo.markpanther
BUNDLE_FLAGS   ?=

SIGN_FLAGS = $(BUNDLE_FLAGS) CODE_SIGN_IDENTITY="$(SIGN_ID)" CODE_SIGN_STYLE=Manual \
             DEVELOPMENT_TEAM=$(TEAM_ID) ENABLE_HARDENED_RUNTIME=$(HARDENED) \
             CODE_SIGN_INJECT_BASE_ENTITLEMENTS=$(INJECT_DEBUG_ENTITLEMENTS) \
             OTHER_CODE_SIGN_FLAGS="$(TIMESTAMP)"

.PHONY: project build release signed notarize dist publish install install-signed \
        test test-core test-web test-ui vendor run clean check-signing

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug -derivedDataPath $(BUILD) build -quiet

release: project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release -derivedDataPath $(BUILD) build -quiet \
		$(SIGN_FLAGS)

# 配布用のビルド。公証には hardened runtime が要る。
# 入れ子の .appex は xcodebuild が各自の entitlements で署名する。あとから --deep で署名し直さないこと
# （--deep は appex に entitlements を渡さないので、サンドボックス無しと見なされて PlugInKit に弾かれる）。
check-signing:
	@test -n "$(TEAM_ID)" -a -n "$(NOTARY_PROFILE)" || { \
		echo "TEAM_ID / NOTARY_PROFILE が未設定。private/Signing.local.mk を置くか、make に TEAM_ID=... NOTARY_PROFILE=... を渡す"; \
		exit 1; }

signed: check-signing
	@# 署名の設定だけ変えても、前回のままで最新と見なされた .appex は署名し直されない。
	@# 配布物では中身と署名が食い違うと公証が落ちるので、毎回捨てて作り直す。
	rm -rf $(BUILD)/Build/Products/Release
	$(MAKE) release SIGN_ID="Developer ID Application" HARDENED=YES \
		TIMESTAMP=--timestamp INJECT_DEBUG_ENTITLEMENTS=NO \
		BUNDLE_FLAGS=MP_BUNDLE_ID=$(OFFICIAL_BUNDLE_ID)

# 公証して、結果をアプリに綴じ込む（オフラインでも Gatekeeper が通るように）。
# 初回だけ認証情報を登録する:
#   xcrun notarytool store-credentials $(NOTARY_PROFILE) \
#     --apple-id <Apple ID> --team-id $(TEAM_ID) --password <App 用パスワード>
notarize: signed
	rm -rf $(DIST)
	mkdir -p $(DIST)
	ditto -c -k --keepParent $(BUILD)/Build/Products/Release/$(APP).app $(DIST)/$(APP)-submit.zip
	xcrun notarytool submit $(DIST)/$(APP)-submit.zip --keychain-profile $(NOTARY_PROFILE) --wait \
		| tee $(DIST)/notary.log
	@# notarytool は Invalid でも終了コード 0 で返る。自分で見て止める
	@grep -q "status: Accepted" $(DIST)/notary.log || { \
		echo ""; echo "公証が通りませんでした。理由:"; \
		xcrun notarytool log $$(sed -n 's/^  id: //p' $(DIST)/notary.log | head -1) \
			--keychain-profile $(NOTARY_PROFILE); \
		exit 1; }
	xcrun stapler staple $(BUILD)/Build/Products/Release/$(APP).app

# 配布物をつくる。spctl で「配ったら実際に開けるか」を最後に確かめる。
dist: notarize
	ditto -c -k --keepParent $(BUILD)/Build/Products/Release/$(APP).app $(DIST)/$(APP).zip
	spctl -a -vvv $(BUILD)/Build/Products/Release/$(APP).app
	@echo "配布用: $(DIST)/$(APP).zip"

# GitHub Releases に出す。版は project.yml の MARKETING_VERSION、本文は CHANGELOG.md の同じ版の節。
#   make publish            … 署名 → 公証 → zip → タグを push → Release 作成
#   make publish DRY_RUN=1  … 何も作らず、版・タグ・Release 本文だけ見る
publish:
	scripts/publish.sh

test: test-core test-web

test-core:
	swift test --package-path $(CORE)

test-web:
	cd web && bun test

test-ui: project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -derivedDataPath $(BUILD) test -quiet

vendor:
	cd web && bun install --frozen-lockfile && bun run vendor

run: build
	open $(BUILD)/Build/Products/Debug/$(APP).app

# 手元の /Applications にも Developer ID 署名で入れたいとき（通知など、署名の身元が要る機能の確認用）
install-signed:
	$(MAKE) install SIGN_ID="Developer ID Application" HARDENED=YES \
		BUNDLE_FLAGS=MP_BUNDLE_ID=$(OFFICIAL_BUNDLE_ID)

install: release
	rm -rf /Applications/$(APP).app
	cp -R $(BUILD)/Build/Products/Release/$(APP).app /Applications/
	mkdir -p $(BIN_DIR)
	install -m 755 scripts/markp $(BIN_DIR)/markp

clean:
	rm -rf $(BUILD) $(CORE)/.build $(CORE)/.build-*
