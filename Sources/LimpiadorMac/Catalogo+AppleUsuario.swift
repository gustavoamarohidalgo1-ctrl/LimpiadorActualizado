import Foundation

// Reglas del área «apple-usuario»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// macOS y apps de Apple en tu carpeta personal (sin contraseña).
extension Catalogo {
    static let appleUsuario: [Regla] = [
        Regla("apple-handoff-portapapeles", "~/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard/*",
              nombre: "Copias del portapapeles universal",
              detalle: "Copias de lo que copiaste con ⌘C para poder pegarlo en otro Mac, iPhone o iPad (Handoff). macOS a veces no las borra y pueden ocupar decenas o cientos de GB.",
              consecuencia: "Nada: solo se pierden copias viejas del portapapeles. Copiar y pegar sigue funcionando igual.")
            .en(.temporales).hijos().edad(dias: 1).accesoTotal().sinArchivosAbiertos(),
        Regla("apple-podcasts-streaming", "~/Library/Containers/com.apple.podcasts/Data/tmp/StreamedMedia",
              nombre: "Restos de episodios escuchados en streaming",
              detalle: "Archivos que Podcasts crea al escuchar episodios sin descargarlos y que luego no borra. Aparecen con 0 bytes pero ocupan espacio de verdad.",
              consecuencia: "Nada: los episodios se vuelven a cargar al escucharlos. Tus descargas y suscripciones no se tocan.")
            .en(.temporales).hijos().edad(dias: 1).accesoTotal().sinArchivosAbiertos().app("Podcasts", "com.apple.podcasts"),
        Regla("apple-podcasts-temporales", "~/Library/Containers/com.apple.podcasts/Data/tmp",
              nombre: "Carátulas y descargas a medias de Podcasts",
              detalle: "Carátulas y trozos de descargas que Podcasts dejó en su carpeta temporal.",
              consecuencia: "Nada: Podcasts las vuelve a descargar cuando le hacen falta.")
            .en(.temporales).archivos("heic", "img", "tmp").edad(dias: 1).accesoTotal().sinArchivosAbiertos().app("Podcasts", "com.apple.podcasts"),
        Regla("apple-podcasts-cache", "~/Library/Caches/com.apple.podcasts",
              nombre: "Caché de Podcasts",
              detalle: "Carátulas y datos temporales de la app Podcasts.",
              consecuencia: "Podcasts los vuelve a descargar. Tus episodios descargados y suscripciones no se tocan.")
            .accesoTotal().sinArchivosAbiertos().app("Podcasts", "com.apple.podcasts"),
        Regla("apple-podcasts-descargas", "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache",
              nombre: "Episodios de podcast descargados hace más de un mes",
              detalle: "Episodios que Podcasts descargó para escucharlos sin conexión. Tienen nombres raros (códigos) en vez del título.",
              consecuencia: "Si el autor retiró algún episodio, no podrás volver a descargarlo. Podcasts puede seguir mostrándolos como descargados hasta que los quites desde la app. Lo más seguro es activar en Podcasts › Ajustes «Eliminar episodios reproducidos».")
            .en(.grandes).cuidado().archivos("mp3", "m4a", "aac", "mp4", "m4v", "mov").edad(dias: 30).accesoTotal().sinArchivosAbiertos().app("Podcasts", "com.apple.podcasts"),
        Regla("apple-mediaanalysis-cache", "~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/com.apple.mediaanalysisd",
              nombre: "Caché del análisis de fotos y vídeos",
              detalle: "Resultados intermedios del servicio que analiza tus fotos para la búsqueda, el Texto en vivo y la Búsqueda visual. En Sonoma y Sequoia creció hasta decenas de GB.",
              consecuencia: "Fotos puede volver a analizar tu fototeca en segundo plano (gastará algo más de batería unas horas). Tus fotos no se tocan.")
            .sinPreseleccion().accesoTotal().sinArchivosAbiertos().excepto("com.apple.e5rt.e5bundlecache"),
        Regla("apple-mediaanalysis-temporales", "~/Library/Containers/com.apple.mediaanalysisd/Data/tmp",
              nombre: "Temporales del análisis de fotos",
              detalle: "Archivos temporales que dejó el servicio que analiza tus fotos y vídeos.",
              consecuencia: "Nada: el servicio crea otros cuando los necesita.")
            .en(.temporales).hijos().edad(dias: 1).accesoTotal().sinArchivosAbiertos(),
        Regla("apple-fondos-cache", "~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/*",
              nombre: "Caché de fondos de pantalla",
              detalle: "Copias de cada imagen que pusiste de fondo de pantalla. En Sonoma y en Tahoe esta caché no se vacía sola y puede llegar a ocupar cientos de GB.",
              consecuencia: "macOS vuelve a preparar el fondo actual (puede verse un momento en negro). Tus fotos y los fondos que elegiste no se tocan.")
            .accesoTotal().sinArchivosAbiertos().excepto("com.apple.e5rt.e5bundlecache"),
        Regla("apple-fondos-aerial-temporales", "~/Library/Containers/com.apple.wallpaper.extension.aerials/Data/tmp",
              nombre: "Descargas a medias de fondos Aerial",
              detalle: "Trozos de vídeos de fondos y salvapantallas Aerial que no se terminaron de descargar.",
              consecuencia: "Nada: si eliges ese fondo, macOS lo vuelve a descargar.")
            .en(.temporales).hijos().edad(dias: 1).accesoTotal().sinArchivosAbiertos(),
        Regla("apple-mensajes-previsualizaciones", "~/Library/Messages/Caches/Previews/Attachments",
              nombre: "Miniaturas de adjuntos de Mensajes",
              detalle: "Vistas previas que Mensajes genera de las fotos, vídeos y enlaces de tus conversaciones.",
              consecuencia: "Mensajes las vuelve a generar al abrir cada conversación. Tus mensajes y los adjuntos originales no se tocan.")
            .hijos().accesoTotal().sinArchivosAbiertos().app("Mensajes", "com.apple.MobileSMS"),
        Regla("apple-mensajes-stickers-previsualizaciones", "~/Library/Messages/Caches/Previews/StickerCache",
              nombre: "Miniaturas de stickers de Mensajes",
              detalle: "Vistas previas de los stickers que aparecen en tus conversaciones.",
              consecuencia: "Mensajes las vuelve a generar. Tus stickers y mensajes no se tocan.")
            .hijos().accesoTotal().sinArchivosAbiertos().app("Mensajes", "com.apple.MobileSMS"),
        Regla("apple-crashreporter", "~/Library/Application Support/CrashReporter/Intervals_*.plist",
              nombre: "Contadores de fallos antiguos",
              detalle: "Pequeños archivos donde macOS cuenta cuántas veces se cerró de golpe cada app.",
              consecuencia: "Nada: se vuelven a crear en el próximo fallo.")
            .en(.registros).edad(dias: 30).excepto("DiagnosticMessagesHistory.plist"),
        Regla("apple-quicklook-miniaturas", "$CACHES/com.apple.QuickLook.thumbnailcache",
              nombre: "Miniaturas de Vista Rápida",
              detalle: "Las miniaturas que el Finder y Vista Rápida generan de tus archivos. Guarda también miniaturas de archivos que ya borraste.",
              consecuencia: "El Finder las vuelve a generar al mostrar cada carpeta (verás iconos genéricos un momento).")
            .en(.temporales).sinArchivosAbiertos(),
        Regla("apple-quicklook-agente", "~/Library/Caches/com.apple.quicklook.ThumbnailsAgent",
              nombre: "Caché del generador de miniaturas",
              detalle: "Caché del servicio que crea las miniaturas de tus archivos.",
              consecuencia: "Se regenera sola al mostrar archivos en el Finder.")
            .sinArchivosAbiertos(),
        Regla("apple-quicklook-antigua", "~/Library/Caches/com.apple.QuickLook.thumbnailcache",
              nombre: "Miniaturas de Vista Rápida (ubicación antigua)",
              detalle: "Miniaturas que versiones anteriores de macOS guardaban en tu carpeta.",
              consecuencia: "Nada: se regeneran si hacen falta.")
            .sinArchivosAbiertos(),
        Regla("apple-metal-apps-apple", "$CACHES/com.apple.*/com.apple.metal*",
              nombre: "Shaders de Metal de apps de Apple",
              detalle: "Programas gráficos que macOS compila para cada app y servicio de Apple (Fotos, Mapas, Dock…).",
              consecuencia: "Cada app los vuelve a compilar la próxima vez que se abra (puede tardar un poco más).")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().excepto("com.apple.WebKit.*", "com.apple.Safari*", "com.apple.dt.*", "com.apple.DeveloperTools"),
        Regla("apple-gpuarchiver-apps-apple", "$CACHES/com.apple.*/com.apple.gpuarchiver",
              nombre: "Archivos gráficos precompilados de apps de Apple",
              detalle: "Binarios de GPU que macOS archiva para que las apps de Apple arranquen más rápido.",
              consecuencia: "Se vuelven a crear la próxima vez que se abra cada app.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().excepto("com.apple.WebKit.*", "com.apple.Safari*", "com.apple.dt.*", "com.apple.DeveloperTools"),
        Regla("apple-iconos", "$CACHES/com.apple.iconservices",
              nombre: "Caché de iconos",
              detalle: "Iconos de apps y archivos ya dibujados que el Finder y el Dock guardan para mostrarlos rápido. Borrarla arregla iconos que se ven mal.",
              consecuencia: "Algunos iconos se verán genéricos hasta que reinicies el Mac; luego se regeneran solos.")
            .en(.temporales).revisar().sinArchivosAbiertos(),
        Regla("apple-geoservices", "~/Library/Caches/GeoServices/*",
              nombre: "Caché de mapas del sistema",
              detalle: "Trozos de mapas que macOS descarga para Mapas, el Tiempo, Buscar y Fotos.",
              consecuencia: "Se vuelven a descargar al ver un mapa (necesita internet). Si descargaste mapas sin conexión, comprueba en Mapas que siguen ahí. Tus lugares guardados no se tocan.")
            .sinPreseleccion().sinArchivosAbiertos().excepto("*Offline*", "*offline*"),
        Regla("apple-parsecd", "~/Library/Caches/com.apple.parsecd",
              nombre: "Caché de sugerencias de búsqueda",
              detalle: "Resultados y sugerencias que Spotlight y Safari descargan de internet mientras escribes.",
              consecuencia: "Se vuelven a descargar. Tu índice de Spotlight y tus archivos no se tocan.")
            .hijos().sinArchivosAbiertos(),
        Regla("apple-servicios-multimedia", "~/Library/Caches/com.apple.AppleMediaServices",
              nombre: "Caché de las tiendas de Apple",
              detalle: "Fichas, portadas y recomendaciones de la App Store, Música, TV y Podcasts.",
              consecuencia: "Se vuelven a descargar al abrir esas apps.")
            .hijos().sinArchivosAbiertos(),
        Regla("apple-appstore-contenedor", "~/Library/Containers/com.apple.AppStore/Data/Library/Caches",
              nombre: "Caché de la App Store",
              detalle: "Imágenes y páginas de la App Store guardadas para cargar más rápido.",
              consecuencia: "La App Store las vuelve a descargar. Tus apps y sus actualizaciones no se tocan.")
            .accesoTotal().app("App Store", "com.apple.AppStore"),
        Regla("apple-musica-agentes", "~/Library/Caches/com.apple.AMP*",
              nombre: "Cachés de los servicios de Música",
              detalle: "Cachés de los procesos que gestionan tu biblioteca de música, las carátulas y la sincronización con el iPhone.",
              consecuencia: "Se regeneran solas. Tus canciones, listas y copias del iPhone no se tocan.")
            .sinPreseleccion().accesoTotal().sinArchivosAbiertos().app("Música", "com.apple.Music"),
        Regla("apple-musica-caratulas", "~/Library/Containers/com.apple.AMPArtworkAgent/Data/Library/Caches",
              nombre: "Caché de carátulas de Música",
              detalle: "Carátulas de álbumes que Música descargó.",
              consecuencia: "Música las vuelve a descargar al mostrarlas.")
            .accesoTotal().sinArchivosAbiertos().app("Música", "com.apple.Music"),
        Regla("apple-itunes-store-cache", "~/Library/Caches/com.apple.iTunes",
              nombre: "Caché de iTunes Store",
              detalle: "Caché de la tienda de iTunes, que todavía usan algunos componentes de Música y TV (y que queda de iTunes en Macs actualizados).",
              consecuencia: "Se vuelve a crear si hace falta. Tu música y tus compras no se tocan.")
            .accesoTotal().sinArchivosAbiertos(),
        Regla("apple-tv-cache-usuario", "~/Library/Caches/com.apple.TV",
              nombre: "Caché de la app TV",
              detalle: "Imágenes y datos temporales de la app TV.",
              consecuencia: "TV los vuelve a descargar. Las películas y series descargadas no se tocan.")
            .accesoTotal().app("TV", "com.apple.TV"),
        Regla("apple-finalcut-cache", "~/Library/Caches/com.apple.FinalCut",
              nombre: "Caché de Final Cut Pro",
              detalle: "Archivos temporales que Final Cut Pro usa mientras editas.",
              consecuencia: "Final Cut la vuelve a crear. Tus bibliotecas y proyectos no se tocan.")
            .app("Final Cut Pro", "com.apple.FinalCut"),
        Regla("apple-finalcut-transcodificados", "~/Movies/*.fcpbundle/*/Transcoded Media",
              nombre: "Medios optimizados y proxy de Final Cut Pro",
              detalle: "Copias optimizadas y de baja resolución de tus vídeos que Final Cut crea para editar con fluidez. Pueden ocupar tanto como los originales.",
              consecuencia: "Final Cut las vuelve a crear desde los vídeos originales (puede tardar mucho). Si borraste o moviste los originales, o están en un disco desconectado, perderás estas copias para siempre.")
            .cuidado().app("Final Cut Pro", "com.apple.FinalCut"),
        Regla("apple-iwork-cache", "~/Library/Containers/com.apple.iWork.*/Data/Library/Caches",
              nombre: "Caché de Pages, Numbers y Keynote",
              detalle: "Archivos temporales de las apps de iWork.",
              consecuencia: "Se regeneran al abrir cada app. Tus documentos no se tocan.")
            .accesoTotal().app("iWork", "com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote"),
        Regla("apple-mail-cache", "~/Library/Containers/com.apple.mail/Data/Library/Caches/*",
              nombre: "Caché de Mail",
              detalle: "Datos temporales de Mail (imágenes remotas, vistas previas de mensajes).",
              consecuencia: "Mail la vuelve a crear. Tus correos, cuentas y adjuntos no se tocan.")
            .accesoTotal().sinArchivosAbiertos().excepto("com.apple.e5rt.e5bundlecache").app("Mail", "com.apple.mail"),
        Regla("apple-mail-registros", "~/Library/Containers/com.apple.mail/Data/Library/Logs/Mail",
              nombre: "Registros de conexión de Mail",
              detalle: "Registros de las conexiones de Mail con tus servidores de correo. Pueden crecer mucho si alguna vez activaste el registro de conexiones.",
              consecuencia: "Nada: solo son registros. Tus correos no se tocan.")
            .en(.registros).hijos().accesoTotal().app("Mail", "com.apple.mail"),
        Regla("apple-libros-web", "~/Library/Containers/com.apple.iBooksX/Data/Library/Caches/WebKit",
              nombre: "Caché de la tienda de Libros",
              detalle: "Páginas e imágenes de Apple Books guardadas para cargar más rápido.",
              consecuencia: "Libros las vuelve a descargar. Tus libros, notas y subrayados no se tocan.")
            .accesoTotal().app("Libros", "com.apple.iBooksX"),
        Regla("apple-imovie-cache", "~/Library/Containers/com.apple.iMovieApp/Data/Library/Caches",
              nombre: "Caché de iMovie",
              detalle: "Archivos temporales de iMovie (miniaturas, vistas previas).",
              consecuencia: "iMovie los vuelve a crear. Tus proyectos y vídeos no se tocan.")
            .accesoTotal().app("iMovie", "com.apple.iMovieApp"),
        Regla("apple-garageband-cache", "~/Library/Containers/com.apple.garageband10/Data/Library/Caches",
              nombre: "Caché de GarageBand",
              detalle: "Archivos temporales de GarageBand.",
              consecuencia: "GarageBand los vuelve a crear. Tus canciones, proyectos y sonidos descargados no se tocan.")
            .accesoTotal().app("GarageBand", "com.apple.garageband10"),
        Regla("apple-safari-webapps", "~/Library/Containers/com.apple.Safari.WebApp/Data/Library/Containers/*/Library/Caches",
              nombre: "Caché de apps web de Safari",
              detalle: "Cachés de las webs que añadiste al Dock como app (Safari › Archivo › Añadir al Dock).",
              consecuencia: "Cada app web vuelve a cargar sus archivos la próxima vez. Tus sesiones y ajustes no se tocan.")
            .accesoTotal().sinArchivosAbiertos(),
        Regla("apple-safari-favicons", "~/Library/Safari/Favicon Cache",
              nombre: "Iconos de webs de Safari",
              detalle: "Los iconitos de las webs que visitaste, que Safari muestra en pestañas, marcadores e historial.",
              consecuencia: "Safari los vuelve a descargar al visitar cada web (al principio verás iconos genéricos). No pierdes historial ni marcadores.")
            .sinPreseleccion().accesoTotal().app("Safari", "com.apple.Safari"),
        Regla("apple-safari-iconos-tactiles", "~/Library/Safari/Touch Icons Cache",
              nombre: "Miniaturas de webs favoritas de Safari",
              detalle: "Imágenes grandes de las webs que aparecen en la página de inicio y en Favoritos de Safari.",
              consecuencia: "Safari las vuelve a descargar. Tus favoritos no se tocan.")
            .sinPreseleccion().accesoTotal().app("Safari", "com.apple.Safari"),
        Regla("apple-python-cache", "~/Library/Caches/com.apple.python",
              nombre: "Caché del Python de Apple",
              detalle: "Archivos .pyc que el python3 de Xcode y de las herramientas de línea de comandos guarda aquí porque no puede escribir en su propia carpeta. Con pip y scripts se llena de copias de rutas temporales.",
              consecuencia: "Python los vuelve a generar la primera vez que ejecutes cada script (irá un poco más lento esa vez).")
            .en(.desarrollo).sinArchivosAbiertos(),
        Regla("apple-descargas-segundo-plano", "~/Library/Caches/com.apple.nsurlsessiond/Downloads/*",
              nombre: "Descargas en segundo plano abandonadas",
              detalle: "Archivos a medio descargar que las apps dejaron en el servicio de descargas de macOS y que llevan más de una semana sin avanzar.",
              consecuencia: "Si alguna app retoma esa descarga, empezará desde el principio.")
            .en(.temporales).sinPreseleccion().hijos().edad(dias: 7).sinArchivosAbiertos(),
        Regla("apple-configurator-firmware", "~/Library/Group Containers/*.group.com.apple.configurator/Library/Caches/Firmware",
              nombre: "Firmware descargado por Apple Configurator",
              detalle: "Sistemas completos (.ipsw) de iPhone, iPad, Apple TV o Mac que Apple Configurator descargó para restaurarlos. Cada uno ocupa entre 5 y 15 GB.",
              consecuencia: "Si vuelves a restaurar un dispositivo, Apple Configurator lo descargará otra vez.")
            .en(.instaladores).sinPreseleccion().archivos("ipsw").accesoTotal().app("Apple Configurator", "com.apple.configurator.ui"),
        Regla("apple-ipod-photo-cache-carpeta", "~/Pictures/iPod Photo Cache",
              nombre: "Fotos preparadas para tu iPhone o iPad (carpeta)",
              detalle: "Copias reducidas que el Finder crea cuando sincronizas una carpeta de fotos con un iPhone o iPad.",
              consecuencia: "Tus fotos no se tocan. Se vuelve a crear en la próxima sincronización por cable.")
            .sinPreseleccion(),
        Regla("apple-aerial-terceros-videos", "~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver*/Data/Library/Application Support/Aerial/Cache",
              nombre: "Vídeos descargados del salvapantallas Aerial",
              detalle: "Vídeos aéreos que el salvapantallas Aerial (de terceros) descargó. Cada uno ocupa entre 100 MB y 1 GB.",
              consecuencia: "Aerial los vuelve a descargar cuando los necesite (hace falta internet). Mientras tanto, el salvapantallas puede verse en negro.")
            .revisar().hijos().accesoTotal().app("Aerial"),
        Regla("apple-salvapantallas-terceros-cache", "~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver*/Data/Library/Caches/*",
              nombre: "Caché de salvapantallas de otros desarrolladores",
              detalle: "Archivos temporales de los salvapantallas que instalaste (no los de Apple).",
              consecuencia: "Cada salvapantallas los vuelve a crear la próxima vez que se active.")
            .sinPreseleccion().accesoTotal().sinArchivosAbiertos().excepto("Aerial").proceso("legacyScreenSaver", patron: "legacyScreenSaver"),
        Regla("apple-voz-cache", "~/Library/Caches/com.apple.speech.*",
              nombre: "Cachés de voz",
              detalle: "Datos temporales del sistema que lee texto en voz alta y del reconocimiento de voz.",
              consecuencia: "Se regeneran la próxima vez que el Mac lea algo en voz alta o uses el dictado. Las voces descargadas no están aquí.")
            .sinPreseleccion().sinArchivosAbiertos(),
        Regla("apple-dictado-cache", "~/Library/Caches/com.apple.SpeechRecognitionCore",
              nombre: "Caché del dictado",
              detalle: "Datos temporales del servicio de dictado de macOS.",
              consecuencia: "Se regenera la próxima vez que dictes.")
            .sinPreseleccion().sinArchivosAbiertos(),
        Regla("apple-transporter-registros", "~/Library/Group Containers/group.com.apple.contentdelivery/Library/Logs",
              nombre: "Registros de subidas a App Store Connect",
              detalle: "Registros de Transporter y de las subidas de apps desde Xcode a App Store Connect.",
              consecuencia: "Nada: solo son registros. Tus apps y versiones subidas no se tocan.")
            .en(.registros).hijos().accesoTotal().app("Transporter"),
        Regla("apple-transporter-registros-raiz", "~/Library/Group Containers/group.com.apple.contentdelivery/Logs",
              nombre: "Registros de subidas a App Store Connect",
              detalle: "Registros de Transporter y de las subidas de apps desde Xcode a App Store Connect.",
              consecuencia: "Nada: solo son registros. Tus apps y versiones subidas no se tocan.")
            .en(.registros).hijos().accesoTotal().app("Transporter"),
        Regla("apple-contenedores-temporales", "~/Library/Containers/com.apple.*/Data/tmp/*",
              nombre: "Temporales de apps de Apple",
              detalle: "Archivos temporales que las apps y servicios de Apple dejaron en su carpeta privada y que llevan días sin usarse.",
              consecuencia: "Nada: ningún programa los tiene abiertos y llevan más de 3 días sin cambios.")
            .en(.temporales).sinPreseleccion().edad(dias: 3).accesoTotal().sinArchivosAbiertos().excepto("com.apple.Notes*", "com.apple.mail", "com.apple.MobileSMS*", "com.apple.Settings*", "com.apple.systempreferences*", "com.apple.controlcenter*", "com.apple.finder*", "com.apple.dock*", "com.apple.Passwords*", "com.apple.keychain*", "com.apple.security*", "com.apple.CloudDocs*", "com.apple.FileProvider*", "com.apple.iCloudDrive*", "com.apple.bird*", "com.apple.Preview*", "com.apple.TextEdit*", "com.apple.Photos*", "com.apple.iWork.*", "com.apple.QuickTimePlayerX*", "com.apple.VoiceMemos*", "com.apple.screencaptureui*", "com.apple.freeform*", "TemporaryItems", "NSIRD_*"),
    ]
}
