#!/usr/bin/env bash
# Собирает «Расписание уроков» для трёх платформ прямо на Linux — без Android SDK,
# Xcode и Windows:
#   release/Raspisanie.apk  — Android 7+ (подписанный APK)
#   release/Raspisanie.exe  — Windows 10/11 x64 (один файл, WebView2)
#   release/Raspisanie.ipa  — iOS 14+ (ad-hoc подпись, для AltStore/Sideloadly/ESign/TrollStore)
#
# Нужны только: bash, node + npm, python3, git, openssl. Всё остальное скачивается в $TOOLS:
#   ziglang (PyPI)        — кросс-компилятор C/C++/Objective-C для Windows и iOS
#   jdk4py  (PyPI)        — Java для apktool/apksigner
#   @postar/apktool-node  — apktool (aapt2 + smali) и apksigner
#   sharp (npm)           — иконки
#   webview/webview, WebView2.h, theos/sdks (iPhoneOS SDK) — с GitHub
#
# Использование: standalone/build.sh [apk|exe|ipa ...]   (по умолчанию — всё)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SA="$ROOT/standalone"
TOOLS="${TOOLS:-/tmp/raspisanie-tools}"
BUILD="${BUILD:-/tmp/raspisanie-build}"
OUT="$ROOT/release"
VERSION="$(node -p "require('$ROOT/package.json').version")"
BUNDLE_ID="com.hardst1ly.schedule"
IOS_SDK_VERSION="16.5"

TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(apk exe ipa)
want() { local t; for t in "${TARGETS[@]}"; do [ "$t" = "$1" ] && return 0; done; return 1; }
log() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

mkdir -p "$TOOLS" "$BUILD" "$OUT"

# ---------------------------------------------------------------- tools
log "Инструменты ($TOOLS)"
if [ ! -x "$TOOLS/venv/bin/python" ]; then
  python3 -m venv "$TOOLS/venv"
fi
"$TOOLS/venv/bin/pip" install -q --disable-pip-version-check ziglang jdk4py
PY="$TOOLS/venv/bin/python"
ZIG=("$PY" -m ziglang)
JAVA="$("$PY" -c 'import jdk4py; print(jdk4py.JAVA)')"

if [ ! -d "$TOOLS/node/node_modules/sharp" ] || [ ! -d "$TOOLS/node/node_modules/@postar/apktool-node" ]; then
  mkdir -p "$TOOLS/node"
  (cd "$TOOLS/node" && [ -f package.json ] || npm init -y >/dev/null)
  (cd "$TOOLS/node" && npm install --no-audit --no-fund --silent sharp @postar/apktool-node)
fi
APKTOOL="$TOOLS/node/node_modules/@postar/apktool-node/lib/apktool.jar"
APKSIGNER="$TOOLS/node/node_modules/@postar/apktool-node/lib/apksigner.jar"
export SHARP_PATH="$TOOLS/node/node_modules/sharp"

# ---------------------------------------------------------------- resources
log "Ресурсы (встроенный HTML, иконки)"
node "$SA/gen-resources.mjs" "$BUILD/res"

# ---------------------------------------------------------------- APK
if want apk; then
  log "Android: сборка APK"
  rm -rf "$BUILD/apk" && mkdir -p "$BUILD/apk"
  cp -r "$SA/android" "$BUILD/apk/src"
  mkdir -p "$BUILD/apk/src/assets"
  cp -r "$ROOT/www/." "$BUILD/apk/src/assets/"
  sed -i "s/^  versionName: .*/  versionName: $VERSION/" "$BUILD/apk/src/apktool.yml"
  "$JAVA" -jar "$APKTOOL" b "$BUILD/apk/src" -o "$BUILD/apk/built.apk"
  python3 "$SA/android/zipalign.py" "$BUILD/apk/built.apk" "$BUILD/apk/unsigned.apk"
  "$JAVA" --enable-native-access=ALL-UNNAMED -jar "$APKSIGNER" sign \
    --ks "$ROOT/android/app/schedule-release.p12" --ks-type PKCS12 \
    --ks-pass pass:raspisanie --ks-key-alias schedule \
    --min-sdk-version 24 \
    --out "$OUT/Raspisanie.apk" "$BUILD/apk/unsigned.apk"
  "$JAVA" --enable-native-access=ALL-UNNAMED -jar "$APKSIGNER" verify --min-sdk-version 24 --verbose "$OUT/Raspisanie.apk" | grep -E "Verif"
  rm -f "$OUT/Raspisanie.apk.idsig"
fi

