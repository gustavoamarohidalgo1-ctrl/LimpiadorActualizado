# LimpiadorMac

App nativa para macOS (SwiftUI) que analiza a fondo el disco, encuentra lo que ocupa espacio sin necesidad y **avisa de lo que no conviene borrar**. Hecha para un MacBook Air M2 con el disco casi lleno.

No borra nada sin confirmación. Cada elemento explica qué es, qué contiene, por qué es (o no) seguro borrarlo y qué pasa si lo borras.

## Qué encuentra

| Categoría | Ejemplos |
|---|---|
| Emuladores | Emuladores de Android (completos o «restablecer» sin borrarlos), imágenes del sistema que no usa ningún emulador, plataformas, build-tools y NDK que no usa ningún proyecto (leído de sus `build.gradle`), sistemas iOS para simuladores sin usar |
| Cachés de desarrollo | Gradle (por versión y según lo que usa cada proyecto), npm, Xcode, CocoaPods, pip, Playwright, Deno, Dart, versiones viejas de Homebrew, paquetes de conda; en VS Code, Cursor y Windsurf: extensiones que ya no están instaladas, cachés de versiones anteriores y datos de proyectos que ya no existen |
| Cachés de aplicaciones | Cachés de apps, las cachés internas de apps Electron/Chromium y los adjuntos abiertos desde Mail |
| Temporales del sistema | Temporales y cachés que macOS guarda para tu usuario en `/var/folders` (compilador, apps…), solo lo que ningún programa tiene abierto |
| Restos de apps borradas | Datos, cachés, registros, contenedores y agentes de inicio de apps desinstaladas, agrupados por app |
| Compilaciones | `build`, `node_modules`, `.gradle`, `Pods`… agrupados por proyecto, con la fecha del último commit |
| Carpetas ocultas | Separa las cachés de una herramienta de su historial y configuración |
| Instaladores | `.dmg`, `.pkg`, `.apk`…, firmware de iPhone (`.ipsw`) e instaladores de macOS, indicando si la app ya está instalada y en qué versión |
| Duplicados | Archivos idénticos (SHA-256), descartando clones de APFS que no ocupan espacio extra |
| Archivos grandes | Más de 100 MB en tus carpetas y los más pesados escondidos en `~/Library` |

## Exactitud

- **A quién pertenece cada carpeta**: además del nombre, lee la firma de código de cada app instalada (Team ID, App Groups y las extensiones y ayudantes que lleva dentro). Así reconoce contenedores como `UBF8T346G9.Office` (Outlook) o `group.net.whatsapp.WhatsApp.shared` (WhatsApp) y no los confunde con restos.
- **Espacio real**: antes de limpiar calcula cuánto se libera de verdad. APFS dice qué parte de cada archivo comparte con clones o instantáneas de Time Machine, y los enlaces duros solo cuentan si se borran todos sus nombres.
- **Lo que usan tus proyectos**: las versiones del SDK de Android, de Gradle y de las extensiones de VS Code se comparan con lo que piden tus proyectos y editores, no con «la más nueva».
- **Si no puede saberlo, no lo ofrece**: si no puede leer la lista de simuladores, qué archivos están abiertos o la lista de extensiones, no propone borrar lo que dependa de eso.

## Seguridad

- **Evaluador de riesgo**: sube a *Cuidado* lo que contiene keystores de Android, claves o contraseñas, repositorios git, documentos o fotos, apps compiladas para publicar, respaldos o cosas en la nube.
- **En uso**: detecta apps abiertas, emuladores encendidos, Gradle trabajando y archivos abiertos; lo que esté en uso se salta al limpiar.
- **Rutas protegidas**: nunca toca la carpeta personal, `Library`, llaveros, `.ssh`, `.git` ni llaves de firma, aunque se seleccionen. Fuera de tu carpeta solo puede borrar lo que hay dentro de tus temporales de `/var/folders`, versiones viejas de Homebrew e instaladores de macOS.
- **Duplicados**: nunca borra la última copia, aunque marques todas.
- **Deshacer**: lo que va a la Papelera se puede devolver a su sitio con un clic, también de limpiezas anteriores. Lo marcado como *Revisar* o *Cuidado* siempre va a la Papelera.
- **Lo irreversible se avisa**: vaciar un simulador, eliminar un sistema iOS o vaciar la Papelera no se puede deshacer, y la confirmación lo dice. Si vacías la Papelera en la misma limpieza, se hace al final y solo con lo que ya estaba en ella.
- **Historial** de todo lo borrado en `~/Library/Logs/LimpiadorMac/historial.log`.
- Ninguna acción que borra responde a la tecla Enter: hay que hacer clic.

## Cómo funciona

1. `Indice`: recorre en paralelo con `fts` la carpeta personal, `/Users/Shared` y tus temporales de `/var/folders` (unos 3 s para más de 500 000 archivos) y guarda, para cada carpeta, su tamaño real, su última actividad y qué contiene.
2. `AppsInstaladas`: qué apps hay, sus versiones y su firma de código.
3. `Escaner`: cada categoría consulta el índice.
4. `Evaluador`: aplica las reglas de seguridad y explica cada decisión.
5. `EspacioReal`: calcula lo que se libera de verdad.
6. `Limpiador` e `Historial`: borran con comprobaciones de último momento y permiten deshacer.

## Compilar

Requisitos: macOS 14 o superior y Xcode (Swift 5.10+).

```bash
./crear-app.sh
```

Crea `LimpiadorMac.app` en la carpeta del proyecto.

Para ver el análisis en la terminal, sin abrir ventanas y sin borrar nada:

```bash
.build/release/LimpiadorMac --diagnostico --motivos
```

Para un análisis completo, dale a la app **Acceso total al disco** en Ajustes del Sistema › Privacidad y seguridad.

## Pruebas

```bash
swift test
```

Para probar el análisis sin tocar tu carpeta personal, crea una carpeta de prueba con basura simulada y analízala:

```bash
./scripts/carpeta-de-prueba.sh /tmp/casa
LIMPIADORMAC_HOME=/tmp/casa .build/release/LimpiadorMac --diagnostico --motivos
```

GitHub Actions compila, ejecuta los tests y este diagnóstico en macOS en cada cambio.
