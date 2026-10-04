#!/bin/bash
# Crea una carpeta personal de prueba con «basura» representativa.
# Sirve para probar el análisis sin tocar nada real:
#   ./scripts/carpeta-de-prueba.sh /tmp/casa
#   LIMPIADORMAC_HOME=/tmp/casa .build/release/LimpiadorMac --diagnostico --motivos
set -euo pipefail
CASA="${1:?Uso: carpeta-de-prueba.sh <carpeta>}"
rm -rf "$CASA"
mkdir -p "$CASA"
cd "$CASA"

# archivo <ruta> <MB>: contenido aleatorio para que ocupe espacio real.
archivo() {
  mkdir -p "$(dirname "$1")"
  dd if=/dev/urandom of="$1" bs=1048576 count="$2" 2>/dev/null
}
viejo() { touch -t 202401010000 "$@"; }

# Cachés y restos de una app que ya no está instalada.
archivo "Library/Caches/com.ejemplo.Fantasma/cache.db" 2
archivo "Library/Application Support/AppFantasma/datos.bin" 3
viejo "Library/Application Support/AppFantasma/datos.bin"

# Cachés de desarrollo.
archivo ".npm/_cacache/content-v2/sha512/aa/paquete" 2
archivo ".npm/_logs/2024-01-01T00_00_00_000Z-debug-0.log" 2
archivo ".nvm/.cache/bin/node-v18.0.0-darwin-arm64.tar.xz" 2
archivo "Library/Developer/Xcode/DerivedData/Proyecto-abcdefghijkl/Build/objeto.o" 2
archivo "Library/Developer/Xcode/DocumentationCache/v1/indice.bin" 2
archivo ".gradle/native/1.0/libnativo.dylib" 2

# Proyectos con carpetas regenerables.
mkdir -p "Proyectos/web"
echo '{"name":"web"}' > "Proyectos/web/package.json"
archivo "Proyectos/web/node_modules/lib/index.js" 2
archivo "Proyectos/web/build/app.js" 2
viejo "Proyectos/web/package.json"

# Proyecto de electron-builder: su build/ son recursos, no compilación.
mkdir -p "Proyectos/escritorio/build"
echo '{"name":"escritorio","build":{"appId":"com.ejemplo.escritorio"}}' > "Proyectos/escritorio/package.json"
archivo "Proyectos/escritorio/build/icon.icns" 2

# Instaladores y duplicados.
archivo "Downloads/Instalador-1.2.dmg" 2
viejo "Downloads/Instalador-1.2.dmg"
archivo "Pictures/vacaciones.jpg" 2
mkdir -p "Downloads" "Documents"
cat "Pictures/vacaciones.jpg" > "Downloads/vacaciones.jpg"
cp -c "Pictures/vacaciones.jpg" "Documents/clon-de-vacaciones.jpg" 2>/dev/null || true

# VS Code: una extensión vieja y datos de un proyecto que ya no existe.
mkdir -p ".vscode/extensions"
archivo ".vscode/extensions/ejemplo.extension-1.0.0/extension.js" 2
archivo ".vscode/extensions/ejemplo.extension-2.0.0/extension.js" 2
cat > ".vscode/extensions/extensions.json" <<'JSON'
[{"identifier":{"id":"ejemplo.extension"},"version":"2.0.0","relativeLocation":"ejemplo.extension-2.0.0"}]
JSON
ESPACIO="Library/Application Support/Code/User/workspaceStorage/0123456789abcdef"
mkdir -p "$ESPACIO"
echo '{"folder":"file:///Users/nadie/proyecto-borrado"}' > "$ESPACIO/workspace.json"
archivo "$ESPACIO/state.vscdb" 2
viejo "$ESPACIO/state.vscdb" "$ESPACIO/workspace.json"
archivo "Library/Application Support/Code/CachedData/aaaa1111/cache.bin" 2
viejo "Library/Application Support/Code/CachedData/aaaa1111/cache.bin" "Library/Application Support/Code/CachedData/aaaa1111"
archivo "Library/Application Support/Code/CachedData/bbbb2222/cache.bin" 2

# Firmware de iPhone ya descargado.
archivo "Library/iTunes/iPhone Software Updates/iPhone_Restore.ipsw" 2

# Algo en la Papelera.
archivo ".Trash/viejo.zip" 2

# Una carpeta oculta con un keystore: tiene que salir como «Cuidado».
archivo ".herramienta-vieja/datos.bin" 2
archivo ".herramienta-vieja/firma.jks" 1
viejo ".herramienta-vieja/datos.bin" ".herramienta-vieja/firma.jks"

echo "Carpeta de prueba lista en $CASA"
du -sh "$CASA"