# ---------------------------------------------------------------- EXE
if want exe; then
  log "Windows: сборка EXE"
  [ -d "$TOOLS/webview" ] || git clone -q --depth 1 https://github.com/webview/webview.git "$TOOLS/webview"
  mkdir -p "$TOOLS/wv2"
  if [ ! -s "$TOOLS/wv2/WebView2.h" ]; then
    # WebView2.h из NuGet-пакета Microsoft.Web.WebView2 (копия в репозитории arturo-lang)
    if command -v gh >/dev/null; then
      gh api -H "Accept: application/vnd.github.raw" \
        "repos/arturo-lang/arturo/contents/src/extras/webview/deps/include/WebView2.h" > "$TOOLS/wv2/WebView2.h"
    else
      git clone -q --depth 1 --filter=blob:none --sparse https://github.com/arturo-lang/arturo.git "$TOOLS/arturo"
      (cd "$TOOLS/arturo" && git sparse-checkout set src/extras/webview/deps/include)
      cp "$TOOLS/arturo/src/extras/webview/deps/include/WebView2.h" "$TOOLS/wv2/"
    fi
  fi
  # В MinGW-заголовках Zig нет EventToken.h — нужна одна структура
  cat > "$TOOLS/wv2/EventToken.h" <<'EOF'
#pragma once
#ifndef __eventtoken_h__
#define __eventtoken_h__
typedef struct EventRegistrationToken { __int64 value; } EventRegistrationToken;
#endif
EOF
  W="$BUILD/exe"; rm -rf "$W" && mkdir -p "$W"
  cp "$SA/windows/app.rc" "$SA/windows/app.manifest" "$BUILD/res/app.ico" "$W/"
  (cd "$W" && "${ZIG[@]}" c++ -target x86_64-windows-gnu -O2 -std=c++17 -DNDEBUG -w \
      -I"$TOOLS/webview/core/include" -I"$TOOLS/wv2" -I"$BUILD/res" \
      "$SA/windows/main.cc" app.rc -o Raspisanie.exe \
      -Wl,--subsystem,windows \
      -lole32 -lshell32 -lshlwapi -luser32 -lversion -ladvapi32 -lgdi32)
  cp "$W/Raspisanie.exe" "$OUT/Raspisanie.exe"
fi

# ---------------------------------------------------------------- IPA
if want ipa; then
  log "iOS: сборка IPA"
  SDK="$TOOLS/sdks/iPhoneOS$IOS_SDK_VERSION.sdk"
  if [ ! -d "$SDK/System" ]; then
    rm -rf "$TOOLS/sdks"
    git clone -q --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks.git "$TOOLS/sdks"
    (cd "$TOOLS/sdks" && git sparse-checkout set "iPhoneOS$IOS_SDK_VERSION.sdk")
  fi
  I="$BUILD/ipa"; rm -rf "$I" && mkdir -p "$I/Payload/Raspisanie.app/www"
  APP="$I/Payload/Raspisanie.app"
  "${ZIG[@]}" cc -target aarch64-ios.14.0 --sysroot "$SDK" \
    -isystem "$SDK/usr/include" -iframework "$SDK/System/Library/Frameworks" \
    -F"$SDK/System/Library/Frameworks" -L/usr/lib \
    -fobjc-arc -O2 -x objective-c "$SA/ios/main.m" -o "$APP/Raspisanie" \
    -framework UIKit -framework WebKit -framework Foundation -framework CoreGraphics -lobjc \
    -Wl,-headerpad_max_install_names
  cp -r "$ROOT/www/." "$APP/www/"
  sed -e "s/@VERSION@/$VERSION/g" -e "s/@SDK@/$IOS_SDK_VERSION/g" "$SA/ios/Info.plist" > "$APP/Info.plist"
  printf 'APPL????' > "$APP/PkgInfo"
  node --input-type=module -e "
    import { createRequire } from 'module';
    const sharp = createRequire(import.meta.url)(process.env.SHARP_PATH);
    const src = '$ROOT/assets/icon.png', dir = '$APP';
    const icons = { 'AppIcon60x60@2x.png': 120, 'AppIcon60x60@3x.png': 180, 'AppIcon76x76~ipad.png': 76,
                    'AppIcon76x76@2x~ipad.png': 152, 'AppIcon83.5x83.5@2x~ipad.png': 167 };
    for (const [name, s] of Object.entries(icons))
      await sharp(src).resize(s, s).flatten({ background: '#4f46e5' }).removeAlpha().png().toFile(dir + '/' + name);
  "
  "$PY" "$SA/ios/adhoc_sign.py" "$APP/Raspisanie" "$BUNDLE_ID" "$APP/Info.plist"
  rm -f "$OUT/Raspisanie.ipa"
  (cd "$I" && zip -qry "$OUT/Raspisanie.ipa" Payload)
fi

log "Готово"
ls -la "$OUT"
