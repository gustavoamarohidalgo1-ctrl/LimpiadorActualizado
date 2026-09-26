# LimpiadorMac

App nativa para macOS (SwiftUI) que analiza a fondo el disco, encuentra lo que ocupa espacio sin necesidad y **avisa de lo que no conviene borrar**. Hecha para un MacBook Air M2 con el disco casi lleno.

No borra nada sin confirmación. Cada elemento explica qué es, qué contiene, por qué es (o no) seguro borrarlo y qué pasa si lo borras.

## Qué encuentra

| Categoría | Ejemplos |
|---|---|
| Emuladores | Emuladores de Android (completos o «restablecer» sin borrarlos), imágenes del sistema que no usa ningún emulador, sistemas iOS para simuladores sin usar |
| Cachés de desarrollo | Gradle (por versión y según lo que usa cada proyecto), npm, Xcode DerivedData, CocoaPods, pip, Playwright… |
| Cachés de aplicaciones | Cachés de apps y las cachés internas de apps Electron/Chromium |
| Restos de apps borradas | Datos, cachés, registros y agentes de inicio de apps desinstaladas, agrupados por app |
| Compilaciones | `build`, `node_modules`, `.gradle`, `Pods`… agrupados por proyecto, con la fecha del último commit |
| Carpetas ocultas | Separa las cachés de una herramienta de su historial y configuración |
| Instaladores | `.dmg`, `.pkg`, `.apk`… indicando si la app ya está instalada o si hay una versión más nueva |
| Duplicados | Archivos idénticos (SHA-256), descartando clones de APFS que no ocupan espacio extra |
| Archivos grandes | Más de 100 MB en tus carpetas y los más pesados escondidos en `~/Library` |

## Seguridad

- **Evaluador de riesgo**: sube a *Cuidado* lo que contiene keystores de Android, claves o contraseñas, repositorios git, documentos o fotos, apps compiladas para publicar, respaldos o cosas en la nube.
- **En uso**: detecta apps abiertas, emuladores encendidos y Gradle trabajando; lo que esté en uso se salta al limpiar.
- **Rutas protegidas**: nunca toca la carpeta personal, `Library`, llaveros, `.ssh`, `.git` ni llaves de firma, aunque se seleccionen.
- **Deshacer**: lo que va a la Papelera se puede devolver a su sitio con un clic. Lo marcado como *Revisar* o *Cuidado* siempre va a la Papelera.
- **Historial** de todo lo borrado en `~/Library/Logs/LimpiadorMac/historial.log`.
- Ninguna acción que borra responde a la tecla Enter: hay que hacer clic.

## Cómo funciona

1. `Indice`: recorre la carpeta personal en paralelo con `fts` (unos 3 s para más de 500 000 archivos) y guarda, para cada carpeta, su tamaño real, su última actividad y qué contiene.
2. `Escaner`: cada categoría consulta el índice.
3. `Evaluador`: aplica las reglas de seguridad y explica cada decisión.
4. `Limpiador` e `Historial`: borran con comprobaciones de último momento y permiten deshacer.

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
