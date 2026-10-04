import Foundation

/// Apps de terceros: navegadores, comunicación, multimedia, juegos y utilidades.
/// Lo que está en ~/Library/Caches ya lo cubre el análisis general; aquí va lo que las apps guardan en otros sitios.
extension Catalogo {
    static let aplicaciones: [Regla] = [
        // MARK: Navegadores
        Regla("chrome-modelo-ia", "~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel",
              nombre: "Modelo de IA de Chrome",
              detalle: "El modelo de inteligencia artificial que Chrome descarga para sus funciones locales (puede ocupar varios GB).",
              consecuencia: "Si usas esas funciones, Chrome lo vuelve a descargar. Tus pestañas, contraseñas y marcadores no se tocan.")
            .soloSiEstaInstalada().sinPreseleccion().app("Google Chrome", "com.google.Chrome"),
        Regla("firefox-informes", "~/Library/Application Support/Firefox/Crash Reports",
              nombre: "Informes de fallos de Firefox",
              detalle: "Informes que Firefox guarda cuando se cierra de golpe.",
              consecuencia: "Nada: solo sirven para diagnosticar fallos antiguos.")
            .en(.registros).app("Firefox", "org.mozilla.firefox"),

        // MARK: Comunicación
        Regla("discord-versiones", "~/Library/Application Support/discord/0.0.*",
              nombre: "Versiones viejas de Discord",
              detalle: "Módulos de versiones anteriores de Discord que se quedaron al actualizar.",
              consecuencia: "Nada: Discord usa la versión más nueva, que se conserva.")
            .conservando(.versionMasAlta).soloSiEstaInstalada().app("Discord", "com.hnc.Discord"),

        // MARK: Multimedia
        Regla("adobe-media-cache-files", "~/Library/Application Support/Adobe/Common/Media Cache Files",
              nombre: "Caché de medios de Adobe",
              detalle: "Audio y vídeo que Premiere, After Effects y Media Encoder preparan para editar con fluidez.",
              consecuencia: "Adobe la regenera al abrir cada proyecto (la primera vez irá más lento). Tus proyectos y vídeos no se tocan.")
            .app("Adobe Premiere Pro", "com.adobe.PremierePro", "com.adobe.AfterEffects"),
        Regla("adobe-media-cache", "~/Library/Application Support/Adobe/Common/Media Cache",
              nombre: "Base de datos de la caché de medios de Adobe",
              detalle: "El índice de la caché de medios de las apps de vídeo de Adobe.",
              consecuencia: "Adobe la vuelve a crear al abrir un proyecto.")
            .app("Adobe Premiere Pro", "com.adobe.PremierePro", "com.adobe.AfterEffects"),
        Regla("adobe-peak-files", "~/Library/Application Support/Adobe/Common/Peak Files",
              nombre: "Formas de onda de Adobe",
              detalle: "Dibujos de las ondas de audio que Premiere y Audition calculan para mostrarlas.",
              consecuencia: "Se vuelven a calcular al abrir cada proyecto.")
            .app("Adobe Premiere Pro", "com.adobe.PremierePro", "com.adobe.Audition"),
        Regla("final-cut-render", "~/Movies/*.fcpbundle/*/Render Files",
              nombre: "Archivos de render de Final Cut Pro",
              detalle: "Vídeo prerenderizado de tus proyectos para reproducirlos sin cortes.",
              consecuencia: "Final Cut los vuelve a renderizar cuando haga falta. Tus vídeos y proyectos no se tocan (es lo mismo que «Eliminar archivos generados»).")
            .sinPreseleccion().app("Final Cut Pro", "com.apple.FinalCut"),
        Regla("imovie-render", "~/Movies/*.imovielibrary/*/Render Files",
              nombre: "Archivos de render de iMovie",
              detalle: "Vídeo prerenderizado de tus proyectos de iMovie.",
              consecuencia: "iMovie los vuelve a generar cuando haga falta. Tus vídeos y proyectos no se tocan.")
            .sinPreseleccion().app("iMovie", "com.apple.iMovieApp"),

        // MARK: Juegos
        Regla("steam-appcache", "~/Library/Application Support/Steam/appcache",
              nombre: "Caché de Steam",
              detalle: "Información de juegos y de la tienda que Steam guarda para cargar más rápido.",
              consecuencia: "Steam la vuelve a crear al abrirse. Tus juegos no se tocan.")
            .soloSiEstaInstalada().app("Steam", "com.valvesoftware.steam"),
        Regla("steam-depotcache", "~/Library/Application Support/Steam/depotcache",
              nombre: "Manifiestos de descarga de Steam",
              detalle: "Datos que Steam usó para descargar y actualizar juegos.",
              consecuencia: "Steam los vuelve a descargar cuando actualice un juego.")
            .soloSiEstaInstalada().app("Steam", "com.valvesoftware.steam"),
        Regla("steam-shaders", "~/Library/Application Support/Steam/steamapps/shadercache",
              nombre: "Shaders de juegos de Steam",
              detalle: "Shaders precompilados de cada juego.",
              consecuencia: "Steam los vuelve a preparar; el primer arranque de cada juego puede tardar algo más.")
            .soloSiEstaInstalada().app("Steam", "com.valvesoftware.steam"),
        Regla("steam-temporales", "~/Library/Application Support/Steam/steamapps/temp",
              nombre: "Temporales de Steam",
              detalle: "Archivos temporales de instalaciones y actualizaciones de juegos.",
              consecuencia: "Nada: Steam crea otros cuando los necesita.")
            .soloSiEstaInstalada().app("Steam", "com.valvesoftware.steam"),
        Regla("steam-descargas", "~/Library/Application Support/Steam/steamapps/downloading",
              nombre: "Descargas a medias de Steam",
              detalle: "Juegos o actualizaciones que empezaste a descargar y no terminaron.",
              consecuencia: "Si quieres esos juegos, Steam tendrá que descargarlos desde el principio.")
            .soloSiEstaInstalada().revisar().app("Steam", "com.valvesoftware.steam"),
        Regla("steam-registros", "~/Library/Application Support/Steam/logs",
              nombre: "Registros de Steam",
              detalle: "Registros de Steam.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).soloSiEstaInstalada().app("Steam", "com.valvesoftware.steam"),
        Regla("minecraft-registros", "~/Library/Application Support/minecraft/logs",
              nombre: "Registros de Minecraft",
              detalle: "Registros de cada partida de Minecraft.",
              consecuencia: "Nada: tus mundos no se tocan.")
            .en(.registros).app("Minecraft", "com.mojang.minecraftlauncher"),

        // MARK: Actualizaciones descargadas
        Regla("electron-actualizaciones", "~/Library/Application Support/Caches/*-updater",
              nombre: "Actualizaciones descargadas de apps",
              detalle: "Instaladores de actualizaciones que las apps (Electron) descargaron y ya aplicaron o volverán a descargar.",
              consecuencia: "Nada: si la app necesita actualizarse, vuelve a descargar la actualización.")
            .edad(dias: 3),
    ]
}
