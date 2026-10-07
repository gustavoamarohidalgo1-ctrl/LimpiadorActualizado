import Foundation

// Reglas del área «navegadores»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// Navegadores: lo que guardan fuera de ~/Library/Caches.
extension Catalogo {
    static let navegadores: [Regla] = [
        Regla("chrome-modelo-ia-gemini-nano", "~/Library/Application Support/Google/Chrome */OptGuideOnDeviceModel",
              nombre: "Modelo de IA de Chrome Beta, Dev o Canary",
              detalle: "Modelo de inteligencia artificial (Gemini Nano) que las versiones de prueba de Chrome descargan por su cuenta para funciones como «Ayúdame a escribir». Suele ocupar entre 2 y 4 GB.",
              consecuencia: "No pierdes nada tuyo. Chrome solo lo vuelve a descargar si tienes unos 20 GB libres (y lo borra solo si te quedan menos de 5 GB). Si no quieres que vuelva, desactiva «IA en el dispositivo» en Chrome › Configuración › Sistema.")
            .sinPreseleccion().soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"),
        Regla("chrome-modelos-ia-manifiesto", "~/Library/Application Support/Google/*/OptGuideManifestModel",
              nombre: "Otros modelos de IA de Chrome",
              detalle: "Modelos de inteligencia artificial que Chrome descarga en segundo plano (incluidas versiones nuevas de Gemini Nano). Pueden ocupar varios GB.",
              consecuencia: "Tus datos no se tocan. Chrome los vuelve a descargar si una función los necesita y tienes unos 20 GB libres.")
            .sinPreseleccion().soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.google.chrome.for.testing"),
        Regla("chrome-screen-ai", "~/Library/Application Support/Google/*/screen_ai",
              nombre: "Reconocimiento de texto de Chrome",
              detalle: "Componente que Chrome descarga para leer el texto de los PDF escaneados y del modo lectura.",
              consecuencia: "Chrome lo vuelve a descargar la próxima vez que lo necesite. Tus datos no se tocan.")
            .soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.google.chrome.for.testing"),
        Regla("chrome-traductor-sin-conexion", "~/Library/Application Support/Google/*/TranslateKit",
              nombre: "Traductor sin conexión de Chrome",
              detalle: "Motor y paquetes de idiomas que Chrome descarga para traducir sin internet.",
              consecuencia: "Si vuelves a traducir sin conexión, Chrome descarga de nuevo lo que necesite. Tus datos no se tocan.")
            .soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.google.chrome.for.testing"),
        Regla("chrome-subtitulos-motor", "~/Library/Application Support/Google/*/SODA",
              nombre: "Motor de subtítulos automáticos de Chrome",
              detalle: "Programa de reconocimiento de voz que usan los «Subtítulos automáticos» de Chrome.",
              consecuencia: "Si usas los subtítulos automáticos, Chrome lo vuelve a descargar al activarlos (tarda unos minutos).")
            .sinPreseleccion().soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.google.chrome.for.testing"),
        Regla("chrome-subtitulos-idiomas", "~/Library/Application Support/Google/*/SODALanguagePacks",
              nombre: "Idiomas de subtítulos automáticos de Chrome",
              detalle: "Paquetes de idioma para los subtítulos automáticos de Chrome (cada uno ocupa decenas de MB).",
              consecuencia: "Si vuelves a usar los subtítulos automáticos en ese idioma, Chrome lo descarga otra vez.")
            .sinPreseleccion().soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.google.chrome.for.testing"),
        Regla("chrome-modelo-busqueda-historial", "~/Library/Application Support/Google/*/AIEmbeddings",
              nombre: "Modelo de búsqueda inteligente del historial de Chrome",
              detalle: "Modelo que Chrome usa para buscar en tu historial escribiendo con tus propias palabras.",
              consecuencia: "Tu historial no se toca. Si la función está activa, Chrome vuelve a descargar el modelo.")
            .soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.google.chrome.for.testing"),
        Regla("chrome-voces-lectura", "~/Library/Application Support/Google/*/WasmTtsEngine",
              nombre: "Voces de «Leer en voz alta» de Chrome",
              detalle: "Motor de voz que Chrome descarga para leer páginas en voz alta en el modo lectura.",
              consecuencia: "Chrome lo vuelve a descargar si usas la lectura en voz alta.")
            .soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.google.chrome.for.testing"),
        Regla("chrome-listas-navegacion-segura", "~/Library/Application Support/Google/*/Safe Browsing",
              nombre: "Listas de Navegación segura de Chrome",
              detalle: "Copia local de las listas de sitios peligrosos que Chrome descarga de Google.",
              consecuencia: "Chrome las vuelve a descargar al abrirse. Mientras tanto, la protección contra sitios peligrosos depende de la comprobación en línea.")
            .sinPreseleccion().soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.google.chrome.for.testing"),
        Regla("chrome-metricas-uso", "~/Library/Application Support/Google/*/BrowserMetrics",
              nombre: "Estadísticas de uso de Chrome",
              detalle: "Archivos de estadísticas que Chrome guarda antes de enviarlos a Google.",
              consecuencia: "Nada: Chrome crea archivos nuevos al abrirse.")
            .en(.registros).soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.google.chrome.for.testing"),
        Regla("chrome-metricas-diferidas", "~/Library/Application Support/Google/*/DeferredBrowserMetrics",
              nombre: "Estadísticas pendientes de Chrome",
              detalle: "Estadísticas de uso que Chrome guardó para enviar más tarde.",
              consecuencia: "Nada: solo son estadísticas.")
            .en(.registros).soloSiEstaInstalada().app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.google.chrome.for.testing"),
        Regla("google-updater-paquetes", "~/Library/Application Support/Google/GoogleUpdater/crx_cache",
              nombre: "Actualizaciones descargadas de Chrome",
              detalle: "Paquetes de actualización de Chrome que el actualizador de Google guarda después de instalarlos.",
              consecuencia: "Nada: Chrome ya está actualizado. La próxima actualización puede descargar el paquete completo en vez de solo los cambios.")
            .en(.instaladores).proceso("Google Updater", patron: "/googleupdater.app/contents/macos/googleupdater"),
        Regla("google-updater-paquetes-sistema", "/Library/Application Support/Google/GoogleUpdater/crx_cache",
              nombre: "Actualizaciones descargadas de Chrome (para todos los usuarios)",
              detalle: "Paquetes de actualización que el actualizador de Google guarda cuando Chrome está instalado para todo el Mac.",
              consecuencia: "Nada: Chrome ya está actualizado. La próxima actualización puede tardar un poco más en descargarse.")
            .admin().sinPreseleccion().proceso("Google Updater", patron: "/googleupdater.app/contents/macos/googleupdater"),
        Regla("edge-updater-versiones-guardadas", "~/Library/Application Support/Microsoft/EdgeUpdater/apps/msedge-stable/[0-9]*",
              nombre: "Copias viejas de Microsoft Edge del actualizador",
              detalle: "Copias completas de Microsoft Edge (casi 1 GB cada una) que su actualizador descargó y no borró después de instalar.",
              consecuencia: "Nada: Edge sigue funcionando con su versión actual. Se conserva la copia más nueva por si es una actualización pendiente.")
            .en(.instaladores).conservando(.versionMasAlta).edad(dias: 1).app("Microsoft Edge", "com.microsoft.edgemac"),
        Regla("edge-updater-versiones-sistema", "/Library/Application Support/Microsoft/EdgeUpdater/apps/msedge-stable/[0-9]*",
              nombre: "Copias viejas de Microsoft Edge (para todos los usuarios)",
              detalle: "Copias completas de Microsoft Edge que el actualizador de todo el Mac descargó y no borró después de instalar.",
              consecuencia: "Nada: Edge sigue funcionando con su versión actual. Se conserva la copia más nueva por si es una actualización pendiente.")
            .admin().sinPreseleccion().conservando(.versionMasAlta).edad(dias: 1).app("Microsoft Edge", "com.microsoft.edgemac"),
        Regla("brave-modelos-ia-locales", "~/Library/Application Support/BraveSoftware/*/BraveLocalAIModels",
              nombre: "Modelos de IA locales de Brave",
              detalle: "Modelos que Brave descarga para sus funciones de IA en el dispositivo (Leo, búsqueda en el historial).",
              consecuencia: "Brave los vuelve a descargar si la IA local sigue activada. Tus datos no se tocan.")
            .soloSiEstaInstalada().app("Brave Browser", "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly"),
        Regla("firefox-almacenamiento-por-borrar", "~/Library/Application Support/Firefox/Profiles/*/storage/to-be-removed",
              nombre: "Datos web que Firefox iba a borrar",
              detalle: "Datos de sitios web que Firefox ya marcó para eliminar y no terminó de borrar.",
              consecuencia: "Nada: Firefox ya los había descartado.")
            .soloSiEstaInstalada().app("Firefox", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"),
        Regla("firefox-restos-ventanas-privadas", "~/Library/Application Support/Firefox/Profiles/*/storage/private",
              nombre: "Restos de ventanas privadas de Firefox",
              detalle: "Datos de navegación privada que debían borrarse al cerrar Firefox y se quedaron (por ejemplo, tras un cierre inesperado).",
              consecuencia: "Nada: Firefox los borraría igualmente al abrirse o al salir.")
            .soloSiEstaInstalada().app("Firefox", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"),
        Regla("firefox-telemetria-archivada", "~/Library/Application Support/Firefox/Profiles/*/datareporting/archived",
              nombre: "Informes de uso archivados de Firefox",
              detalle: "Copias de los informes de uso que Firefox ya envió (hasta 120 MB).",
              consecuencia: "Nada: ya se enviaron. Solo dejarás de verlos en about:telemetry.")
            .en(.registros).soloSiEstaInstalada().app("Firefox", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"),
        Regla("firefox-telemetria-pendiente", "~/Library/Application Support/Firefox/Profiles/*/saved-telemetry-pings",
              nombre: "Informes de uso pendientes de Firefox",
              detalle: "Informes de uso que Firefox todavía no envió.",
              consecuencia: "Nada: solo no se enviarán esos informes.")
            .en(.registros).soloSiEstaInstalada().app("Firefox", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"),
        Regla("firefox-volcados-fallos-perfil", "~/Library/Application Support/Firefox/Profiles/*/minidumps",
              nombre: "Volcados de fallos de Firefox",
              detalle: "Archivos que Firefox guarda cuando una pestaña o el navegador se cuelga.",
              consecuencia: "Nada: solo dejarás de poder enviar esos informes de fallos.")
            .en(.registros).soloSiEstaInstalada().app("Firefox", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"),
        Regla("firefox-cache-perfil-externo", "~/Library/Application Support/Firefox/Profiles/*/cache2",
              nombre: "Caché web de Firefox (dentro del perfil)",
              detalle: "Caché de páginas e imágenes que Firefox guarda dentro del perfil cuando este se creó en una ubicación propia.",
              consecuencia: "Firefox la vuelve a crear mientras navegas. Tus marcadores, contraseñas e historial no se tocan.")
            .soloSiEstaInstalada().app("Firefox", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"),
        Regla("firefox-cache-arranque-perfil", "~/Library/Application Support/Firefox/Profiles/*/startupCache",
              nombre: "Caché de arranque de Firefox (dentro del perfil)",
              detalle: "Código precompilado que Firefox usa para abrirse más rápido.",
              consecuencia: "La próxima vez Firefox tardará un poco más en abrirse. Tus datos no se tocan.")
            .soloSiEstaInstalada().app("Firefox", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"),
        Regla("webkit-cache-red", "~/Library/Caches/com.apple.WebKit.Networking",
              nombre: "Caché de red de WebKit",
              detalle: "Caché de internet que comparten Safari y otras apps que muestran páginas web.",
              consecuencia: "Se vuelve a crear sola; algunas páginas tardarán un poco más la primera vez. Tu historial y tus contraseñas no se tocan.")
            .sinPreseleccion().sinArchivosAbiertos(),
        Regla("safari-technology-preview-cache", "~/Library/Caches/com.apple.SafariTechnologyPreview",
              nombre: "Caché de Safari Technology Preview",
              detalle: "Caché web de la versión de pruebas de Safari.",
              consecuencia: "Safari Technology Preview la vuelve a crear. Tu historial, marcadores y contraseñas no se tocan.")
            .accesoTotal().app("Safari Technology Preview", "com.apple.SafariTechnologyPreview"),
        Regla("safari-technology-preview-cache-contenedor", "~/Library/Containers/com.apple.SafariTechnologyPreview/Data/Library/Caches",
              nombre: "Caché de Safari Technology Preview (contenedor)",
              detalle: "Caché de páginas y miniaturas de pestañas de la versión de pruebas de Safari.",
              consecuencia: "Safari Technology Preview la vuelve a crear. Tu historial, marcadores y contraseñas no se tocan.")
            .accesoTotal().app("Safari Technology Preview", "com.apple.SafariTechnologyPreview"),
    ]
}
