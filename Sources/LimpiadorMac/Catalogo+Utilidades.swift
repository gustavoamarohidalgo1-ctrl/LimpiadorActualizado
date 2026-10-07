import Foundation

// Reglas del área «utilidades»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// Utilidades, seguridad, periféricos e impresoras.
extension Catalogo {
    static let utilidades: [Regla] = [
        Regla("chromium-updater-crx-usuario", "~/Library/Application Support/*/*Updater/crx_cache",
              nombre: "Actualizaciones ya descargadas de Chrome y Edge",
              detalle: "Paquetes que Google Updater y Microsoft Edge Updater guardan después de actualizar el navegador.",
              consecuencia: "Nada: la próxima actualización se descargará completa en lugar de solo los cambios. Tu navegador y tus datos no se tocan.")
            .proceso("Actualizador de Chrome o Edge", patron: "updater.app/contents/macos/"),
        Regla("chromium-updater-crx-sistema", "/Library/Application Support/*/*Updater/crx_cache",
              nombre: "Actualizaciones ya descargadas de Chrome y Edge (todo el Mac)",
              detalle: "Paquetes que el actualizador de Google o de Edge instalado para todos los usuarios guarda tras actualizar.",
              consecuencia: "Nada: la próxima actualización se descargará completa en lugar de solo los cambios. Tu navegador y tus datos no se tocan.")
            .admin().sinPreseleccion().proceso("Actualizador de Chrome o Edge", patron: "updater.app/contents/macos/"),
        Regla("electron-updater-cache-xdg", "~/.cache/*-updater",
              nombre: "Actualizaciones descargadas de apps (carpeta .cache)",
              detalle: "Instaladores de actualizaciones que apps como Zulip, Workflowy o Beeper guardan después de actualizarse.",
              consecuencia: "Nada: si la app necesita actualizarse, vuelve a descargar la actualización.")
            .edad(dias: 3).sinArchivosAbiertos(),
        Regla("teams-webview-cache", "~/Library/Containers/com.microsoft.teams2/Data/Library/Application Support/Microsoft/MSTeams/EBWebView/*/*Cache",
              nombre: "Caché web de Microsoft Teams",
              detalle: "Páginas, scripts, gráficos e imágenes que el nuevo Teams guarda dentro de su contenedor.",
              consecuencia: "Teams tardará un poco más en abrir la primera vez. No pierdes chats, archivos ni tu sesión.")
            .accesoTotal().soloSiEstaInstalada().app("Microsoft Teams", "com.microsoft.teams2"),
        Regla("teams-webview-service-worker", "~/Library/Containers/com.microsoft.teams2/Data/Library/Application Support/Microsoft/MSTeams/EBWebView/*/Service Worker/CacheStorage",
              nombre: "Copia sin conexión de Microsoft Teams",
              detalle: "Copia de la app web de Teams que se guarda para abrir más rápido.",
              consecuencia: "Teams la vuelve a descargar al abrirse. No pierdes chats ni tu sesión.")
            .accesoTotal().soloSiEstaInstalada().app("Microsoft Teams", "com.microsoft.teams2"),
        Regla("teams-registros", "~/Library/Group Containers/UBF8T346G9.com.microsoft.teams/Library/Application Support/Logs",
              nombre: "Registros de Microsoft Teams",
              detalle: "Registros de diagnóstico del nuevo Teams.",
              consecuencia: "Nada: solo se pierden registros antiguos. Tus chats y archivos no se tocan.")
            .en(.registros).hijos().edad(dias: 2).accesoTotal().app("Microsoft Teams", "com.microsoft.teams2"),
        Regla("utilidades-slack-appstore-cache", "~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/*Cache",
              nombre: "Caché de Slack (App Store)",
              detalle: "Imágenes, scripts y gráficos que guarda Slack instalado desde la App Store.",
              consecuencia: "Slack los vuelve a descargar. No pierdes mensajes ni tu sesión.")
            .accesoTotal().soloSiEstaInstalada().app("Slack", "com.tinyspeck.slackmacgap"),
        Regla("slack-appstore-registros", "~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/logs",
              nombre: "Registros de Slack (App Store)",
              detalle: "Registros de diagnóstico de Slack instalado desde la App Store.",
              consecuencia: "Nada: solo se pierden registros antiguos.")
            .en(.registros).accesoTotal().soloSiEstaInstalada().app("Slack", "com.tinyspeck.slackmacgap"),
        Regla("bitwarden-appstore-cache", "~/Library/Containers/com.bitwarden.desktop/Data/Library/Application Support/Bitwarden/*Cache",
              nombre: "Caché de Bitwarden (App Store)",
              detalle: "Archivos temporales de la ventana de Bitwarden instalado desde la App Store.",
              consecuencia: "Bitwarden los vuelve a crear. Tu bóveda y tu sesión no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Bitwarden", "com.bitwarden.desktop"),
        Regla("bitwarden-appstore-registros", "~/Library/Containers/com.bitwarden.desktop/Data/Library/Application Support/Bitwarden/logs",
              nombre: "Registros de Bitwarden (App Store)",
              detalle: "Registros de diagnóstico de Bitwarden.",
              consecuencia: "Nada: tu bóveda, contraseñas y ajustes no se tocan.")
            .en(.registros).accesoTotal().soloSiEstaInstalada().app("Bitwarden", "com.bitwarden.desktop"),
        Regla("1password-registros", "~/Library/Group Containers/2BUA8C4S2C.com.1password/Library/Application Support/1Password/Data/logs",
              nombre: "Registros de 1Password",
              detalle: "Registros de diagnóstico de 1Password 8 (la app los borra sola a los 14 días).",
              consecuencia: "Nada: tu bóveda, contraseñas y ajustes no se tocan.")
            .en(.registros).hijos().edad(dias: 2).accesoTotal().app("1Password", "com.1password.1password"),
        Regla("webex-versiones-viejas", "~/Library/Application Support/WebEx Folder/T*UMC*",
              nombre: "Versiones antiguas de Webex Meetings",
              detalle: "Copias de la app de reuniones de Webex descargadas para versiones anteriores (se conserva la más reciente).",
              consecuencia: "Si una reunión pide una versión antigua, Webex la vuelve a descargar al entrar.")
            .revisar().conservando(.masReciente).app("Webex Meetings", "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark"),
        Regla("anydesk-registro", "~/.anydesk/anydesk.trace",
              nombre: "Registro de AnyDesk",
              detalle: "Archivo de diagnóstico que AnyDesk va llenando en cada sesión y que crece con el tiempo.",
              consecuencia: "Nada: AnyDesk crea uno nuevo. Tus contactos, ajustes e historial de conexiones no se tocan.")
            .en(.registros).sinArchivosAbiertos().app("AnyDesk", "com.philandro.anydesk"),
        Regla("macports-paquetes-temporales", "/opt/local/var/macports/incoming",
              nombre: "Paquetes temporales de MacPorts",
              detalle: "Paquetes ya compilados que MacPorts descargó y dejó a medio procesar.",
              consecuencia: "Nada: si hacen falta, MacPorts los vuelve a descargar. Es lo mismo que «port clean --archive».")
            .admin().sinPreseleccion().hijos().edad(dias: 1).proceso("MacPorts", patron: "/opt/local/bin/port"),
        Regla("fink-compilaciones", "/opt/sw/src/fink.build",
              nombre: "Compilaciones de Fink",
              detalle: "Carpetas de trabajo que Fink deja al compilar paquetes.",
              consecuencia: "Nada: los paquetes instalados siguen funcionando.")
            .admin().sinPreseleccion().hijos().proceso("Fink", patron: "/opt/sw/bin/"),
        Regla("fink-fuentes", "/opt/sw/src",
              nombre: "Código fuente descargado por Fink",
              detalle: "Archivos comprimidos con el código fuente que Fink descargó para compilar paquetes y que llevan más de un mes sin usarse.",
              consecuencia: "Si vuelves a compilar un paquete, Fink descarga otra vez su código. Los que descargaste tú a mano tendrás que volver a bajarlos y ponerlos en esa carpeta.")
            .admin().revisar().archivos("gz", "bz2", "xz", "tgz", "tbz", "tbz2", "zip", "lz", "lzma", "zst", "7z", "tar", "z").edad(dias: 30).excepto("fink.build").proceso("Fink", patron: "/opt/sw/bin/"),
        Regla("fink-paquetes-descargados", "/opt/sw/var/cache/apt/archives",
              nombre: "Paquetes descargados por Fink",
              detalle: "Paquetes .deb que Fink (apt) descargó para instalar programas ya compilados.",
              consecuencia: "Nada: los paquetes ya están instalados. Es lo mismo que «apt-get clean».")
            .admin().sinPreseleccion().archivos("deb").proceso("Fink", patron: "/opt/sw/bin/"),
    ]
}
