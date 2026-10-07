import Foundation

// Reglas del área «comunicacion»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// Comunicación, oficina y entretenimiento: mensajería, videollamadas, Office, música, vídeo y libros.
extension Catalogo {
    static let comunicacion: [Regla] = [
        Regla("telegram-mac-cache-derivada", "~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/*/account-*/postbox/media/cache",
              nombre: "Vistas previas de Telegram",
              detalle: "Versiones reducidas de fotos, vídeos y stickers que Telegram genera para mostrarlos rápido.",
              consecuencia: "Telegram las vuelve a crear cuando abras cada chat. Tus mensajes y archivos no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Telegram", "ru.keepcoder.Telegram"),
        Regla("telegram-mac-short-cache", "~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/*/account-*/postbox/media/short-cache",
              nombre: "Caché temporal de Telegram",
              detalle: "Archivos de vida corta que Telegram guarda mientras navegas por los chats.",
              consecuencia: "Nada: Telegram los vuelve a crear si los necesita. Tus mensajes y archivos no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Telegram", "ru.keepcoder.Telegram"),
        Regla("telegram-mac-animation-cache", "~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/*/account-*/postbox/media/animation-cache",
              nombre: "Animaciones guardadas de Telegram",
              detalle: "Stickers y emojis animados ya preparados para reproducirse sin esfuerzo.",
              consecuencia: "Telegram los vuelve a preparar; al principio los stickers animados pueden tardar un instante. Tus mensajes no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Telegram", "ru.keepcoder.Telegram"),
        Regla("telegram-mac-temp", "~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/*/temp",
              nombre: "Temporales de Telegram",
              detalle: "Archivos temporales de sesiones anteriores de Telegram.",
              consecuencia: "Nada: Telegram ya los considera sobrantes y crea otros al abrirse.")
            .en(.temporales).edad(dias: 1).accesoTotal().sinArchivosAbiertos().app("Telegram", "ru.keepcoder.Telegram"),
        Regla("telegram-mac-logs", "~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/*/logs",
              nombre: "Registros de Telegram",
              detalle: "Registros internos que Telegram guarda para diagnosticar errores.",
              consecuencia: "Nada: solo son registros. Tus chats no se tocan.")
            .en(.registros).accesoTotal().app("Telegram", "ru.keepcoder.Telegram"),
        Regla("telegram-desktop-cache", "~/Library/Application Support/Telegram Desktop/tdata/user_data*/cache",
              nombre: "Caché de Telegram Desktop",
              detalle: "Fotos, stickers y miniaturas que Telegram Desktop guardó al ver tus chats.",
              consecuencia: "Se vuelven a descargar al abrir cada chat. Es lo mismo que «Borrar caché» en sus ajustes; tus mensajes están en la nube.")
            .soloSiEstaInstalada().app("Telegram Desktop", "com.tdesktop.Telegram"),
        Regla("telegram-desktop-media-cache", "~/Library/Application Support/Telegram Desktop/tdata/user_data*/media_cache",
              nombre: "Vídeos y archivos vistos en Telegram Desktop",
              detalle: "Copias de vídeos, audios y documentos grandes que abriste en Telegram Desktop.",
              consecuencia: "Si vuelves a abrirlos, se descargan otra vez de la nube. Los que guardaste en Descargas no se tocan.")
            .soloSiEstaInstalada().app("Telegram Desktop", "com.tdesktop.Telegram"),
        Regla("telegram-desktop-tdld", "~/Library/Application Support/Telegram Desktop/tdata/tdld",
              nombre: "Descargas a medias de Telegram Desktop",
              detalle: "Carpeta temporal antigua donde Telegram Desktop dejaba descargas sin terminar.",
              consecuencia: "Nada: son restos de descargas temporales. Tus chats no se tocan.")
            .en(.temporales).edad(dias: 3).sinArchivosAbiertos().app("Telegram Desktop", "com.tdesktop.Telegram"),
        Regla("telegram-lite-media-cache", "~/Library/Containers/org.telegram.desktop/Data/Library/Application Support/Telegram Desktop/tdata/user_data*/media_cache",
              nombre: "Vídeos y archivos vistos en Telegram Lite",
              detalle: "Copias de vídeos y documentos que abriste en Telegram Lite (versión de la App Store).",
              consecuencia: "Si vuelves a abrirlos, se descargan otra vez de la nube. Tus mensajes no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Telegram Lite", "org.telegram.desktop"),
        Regla("telegram-lite-cache", "~/Library/Containers/org.telegram.desktop/Data/Library/Application Support/Telegram Desktop/tdata/user_data*/cache",
              nombre: "Caché de Telegram Lite",
              detalle: "Fotos y miniaturas que Telegram Lite guardó al ver tus chats.",
              consecuencia: "Se vuelven a descargar al abrir cada chat. Tus mensajes no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Telegram Lite", "org.telegram.desktop"),
        Regla("signal-update-cache", "~/Library/Application Support/Signal/update-cache",
              nombre: "Actualizaciones descargadas de Signal",
              detalle: "El último instalador de Signal, que guarda para que las próximas actualizaciones descarguen solo los cambios.",
              consecuencia: "La próxima actualización de Signal se descargará completa (algo más grande). Tus chats no se tocan.")
            .en(.instaladores).edad(dias: 1).app("Signal", "org.whispersystems.signal-desktop"),
        Regla("signal-temp", "~/Library/Application Support/Signal/temp",
              nombre: "Temporales de Signal",
              detalle: "Archivos temporales que Signal crea al abrir o enviar adjuntos.",
              consecuencia: "Nada: Signal vacía esta carpeta cada vez que se abre. Tus chats y borradores no se tocan.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().app("Signal", "org.whispersystems.signal-desktop"),
        Regla("discord-asset-cache", "~/Library/Application Support/discord*/discord_asset_cache",
              nombre: "Caché de recursos de Discord",
              detalle: "Imágenes y recursos de la interfaz que Discord guarda para cargar más rápido.",
              consecuencia: "Discord los vuelve a descargar al abrirse. Tus mensajes y ajustes no se tocan.")
            .sinPreseleccion().soloSiEstaInstalada().app("Discord", "com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"),
        Regla("discord-ptb-versiones", "~/Library/Application Support/discordptb/0.0.*",
              nombre: "Versiones viejas de Discord PTB",
              detalle: "Módulos de versiones anteriores de Discord PTB que se quedaron al actualizar.",
              consecuencia: "Nada: Discord PTB usa la versión más nueva, que se conserva.")
            .conservando(.versionMasAlta).soloSiEstaInstalada().app("Discord PTB", "com.hnc.DiscordPTB"),
        Regla("discord-canary-versiones", "~/Library/Application Support/discordcanary/0.0.*",
              nombre: "Versiones viejas de Discord Canary",
              detalle: "Módulos de versiones anteriores de Discord Canary que se quedaron al actualizar.",
              consecuencia: "Nada: Discord Canary usa la versión más nueva, que se conserva.")
            .conservando(.versionMasAlta).soloSiEstaInstalada().app("Discord Canary", "com.hnc.DiscordCanary"),
        Regla("slack-appstore-cache", "~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/Cache",
              nombre: "Caché de Slack (App Store)",
              detalle: "Imágenes y archivos web que Slack guarda para cargar más rápido.",
              consecuencia: "Slack los vuelve a descargar. Es lo mismo que «Borrar caché y reiniciar»; tus mensajes no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Slack", "com.tinyspeck.slackmacgap"),
        Regla("slack-appstore-service-worker", "~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/Service Worker/CacheStorage",
              nombre: "Caché web de Slack (App Store)",
              detalle: "Copia de la aplicación web de Slack que se guarda para abrir sin esperar.",
              consecuencia: "Slack la vuelve a descargar al abrirse. Tus mensajes no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Slack", "com.tinyspeck.slackmacgap"),
        Regla("slack-appstore-code-cache", "~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/Code Cache",
              nombre: "Código precompilado de Slack (App Store)",
              detalle: "Código de la interfaz de Slack ya preparado para arrancar más rápido.",
              consecuencia: "Slack lo vuelve a preparar; el primer arranque irá algo más lento.")
            .accesoTotal().soloSiEstaInstalada().app("Slack", "com.tinyspeck.slackmacgap"),
        Regla("teams-nuevo-cache", "~/Library/Containers/com.microsoft.teams2/Data/Library/Application Support/Microsoft/MSTeams/EBWebView/WV2Profile_*/Cache",
              nombre: "Caché del nuevo Teams",
              detalle: "Imágenes y archivos web que Microsoft Teams guarda para cargar más rápido.",
              consecuencia: "Teams los vuelve a descargar; tus chats y reuniones están en la nube.")
            .accesoTotal().soloSiEstaInstalada().app("Microsoft Teams", "com.microsoft.teams2"),
        Regla("teams-nuevo-service-worker", "~/Library/Containers/com.microsoft.teams2/Data/Library/Application Support/Microsoft/MSTeams/EBWebView/WV2Profile_*/Service Worker/CacheStorage",
              nombre: "Caché web del nuevo Teams",
              detalle: "Copia de la aplicación web de Teams que se guarda para abrir sin esperar.",
              consecuencia: "Teams la vuelve a descargar al abrirse (el primer arranque irá más lento). Tus chats no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Microsoft Teams", "com.microsoft.teams2"),
        Regla("teams-nuevo-code-cache", "~/Library/Containers/com.microsoft.teams2/Data/Library/Application Support/Microsoft/MSTeams/EBWebView/WV2Profile_*/Code Cache",
              nombre: "Código precompilado del nuevo Teams",
              detalle: "Código de la interfaz de Teams ya preparado para arrancar más rápido.",
              consecuencia: "Teams lo vuelve a preparar al abrirse.")
            .accesoTotal().soloSiEstaInstalada().app("Microsoft Teams", "com.microsoft.teams2"),
        Regla("teams-registros-sistema", "/Library/Logs/Microsoft/MSTeams",
              nombre: "Registros del sistema de Teams",
              detalle: "Registros que el instalador y el actualizador de Teams guardan para todo el Mac.",
              consecuencia: "Nada: solo son registros. Tus chats no se tocan.")
            .admin().sinPreseleccion().app("Microsoft Teams", "com.microsoft.teams2"),
        Regla("teams-clasico-registros-sistema", "/Library/Logs/Microsoft/Teams",
              nombre: "Registros de Teams clásico",
              detalle: "Registros que dejó la versión clásica de Teams, que Microsoft ya retiró.",
              consecuencia: "Nada: Teams clásico ya no existe y son solo registros.")
            .admin().sinPreseleccion().app("Microsoft Teams (clásico)", "com.microsoft.teams"),
        Regla("webex-actualizaciones", "~/Library/Application Support/Cisco Spark/Webexteams_upgrades*",
              nombre: "Actualizaciones descargadas de Webex",
              detalle: "Paquetes que Webex descargó para actualizarse.",
              consecuencia: "Nada: Webex ya se actualizó; si hace falta, los vuelve a descargar. Tus reuniones y mensajes no se tocan.")
            .en(.instaladores).edad(dias: 1).app("Webex", "Cisco-Systems.Spark"),
        Regla("obs-crashes", "~/Library/Application Support/obs-studio/crashes",
              nombre: "Informes de fallos de OBS",
              detalle: "Informes que OBS Studio guarda cuando se cierra de golpe.",
              consecuencia: "Nada: solo son informes de errores antiguos. Tus escenas y ajustes no se tocan.")
            .en(.registros).app("OBS Studio", "com.obsproject.obs-studio"),
        Regla("spotify-actualizacion", "~/Library/Application Support/Spotify/PersistentCache/Update",
              nombre: "Actualización descargada de Spotify",
              detalle: "Archivos de la versión nueva de Spotify que se descargaron para instalarse solos.",
              consecuencia: "Nada: si hay otra actualización, Spotify la vuelve a descargar. Tu música descargada no se toca.")
            .en(.instaladores).hijos().edad(dias: 1).app("Spotify", "com.spotify.client"),
        Regla("itunes-caratulas-cache", "~/Music/iTunes/Album Artwork/Cache",
              nombre: "Caché de carátulas del antiguo iTunes",
              detalle: "Copias de carátulas que generaba iTunes; la app Música ya no las usa.",
              consecuencia: "Nada: Música guarda sus carátulas en otro sitio. Tu música no se toca.")
            .sinPreseleccion().edad(dias: 30).app("Música", "com.apple.Music"),
        Regla("podcasts-contenedor-cache", "~/Library/Containers/com.apple.podcasts/Data/Library/Caches",
              nombre: "Caché interna de Podcasts",
              detalle: "Imágenes y datos temporales que Podcasts guarda dentro de su espacio.",
              consecuencia: "Podcasts los vuelve a crear. Tus episodios descargados y suscripciones no se tocan.")
            .accesoTotal().sinArchivosAbiertos().soloSiEstaInstalada().app("Podcasts", "com.apple.podcasts"),
        Regla("kindle-libros-descargados", "~/Library/Containers/com.amazon.Lassen/Data/Library/eBooks",
              nombre: "Libros descargados en Kindle",
              detalle: "Libros de Kindle que descargaste en este Mac para leer sin conexión.",
              consecuencia: "Los libros comprados siguen en tu biblioteca de Amazon y puedes volver a descargarlos desde la app Kindle. Los préstamos vencidos o los libros retirados de la tienda puede que no.")
            .en(.grandes).revisar().accesoTotal().app("Kindle", "com.amazon.Lassen"),
        Regla("office-fontcache", "~/Library/Group Containers/UBF8T346G9.Office/FontCache",
              nombre: "Caché de fuentes de Office",
              detalle: "Lista de tipos de letra que Word, Excel y PowerPoint preparan para arrancar más rápido.",
              consecuencia: "Office la vuelve a crear al abrirse (el primer arranque irá algo más lento). Tus documentos no se tocan.")
            .accesoTotal().soloSiEstaInstalada().app("Microsoft Office", "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.microsoft.Outlook", "com.microsoft.onenote.mac"),
        Regla("office-complementos-wef", "~/Library/Containers/com.microsoft.*/Data/Library/Application Support/Microsoft/Office/16.0/Wef",
              nombre: "Caché de complementos de Office",
              detalle: "Copias de los complementos web (add-ins) que usaste en Word, Excel, PowerPoint u Outlook.",
              consecuencia: "Office vuelve a descargar los complementos al abrirlos; puede que tengas que volver a iniciar sesión en alguno. Tus documentos no se tocan.")
            .revisar().accesoTotal().soloSiEstaInstalada().app("Microsoft Office", "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.microsoft.Outlook"),
        Regla("office-registros-contenedor", "~/Library/Containers/com.microsoft.*/Data/Library/Logs",
              nombre: "Registros de Office",
              detalle: "Registros internos de Word, Excel, PowerPoint, Outlook, OneNote u otras apps de Microsoft.",
              consecuencia: "Nada: solo son registros. Tus documentos y correos no se tocan.")
            .en(.registros).accesoTotal().app("Microsoft Office", "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint", "com.microsoft.Outlook", "com.microsoft.onenote.mac", "com.microsoft.teams2"),
        Regla("wechat-registros", "~/Library/Containers/com.tencent.xinWeChat/Data/Documents/app_data/log",
              nombre: "Registros de WeChat",
              detalle: "Registros internos que WeChat guarda para diagnosticar errores.",
              consecuencia: "Nada: solo son registros. Tus chats y archivos no se tocan.")
            .en(.registros).accesoTotal().app("WeChat", "com.tencent.xinWeChat"),
        Regla("wechat-miniprogramas", "~/Library/Containers/com.tencent.xinWeChat/Data/.wxapplet/WMPF",
              nombre: "Caché de miniprogramas de WeChat",
              detalle: "El motor que WeChat descarga para abrir miniprogramas.",
              consecuencia: "WeChat lo vuelve a descargar la próxima vez que abras un miniprograma. Tus chats no se tocan.")
            .sinPreseleccion().accesoTotal().soloSiEstaInstalada().app("WeChat", "com.tencent.xinWeChat"),
    ]
}
