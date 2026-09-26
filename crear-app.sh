#!/bin/zsh
# Compila LimpiadorMac y la empaqueta como LimpiadorMac.app
set -e
cd "$(dirname "$0")"

echo "→ Compilando…"
swift build -c release

APP="LimpiadorMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LimpiadorMac "$APP/Contents/MacOS/"
cp Recursos/Info.plist "$APP/Contents/"

echo "→ Creando ícono…"
TMP=$(mktemp -d)
swift Recursos/icono.swift "$TMP/icono.png"
mkdir "$TMP/AppIcon.iconset"
for t in 16 32 128 256 512; do
  sips -z $t $t "$TMP/icono.png" --out "$TMP/AppIcon.iconset/icon_${t}x${t}.png" >/dev/null
  sips -z $((t*2)) $((t*2)) "$TMP/icono.png" --out "$TMP/AppIcon.iconset/icon_${t}x${t}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$TMP"

echo "→ Firmando…"
codesign --force --deep --sign - "$APP"

echo "✓ Listo: $(pwd)/$APP"
