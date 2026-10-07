import Foundation

// Reglas del área «juegos»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// Juegos, tiendas de juegos y motores.
extension Catalogo {
    static let juegos: [Regla] = [
        Regla("steam-workshop-descargas", "~/Library/Application Support/Steam/steamapps/workshop/downloads",
              nombre: "Descargas a medias de mods de Steam",
              detalle: "Mods del Workshop que Steam empezó a descargar y no terminó.",
              consecuencia: "Si todavía quieres esos mods, Steam los vuelve a descargar. Los mods ya instalados no se tocan.")
            .edad(dias: 3).sinArchivosAbiertos().soloSiEstaInstalada().app("Steam", "com.valvesoftware.steam"),
        Regla("steam-workshop-temp", "~/Library/Application Support/Steam/steamapps/workshop/temp",
              nombre: "Temporales de mods de Steam",
              detalle: "Archivos temporales que Steam usa al instalar o actualizar mods del Workshop.",
              consecuencia: "Nada: Steam crea otros cuando los necesita. Tus mods instalados no se tocan.")
            .edad(dias: 1).sinArchivosAbiertos().soloSiEstaInstalada().app("Steam", "com.valvesoftware.steam"),
        Regla("unreal-ddc-global", "~/Library/Application Support/Epic/UnrealEngine/*/DerivedDataCache",
              nombre: "Caché de datos derivados de Unreal",
              detalle: "Shaders y recursos ya procesados que Unreal comparte entre todos tus proyectos (puede ocupar decenas de GB).",
              consecuencia: "Unreal los vuelve a generar al abrir cada proyecto; la primera vez tardará bastante en compilar shaders. Tus proyectos no se tocan.")
            .en(.desarrollo).sinPreseleccion().soloSiEstaInstalada().app("Unreal Editor", "com.epicgames.UnrealEditor", "com.epicgames.EpicGamesLauncher"),
        Regla("wow-cache", "/Applications/World of Warcraft/_*_/Cache",
              nombre: "Caché de World of Warcraft",
              detalle: "Datos de objetos, misiones y criaturas que WoW descarga del servidor.",
              consecuencia: "WoW la vuelve a descargar al entrar. Tus addons, ajustes (carpeta WTF) y personajes no se tocan.")
            .admin().sinPreseleccion().app("World of Warcraft"),
        Regla("wow-errores", "/Applications/World of Warcraft/_*_/Errors",
              nombre: "Informes de fallos de World of Warcraft",
              detalle: "Informes y volcados que WoW guarda cada vez que se cierra de golpe.",
              consecuencia: "Nada: solo sirven para diagnosticar fallos antiguos. Tus addons, ajustes y personajes no se tocan.")
            .admin().sinPreseleccion().app("World of Warcraft"),
        Regla("wow-registros", "/Applications/World of Warcraft/_*_/Logs",
              nombre: "Registros de World of Warcraft",
              detalle: "Registros del juego, incluidos los registros de combate (WoWCombatLog).",
              consecuencia: "Si subes registros de combate a webs de análisis, guarda antes los que quieras conservar. Tus addons y ajustes no se tocan.")
            .admin().revisar().app("World of Warcraft"),
        Regla("itch-descargas", "~/Library/Application Support/itch/apps/downloads",
              nombre: "Descargas a medias de itch.io",
              detalle: "Juegos que la app de itch.io empezó a descargar y no terminó de instalar.",
              consecuencia: "Si todavía quieres esos juegos, itch.io los vuelve a descargar. Los juegos ya instalados no se tocan.")
            .revisar().edad(dias: 7).sinArchivosAbiertos().soloSiEstaInstalada().app("itch", "io.itch.mac"),
        Regla("minecraft-webcache", "~/Library/Application Support/minecraft/webcache",
              nombre: "Caché web antigua de Minecraft",
              detalle: "Caché del launcher anterior de Minecraft, que la versión actual ya no usa.",
              consecuencia: "Nada: el launcher actual usa otra carpeta. Tus mundos y ajustes no se tocan.")
            .app("Minecraft", "com.mojang.minecraftlauncher"),
        Regla("minecraft-informes-fallos", "~/Library/Application Support/minecraft/crash-reports",
              nombre: "Informes de fallos de Minecraft",
              detalle: "Informes que Minecraft guarda cada vez que el juego se cierra de golpe.",
              consecuencia: "Nada: solo sirven para diagnosticar fallos antiguos. Tus mundos no se tocan.")
            .en(.registros).app("Minecraft", "com.mojang.minecraftlauncher"),
        Regla("minecraft-java", "~/Library/Application Support/minecraft/runtime",
              nombre: "Versiones de Java de Minecraft",
              detalle: "Copias de Java que el launcher descargó para cada versión del juego (se conserva la usada más recientemente).",
              consecuencia: "Si juegas una versión que necesita otra, el launcher la vuelve a descargar (unos 100-200 MB). Tus mundos no se tocan.")
            .revisar().hijos(conservar: .masReciente).sinArchivosAbiertos().app("Minecraft", "com.mojang.minecraftlauncher"),
        Regla("minecraft-recursos", "~/Library/Application Support/minecraft/assets",
              nombre: "Sonidos e idiomas de Minecraft",
              detalle: "Sonidos, idiomas e índices que comparten todas las versiones del juego (suele ocupar casi 1 GB).",
              consecuencia: "El launcher los vuelve a descargar la próxima vez que juegues (necesitas internet). Tus mundos y paquetes de recursos no se tocan.")
            .revisar().sinArchivosAbiertos().app("Minecraft", "com.mojang.minecraftlauncher"),
        Regla("minecraft-librerias", "~/Library/Application Support/minecraft/libraries",
              nombre: "Librerías de Minecraft",
              detalle: "Componentes que el juego necesita y que el launcher descargó.",
              consecuencia: "El launcher vuelve a descargar las oficiales. Las versiones con mods (Forge, NeoForge, OptiFine) no abrirán hasta que vuelvas a ejecutar el instalador de cada una. Tus mundos no se tocan.")
            .revisar().sinArchivosAbiertos().app("Minecraft", "com.mojang.minecraftlauncher"),
        Regla("prism-cache", "~/Library/Application Support/PrismLauncher/cache",
              nombre: "Caché de Prism Launcher",
              detalle: "Modpacks, mods y Java descargados que Prism Launcher guarda por si los vuelves a necesitar.",
              consecuencia: "Prism los vuelve a descargar si hacen falta. Tus instancias y mundos no se tocan.")
            .soloSiEstaInstalada().app("Prism Launcher", "org.prismlauncher.PrismLauncher"),
        Regla("prism-java", "~/Library/Application Support/PrismLauncher/java",
              nombre: "Java descargado por Prism Launcher",
              detalle: "Versiones de Java que Prism Launcher descargó para tus instancias.",
              consecuencia: "Prism las vuelve a descargar si tienes activada la descarga automática de Java; si no, tendrás que elegir otra en los ajustes de la instancia. Tus instancias y mundos no se tocan.")
            .revisar().sinArchivosAbiertos().soloSiEstaInstalada().app("Prism Launcher", "org.prismlauncher.PrismLauncher"),
        Regla("modrinth-registros", "~/Library/Application Support/ModrinthApp/launcher_logs",
              nombre: "Registros de Modrinth App",
              detalle: "Registros del lanzador de Modrinth.",
              consecuencia: "Nada: solo son registros. Tus perfiles y mundos no se tocan.")
            .en(.registros).soloSiEstaInstalada().app("Modrinth App", "com.modrinth.theseus"),
        Regla("lunar-cache-juego", "~/.lunarclient/game-cache",
              nombre: "Caché de juego de Lunar Client",
              detalle: "Archivos temporales que Lunar Client guarda para el juego.",
              consecuencia: "Lunar Client la vuelve a crear. Tus ajustes y cuenta no se tocan.")
            .app("Lunar Client", "com.moonsworth.client"),
        Regla("lunar-cache-lanzador", "~/.lunarclient/launcher-cache",
              nombre: "Caché del lanzador de Lunar Client",
              detalle: "Archivos temporales del lanzador de Lunar Client.",
              consecuencia: "Lunar Client la vuelve a crear. Tus ajustes y cuenta no se tocan.")
            .app("Lunar Client", "com.moonsworth.client"),
        Regla("lunar-registros", "~/.lunarclient/logs",
              nombre: "Registros de Lunar Client",
              detalle: "Registros del lanzador y del juego.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).app("Lunar Client", "com.moonsworth.client"),
        Regla("unity-cache-paquetes", "~/Library/Unity/cache",
              nombre: "Caché global de paquetes de Unity",
              detalle: "Paquetes que el Package Manager de Unity descargó y comparte entre tus proyectos.",
              consecuencia: "Unity los vuelve a descargar cuando un proyecto los necesite (necesitas internet y acceso a los registros de paquetes que uses). Tus proyectos no se tocan.")
            .en(.desarrollo).sinPreseleccion().excepto("Licenses", "Asset Store-5.x").app("Unity", "com.unity3d.UnityEditor5.x", "com.unity3d.unityhub"),
        Regla("unity-asset-store", "~/Library/Unity/Asset Store-5.x",
              nombre: "Paquetes descargados de la Asset Store",
              detalle: "Los .unitypackage que descargaste de la Asset Store para importarlos en tus proyectos.",
              consecuencia: "Lo que ya importaste en tus proyectos no se toca. Si los compraste, puedes volver a descargarlos desde Package Manager › My Assets; alguno retirado de la tienda quizá ya no esté disponible.")
            .en(.instaladores).revisar().app("Unity", "com.unity3d.UnityEditor5.x", "com.unity3d.unityhub"),
        Regla("godot-shaders-proyectos", "~/Library/Application Support/Godot/app_userdata/*/shader_cache",
              nombre: "Shaders compilados de tus proyectos de Godot",
              detalle: "Shaders que Godot compila al ejecutar tus proyectos desde el editor.",
              consecuencia: "Godot los vuelve a compilar la próxima vez que ejecutes el proyecto. Las partidas guardadas y ajustes del proyecto no se tocan.")
            .en(.desarrollo).soloSiEstaInstalada().app("Godot", "org.godotengine.godot"),
        Regla("godot-pipelines-proyectos", "~/Library/Application Support/Godot/app_userdata/*/vulkan",
              nombre: "Caché de gráficos de tus proyectos de Godot",
              detalle: "Estados gráficos precalculados (archivos .cache) que Godot guarda al ejecutar tus proyectos.",
              consecuencia: "Godot los vuelve a crear; el primer arranque irá algo más lento. Las partidas guardadas y ajustes del proyecto no se tocan.")
            .en(.desarrollo).archivos("cache").soloSiEstaInstalada().app("Godot", "org.godotengine.godot"),
        Regla("godot-android-sdk", "~/Library/Application Support/Godot/android-sdk",
              nombre: "SDK de Android descargado por Godot",
              detalle: "Una copia del SDK de Android que Godot descarga para exportar a Android. Si usas Android Studio, ya tienes otra en ~/Library/Android/sdk.",
              consecuencia: "Para exportar a Android desde Godot, indica en Ajustes del editor › Exportar › Android la ruta del SDK de Android Studio, o deja que Godot lo descargue otra vez. Tus proyectos no se tocan.")
            .en(.desarrollo).revisar().soloSiEstaInstalada().app("Godot", "org.godotengine.godot"),
        Regla("godot-java-sdk", "~/Library/Application Support/Godot/java-sdk-*",
              nombre: "Java descargado por Godot",
              detalle: "Un JDK que Godot descarga para exportar a Android.",
              consecuencia: "Para exportar a Android, Godot lo vuelve a descargar o puedes indicarle el JDK de Android Studio. Tus proyectos no se tocan.")
            .en(.desarrollo).revisar().soloSiEstaInstalada().app("Godot", "org.godotengine.godot"),
        Regla("heroic-imagenes", "~/Library/Application Support/heroic/images-cache",
              nombre: "Caché de imágenes de Heroic",
              detalle: "Portadas y fondos de tus juegos que Heroic descargó.",
              consecuencia: "Heroic las vuelve a descargar al mostrar tu biblioteca. Tus juegos no se tocan.")
            .soloSiEstaInstalada().app("Heroic", "com.heroicgameslauncher.hgl"),
        Regla("crossover-temp-windows", "~/Library/Application Support/CrossOver/Bottles/*/drive_c/windows/temp",
              nombre: "Temporales de Windows en CrossOver",
              detalle: "Archivos temporales que dejan los instaladores y programas de Windows dentro de tus botellas.",
              consecuencia: "Nada: ningún programa los usa ya. Tus programas y partidas de la botella no se tocan.")
            .en(.temporales).hijos().edad(dias: 3).sinArchivosAbiertos().soloSiEstaInstalada().app("CrossOver", "com.codeweavers.CrossOver"),
        Regla("crossover-temp-usuario", "~/Library/Application Support/CrossOver/Bottles/*/drive_c/users/*/AppData/Local/Temp",
              nombre: "Temporales de usuario en CrossOver",
              detalle: "Archivos temporales de instaladores, Steam y juegos de Windows dentro de tus botellas.",
              consecuencia: "Nada: ningún programa los usa ya. Tus programas y partidas de la botella no se tocan.")
            .en(.temporales).hijos().edad(dias: 3).sinArchivosAbiertos().excepto("Public").soloSiEstaInstalada().app("CrossOver", "com.codeweavers.CrossOver"),
        Regla("crossover-steam-shaders", "~/Library/Application Support/CrossOver/Bottles/*/drive_c/Program Files (x86)/Steam/steamapps/shadercache",
              nombre: "Shaders de juegos de Steam para Windows (CrossOver)",
              detalle: "Shaders precompilados de los juegos de Windows que instalaste con Steam en una botella.",
              consecuencia: "Steam los vuelve a preparar; el primer arranque de cada juego puede tardar algo más. Tus juegos y partidas no se tocan.")
            .soloSiEstaInstalada().app("CrossOver", "com.codeweavers.CrossOver"),
        Regla("crossover-steam-httpcache", "~/Library/Application Support/CrossOver/Bottles/*/drive_c/Program Files (x86)/Steam/appcache/httpcache",
              nombre: "Caché de descargas web de Steam para Windows (CrossOver)",
              detalle: "Imágenes y datos de la biblioteca que guarda el Steam de Windows de una botella.",
              consecuencia: "Steam la vuelve a crear. Tus juegos y partidas no se tocan.")
            .soloSiEstaInstalada().app("CrossOver", "com.codeweavers.CrossOver"),
        Regla("whisky-temp-windows", "~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/*/drive_c/windows/temp",
              nombre: "Temporales de Windows en Whisky",
              detalle: "Archivos temporales que dejan los programas de Windows dentro de tus botellas de Whisky.",
              consecuencia: "Nada: ningún programa los usa ya. Tus programas y partidas de la botella no se tocan.")
            .en(.temporales).hijos().edad(dias: 3).accesoTotal().sinArchivosAbiertos().soloSiEstaInstalada().app("Whisky", "com.isaacmarovitz.Whisky"),
        Regla("whisky-temp-usuario", "~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/*/drive_c/users/*/AppData/Local/Temp",
              nombre: "Temporales de usuario en Whisky",
              detalle: "Archivos temporales de instaladores y juegos de Windows en tus botellas de Whisky.",
              consecuencia: "Nada: ningún programa los usa ya. Tus programas y partidas de la botella no se tocan.")
            .en(.temporales).hijos().edad(dias: 3).accesoTotal().sinArchivosAbiertos().excepto("Public").soloSiEstaInstalada().app("Whisky", "com.isaacmarovitz.Whisky"),
        Regla("wine-temp-windows", "~/.wine/drive_c/windows/temp",
              nombre: "Temporales de Wine",
              detalle: "Archivos temporales que dejan los programas de Windows en tu prefijo de Wine.",
              consecuencia: "Nada: ningún programa los usa ya. Tus programas y partidas no se tocan.")
            .en(.temporales).hijos().edad(dias: 3).sinArchivosAbiertos().proceso("wineserver", patron: "wineserver"),
        Regla("wine-temp-usuario", "~/.wine/drive_c/users/*/AppData/Local/Temp",
              nombre: "Temporales de usuario de Wine",
              detalle: "Archivos temporales de instaladores y juegos de Windows en tu prefijo de Wine.",
              consecuencia: "Nada: ningún programa los usa ya. Tus programas y partidas no se tocan.")
            .en(.temporales).hijos().edad(dias: 3).sinArchivosAbiertos().excepto("Public").proceso("wineserver", patron: "wineserver"),
        Regla("wine-temp-usuario-antiguo", "~/.wine/drive_c/users/*/Temp",
              nombre: "Temporales de usuario de Wine (prefijos antiguos)",
              detalle: "Archivos temporales de instaladores y juegos de Windows en un prefijo de Wine creado con versiones antiguas.",
              consecuencia: "Nada: ningún programa los usa ya. Tus programas y partidas no se tocan.")
            .en(.temporales).hijos().edad(dias: 3).sinArchivosAbiertos().excepto("Public").proceso("wineserver", patron: "wineserver"),
        Regla("wine-complementos", "~/.cache/wine",
              nombre: "Instaladores de Wine Mono y Gecko",
              detalle: "Los instaladores de Mono y Gecko que Wine descargó al crear tus prefijos.",
              consecuencia: "Nada: ya están instalados. Si creas un prefijo nuevo, Wine los vuelve a descargar.")
            .en(.instaladores).proceso("wineserver", patron: "wineserver"),
        Regla("openemu-base-juegos", "~/Library/Application Support/OpenEmu/openvgdb.sqlite",
              nombre: "Base de datos de juegos de OpenEmu",
              detalle: "La base de datos (OpenVGDB) que OpenEmu descarga para reconocer tus juegos y sus portadas.",
              consecuencia: "OpenEmu la vuelve a descargar al abrirse. Tus juegos, partidas guardadas y capturas no se tocan.")
            .sinPreseleccion().soloSiEstaInstalada().app("OpenEmu", "org.openemu.OpenEmu"),
        Regla("dolphin-volcados", "~/Library/Application Support/Dolphin/Dump",
              nombre: "Volcados de Dolphin",
              detalle: "Texturas, fotogramas, audio y vídeo que Dolphin guarda cuando activas sus opciones de volcado (pueden ocupar varios GB).",
              consecuencia: "Perderás esos volcados. Si los activaste para crear un paquete de texturas o grabar un vídeo, revisa antes lo que quieras guardar. Tus partidas y texturas personalizadas no se tocan.")
            .revisar().soloSiEstaInstalada().app("Dolphin", "org.dolphin-emu.dolphin"),
        Regla("pcsx2-cache", "~/Library/Application Support/PCSX2/cache",
              nombre: "Caché de PCSX2",
              detalle: "Shaders y la lista de juegos que PCSX2 guarda para arrancar más rápido.",
              consecuencia: "PCSX2 los vuelve a crear; los juegos pueden dar tirones las primeras veces. Tus partidas y memory cards no se tocan.")
            .soloSiEstaInstalada().app("PCSX2", "net.pcsx2.pcsx2"),
        Regla("duckstation-cache", "~/Library/Application Support/DuckStation/cache",
              nombre: "Caché de DuckStation",
              detalle: "Shaders y la lista de juegos que DuckStation guarda para arrancar más rápido.",
              consecuencia: "DuckStation los vuelve a crear. Tus partidas y memory cards no se tocan.")
            .soloSiEstaInstalada().app("DuckStation", "com.github.stenzek.duckstation"),
        Regla("rpcs3-cache-hdd1", "~/Library/Application Support/rpcs3/dev_hdd1/caches",
              nombre: "Caché del disco de PS3 en RPCS3",
              detalle: "La partición de caché que los juegos de PS3 usan para cargar más rápido.",
              consecuencia: "Cada juego la vuelve a crear al arrancar (la primera carga irá más lenta). Tus partidas y juegos instalados no se tocan.")
            .sinPreseleccion().soloSiEstaInstalada().app("RPCS3", "net.rpcs3.rpcs3"),
        Regla("retroarch-miniaturas", "~/Library/Application Support/RetroArch/thumbnails",
              nombre: "Portadas descargadas de RetroArch",
              detalle: "Portadas y capturas de juegos que RetroArch descargó para tus listas.",
              consecuencia: "Puedes volver a descargarlas con Actualizador en línea › Actualizar miniaturas. Si pusiste portadas a mano, se perderán. Tus partidas no se tocan.")
            .revisar().soloSiEstaInstalada().app("RetroArch", "com.libretro.RetroArch"),
        Regla("retroarch-descargas", "~/Library/Application Support/RetroArch/downloads",
              nombre: "Descargas de RetroArch",
              detalle: "Archivos que bajaste con el actualizador en línea y el descargador de contenido de RetroArch.",
              consecuencia: "Puede haber juegos o contenido que descargaste desde RetroArch y que tus listas usan. Revisa antes lo que quieras conservar.")
            .en(.grandes).cuidado().soloSiEstaInstalada().app("RetroArch", "com.libretro.RetroArch"),
        Regla("retroarch-registros", "~/Documents/RetroArch/logs",
              nombre: "Registros de RetroArch",
              detalle: "Registros de RetroArch y de sus núcleos.",
              consecuencia: "Nada: solo son registros. Tus partidas guardadas y ajustes no se tocan.")
            .en(.registros).sinPreseleccion().app("RetroArch", "com.libretro.RetroArch"),
        Regla("azahar-shaders-vulkan", "~/Library/Application Support/Azahar/shaders/vulkan",
              nombre: "Caché de shaders de Azahar (Vulkan)",
              detalle: "Shaders que Azahar (emulador de 3DS) guarda para que los juegos no den tirones.",
              consecuencia: "Azahar los vuelve a compilar mientras juegas; al principio puede haber tirones. Tus partidas y los shaders de efectos que instalaste no se tocan.")
            .sinPreseleccion().soloSiEstaInstalada().app("Azahar"),
        Regla("azahar-shaders-opengl", "~/Library/Application Support/Azahar/shaders/opengl",
              nombre: "Caché de shaders de Azahar (OpenGL)",
              detalle: "Shaders que Azahar (emulador de 3DS) guarda para que los juegos no den tirones.",
              consecuencia: "Azahar los vuelve a compilar mientras juegas; al principio puede haber tirones. Tus partidas y los shaders de efectos que instalaste no se tocan.")
            .sinPreseleccion().soloSiEstaInstalada().app("Azahar"),
        Regla("citra-shaders-vulkan", "~/Library/Application Support/Citra/shaders/vulkan",
              nombre: "Caché de shaders de Citra (Vulkan)",
              detalle: "Shaders del emulador de 3DS Citra (antecesor de Azahar).",
              consecuencia: "Citra o Azahar los vuelven a compilar mientras juegas. Tus partidas y los shaders de efectos que instalaste no se tocan.")
            .sinPreseleccion().app("Citra"),
        Regla("citra-shaders-opengl", "~/Library/Application Support/Citra/shaders/opengl",
              nombre: "Caché de shaders de Citra (OpenGL)",
              detalle: "Shaders del emulador de 3DS Citra (antecesor de Azahar).",
              consecuencia: "Citra o Azahar los vuelven a compilar mientras juegas. Tus partidas y los shaders de efectos que instalaste no se tocan.")
            .sinPreseleccion().app("Citra"),
        Regla("ryujinx-cache", "~/Library/Application Support/Ryujinx/games/*/cache",
              nombre: "Caché de shaders y CPU de Ryujinx",
              detalle: "Shaders y código traducido que Ryujinx guarda de cada juego para que vaya fluido.",
              consecuencia: "Ryujinx los vuelve a generar mientras juegas; al principio habrá tirones. Tus partidas y claves no se tocan.")
            .revisar().soloSiEstaInstalada().app("Ryujinx"),
    ]
}
