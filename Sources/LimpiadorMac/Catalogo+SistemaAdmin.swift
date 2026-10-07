import Foundation

// Reglas del área «sistema-admin»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// Basura del sistema fuera de tu carpeta: se borra con la contraseña de administrador.
extension Catalogo {
    static let sistemaAdmin: [Regla] = [
        Regla("sistema-iconos-cache", "/Library/Caches/com.apple.iconservices.store",
              nombre: "Caché de iconos del sistema",
              detalle: "Copias de los iconos de todas tus apps que macOS guarda para dibujarlos rápido. Con los años puede crecer bastante.",
              consecuencia: "macOS la vuelve a crear. Durante un rato puede que veas iconos genéricos; se arregla solo o al reiniciar.")
            .admin().revisar(),
        Regla("sistema-caches-temporales", "/Library/Caches/*",
              nombre: "Temporales viejos en las cachés del sistema",
              detalle: "Archivos temporales y registros que programas del sistema dejaron en la carpeta de cachés compartida y que llevan más de una semana sin usarse.",
              consecuencia: "Nada: si un programa los necesita, los vuelve a crear.")
            .admin().sinPreseleccion().archivos("tmp", "log").edad(dias: 7).sinArchivosAbiertos().excepto("com.apple.containermanagerd", "com.apple.homed", "com.apple.HomeKit", "com.apple.ap.adprivacyd", "*ShortcutsSandboxCache", "FamilyCircle", "GIPPseudonymousID", "CCTClearcutLogger", "*Adobe*", "com.displaylink.*", "com.lasersoft-imaging.*", "com.crowdstrike.*", "com.sentinelone.*", "com.sentinel-labs.*", "com.eset.*", "com.jamf.*", "com.jamfsoftware.*", "com.paloaltonetworks.*", "com.cisco.anyconnect*", "com.cisco.secureclient*", "com.microsoft.autoupdate.helper", "com.apple.iconservices.store"),
        Regla("sistema-instalador-papelera", "/Library/InstallerSandboxes/.PKInstallSandboxManager/*.trashedSandbox",
              nombre: "Restos de instalaciones terminadas",
              detalle: "Copias temporales que el Instalador de macOS usó para instalar programas (.pkg) y que ya marcó para tirar.",
              consecuencia: "Nada: la instalación ya terminó y el Instalador no las vuelve a usar.")
            .admin().sinPreseleccion().edad(dias: 1).proceso("Instalador de macOS", patron: "installer"),
        Regla("sistema-instalador-huerfanos", "/Library/InstallerSandboxes/.PKInstallSandboxManager/*.orphanedSandbox",
              nombre: "Restos de instalaciones abandonadas",
              detalle: "Copias temporales de instalaciones de programas que el Instalador de macOS dejó huérfanas.",
              consecuencia: "Nada: el propio macOS las borraría si se quedara sin espacio.")
            .admin().sinPreseleccion().edad(dias: 1).proceso("Instalador de macOS", patron: "installer"),
        Regla("sistema-instalador-atascados", "/Library/InstallerSandboxes/.PKInstallSandboxManager/*.activeSandbox",
              nombre: "Instalaciones que se quedaron a medias",
              detalle: "Copias de instalaciones de programas (por ejemplo, actualizaciones de Xcode) que no terminaron y llevan días sin moverse. Pueden ocupar decenas de GB.",
              consecuencia: "Si esa instalación sigue en curso o se va a reintentar, empezará de cero y tendrás que repetirla.")
            .admin().revisar().edad(dias: 7).proceso("Instalador de macOS", patron: "packagekit.framework"),
        Regla("sistema-instalador-sin-usar", "/Library/InstallerSandboxes/.PKInstallSandboxManager/*.sandbox",
              nombre: "Instalaciones preparadas que no llegaron a hacerse",
              detalle: "Carpetas que el Instalador de macOS preparó para instalar un programa y que llevan más de una semana sin usarse.",
              consecuencia: "Si había una instalación preparada para más tarde, se cancelará y tendrás que repetirla.")
            .admin().revisar().edad(dias: 7).proceso("Instalador de macOS", patron: "packagekit.framework"),
        Regla("sistema-registros-asl", "/private/var/log",
              nombre: "Registros antiguos del sistema (formato ASL)",
              detalle: "Registros de mensajes, energía y diagnósticos que macOS guarda en su formato antiguo y que llevan más de un mes sin cambiar.",
              consecuencia: "Nada importante: solo pierdes registros de hace más de un mes (por ejemplo, inicios de sesión antiguos).")
            .admin().sinPreseleccion().archivos("asl").edad(dias: 30),
        Regla("sistema-registros-asl-archivados", "/private/var/log/asl.archive",
              nombre: "Archivo de registros antiguos",
              detalle: "Copias de registros antiguos que macOS guarda aparte porque alguien activó el archivado (suele hacerlo la empresa o un administrador).",
              consecuencia: "Pierdes registros antiguos que alguien decidió guardar. Si el Mac es de tu empresa, pregunta antes.")
            .admin().revisar().hijos().edad(dias: 30),
        Regla("sistema-descargas-aerial-atascadas", "/private/var/folders/zz/*/T/com.apple.idleassetsd/CFNetworkDownload_*.tmp",
              nombre: "Descargas atascadas de fondos de pantalla",
              detalle: "Vídeos de fondos y salvapantallas que macOS empezó a descargar y nunca terminó. A veces se acumulan cientos de GB.",
              consecuencia: "Nada: son descargas fallidas. macOS vuelve a descargar el vídeo si lo necesita.")
            .admin().sinPreseleccion().edad(dias: 7).sinArchivosAbiertos(),
        Regla("sistema-clones-de-firma", "/private/var/folders/*/*/X/*.code_sign_clone/code_sign_clone.*",
              nombre: "Copias de verificación de navegadores",
              detalle: "Copias que Chrome, Edge, Brave y otros navegadores parecidos hacen de sí mismos mientras están abiertos. Si el navegador se cerró mal, se quedan hasta que reinicias el Mac.",
              consecuencia: "Nada: solo se ofrecen con el navegador cerrado, y macOS las borraría al reiniciar.")
            .admin().sinPreseleccion().edad(dias: 1).sinArchivosAbiertos().excepto("com.crowdstrike.*", "com.sentinelone.*", "com.sentinel-labs.*", "com.eset.*", "com.jamf.*", "com.jamfsoftware.*", "com.paloaltonetworks.*", "com.cisco.anyconnect*", "com.cisco.secureclient*").app("Google Chrome", "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.chromium.Chromium", "company.thebrowser.Browser"),
        Regla("sistema-registros-adobe", "/Library/Logs/Adobe",
              nombre: "Registros de instalaciones de Adobe",
              detalle: "Registros que Adobe guarda al instalar y actualizar sus apps (incluye archivos .txt y .zip).",
              consecuencia: "Nada: solo se pierden registros de hace más de un mes.")
            .admin().sinPreseleccion().hijos().edad(dias: 30),
        Regla("sistema-registros-creativecloud", "/Library/Logs/CreativeCloud",
              nombre: "Registros de Creative Cloud",
              detalle: "Registros de la app Creative Cloud y de sus actualizaciones.",
              consecuencia: "Nada: solo se pierden registros de hace más de un mes.")
            .admin().sinPreseleccion().hijos().edad(dias: 30),
        Regla("sistema-registros-otros-formatos", "/Library/Logs",
              nombre: "Otros registros viejos de apps del sistema",
              detalle: "Informes de fallos, cuelgues y registros en texto que apps y controladores guardan para todo el Mac.",
              consecuencia: "Nada: solo se pierden registros de hace más de un mes.")
            .admin().sinPreseleccion().archivos("txt", "crash", "ips", "diag", "spin", "hang", "panic").edad(dias: 30),
        Regla("sistema-loops-apple", "/Library/Audio/Apple Loops/Apple",
              nombre: "Loops de GarageBand y Logic",
              detalle: "Fragmentos musicales que GarageBand o Logic Pro descargaron (de 2 a más de 10 GB).",
              consecuencia: "Si usas GarageBand o Logic, tendrás que volver a descargarlos desde la propia app. Si los usaste en canciones de otro programa de música, esas canciones se quedarán sin esos sonidos.")
            .admin().revisar().app("GarageBand", "com.apple.garageband10", "com.apple.logic10", "com.apple.mainstage3"),
        Regla("sistema-garageband-instrumentos", "/Library/Application Support/GarageBand/*",
              nombre: "Instrumentos de GarageBand",
              detalle: "Sonidos de instrumentos que GarageBand descargó. Las lecciones de «Aprende a tocar» no se tocan.",
              consecuencia: "Si usas GarageBand, tendrás que volver a descargar sus sonidos. Si ya no lo tienes, no pierdes nada.")
            .admin().revisar().excepto("Learn to Play").app("GarageBand", "com.apple.garageband10", "com.apple.logic10", "com.apple.mainstage3"),
        Regla("sistema-indice-loops", "/Library/Audio/Apple Loops Index",
              nombre: "Índice de loops de audio",
              detalle: "El índice que GarageBand y Logic usan para buscar loops rápido.",
              consecuencia: "Nada: la app lo vuelve a crear al abrir el explorador de loops.")
            .admin().sinPreseleccion().app("GarageBand", "com.apple.garageband10", "com.apple.logic10", "com.apple.mainstage3"),
        Regla("sistema-plugins-navegador", "/Library/Internet Plug-Ins/*plugin",
              nombre: "Complementos de navegador obsoletos",
              detalle: "Complementos antiguos (Flash, Java, Silverlight…) que ningún navegador actual puede usar. El de Java lleva dentro un Java completo.",
              consecuencia: "Nada en los navegadores. Si abres archivos .jnlp (Java Web Start) o algún programa muy antiguo los necesita, tendrás que reinstalar Java o ese programa.")
            .admin().revisar(),
        Regla("sistema-toolchains-swift", "/Library/Developer/Toolchains/swift-*-RELEASE.xctoolchain",
              nombre: "Versiones de Swift instaladas para todos los usuarios",
              detalle: "Versiones de Swift que instalaste aparte de Xcode, para todo el Mac. Se conserva la más nueva.",
              consecuencia: "Los proyectos que usen una de esas versiones dejarán de compilar con ella hasta que la vuelvas a instalar desde swift.org.")
            .admin().revisar().conservando(.versionMasAlta).proceso("Swift", patron: "/Library/Developer/Toolchains/"),
        Regla("sistema-kits-depuracion-kernel", "/Library/Developer/KDKs/*.kdk",
              nombre: "Kits de depuración del kernel antiguos",
              detalle: "Kits de Apple para depurar extensiones del sistema; cada uno sirve solo para una versión concreta de macOS. Se conservan el más nuevo y el de tu versión actual.",
              consecuencia: "Si vuelves a depurar en esa versión de macOS, tendrás que descargar el kit de nuevo desde developer.apple.com.")
            .admin().revisar().conservando(.versionMasAlta),
        Regla("sistema-gemas-descargadas", "/Library/Ruby/Gems/*/cache",
              nombre: "Paquetes descargados de RubyGems (sistema)",
              detalle: "Los archivos .gem que se descargaron al instalar gemas con sudo (por ejemplo, CocoaPods). Las gemas instaladas no se tocan.",
              consecuencia: "Nada: CocoaPods y las demás gemas siguen funcionando.")
            .admin().sinPreseleccion().proceso("RubyGems", patron: "/usr/bin/gem"),
        Regla("sistema-macports-compilaciones", "/opt/local/var/macports/build",
              nombre: "Compilaciones a medias de MacPorts",
              detalle: "Carpetas de trabajo que MacPorts deja al compilar programas, sobre todo cuando una instalación falla.",
              consecuencia: "Nada: es lo mismo que «port clean --work»; los programas instalados no se tocan.")
            .admin().sinPreseleccion().hijos().edad(dias: 1).proceso("MacPorts", patron: "/opt/local/bin/port"),
        Regla("sistema-macports-registros", "/opt/local/var/macports/logs",
              nombre: "Registros de compilación de MacPorts",
              detalle: "Registros que MacPorts guarda de los programas que no logró compilar.",
              consecuencia: "Nada: es lo mismo que «port clean --logs».")
            .admin().sinPreseleccion().hijos().edad(dias: 7).proceso("MacPorts", patron: "/opt/local/bin/port"),
        Regla("sistema-cache-de-contenidos", "/Library/Application Support/Apple/AssetCache/Data",
              nombre: "Caché de contenidos de Apple",
              detalle: "Copias de actualizaciones y apps que tu Mac guardó para compartirlas con otros dispositivos de tu red (Ajustes › General › Compartir › Caché de contenido).",
              consecuencia: "Tus otros dispositivos descargarán desde internet. Si vuelves a activar la función, la caché empieza de cero.")
            .admin().revisar().proceso("Caché de contenido de macOS", patron: "/usr/libexec/AssetCache/AssetCache"),
        Regla("sistema-sdks-clt-antiguos", "/Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk",
              nombre: "SDKs de macOS antiguos (herramientas de terminal)",
              detalle: "Versiones anteriores del SDK de macOS que se instalan junto a las herramientas de línea de comandos. Se conservan la más nueva y la de tu versión de macOS.",
              consecuencia: "Las herramientas de terminal usarán el SDK más nuevo. Si un proyecto pide esa versión exacta, no compilará. La próxima actualización de las herramientas puede volver a instalarlo.")
            .admin().revisar().conservando(.versionMasAlta).proceso("Herramientas de línea de comandos", patron: "/Library/Developer/CommandLineTools/"),
        Regla("xcode-paquetes-componentes", "~/Library/Developer/Packages",
              nombre: "Paquetes de componentes de Xcode descargados",
              detalle: "Instaladores de componentes de Xcode (soporte de dispositivos nuevos) que Xcode descargó y después instaló.",
              consecuencia: "Nada si ya están instalados; si Xcode los vuelve a necesitar, los descarga otra vez.")
            .en(.desarrollo).revisar().edad(dias: 7).app("Xcode", "com.apple.dt.Xcode"),
    ]
}
