import Foundation

// Reglas del área «dev-herramientas»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// Herramientas de desarrollo, IDEs y virtualización.
extension Catalogo {
    static let herramientasDev: [Regla] = [
        Regla("zed-servidores-lenguaje", "~/Library/Application Support/Zed/languages",
              nombre: "Servidores de lenguaje de Zed",
              detalle: "Programas que Zed descargó para entender cada lenguaje (autocompletado, errores, formato).",
              consecuencia: "Zed los vuelve a descargar la próxima vez que abras un archivo de ese lenguaje (necesita internet).")
            .en(.desarrollo).sinPreseleccion().soloSiEstaInstalada().app("Zed", "dev.zed.Zed", "dev.zed.Zed-Preview"),
        Regla("zed-node", "~/Library/Application Support/Zed/node",
              nombre: "Node.js descargado por Zed",
              detalle: "Una copia de Node.js y su caché de npm que Zed usa para sus extensiones y servidores de lenguaje.",
              consecuencia: "Zed vuelve a descargar Node.js la próxima vez que lo necesite.")
            .en(.desarrollo).soloSiEstaInstalada().app("Zed", "dev.zed.Zed", "dev.zed.Zed-Preview"),
        Regla("zed-servidores-remotos", "~/Library/Application Support/Zed/remote_servers",
              nombre: "Servidores remotos de Zed",
              detalle: "Copias del programa que Zed instala en otros equipos cuando trabajas por SSH.",
              consecuencia: "Si vuelves a conectarte a un servidor por SSH desde Zed, lo descarga otra vez.")
            .en(.desarrollo).soloSiEstaInstalada().app("Zed", "dev.zed.Zed", "dev.zed.Zed-Preview"),
        Regla("zed-trazas-bloqueos", "~/Library/Application Support/Zed/hang_traces",
              nombre: "Informes de bloqueos de Zed",
              detalle: "Trazas que Zed guarda cuando se queda congelado, para diagnosticar el problema.",
              consecuencia: "Nada: solo sirven para diagnosticar bloqueos antiguos.")
            .en(.registros).soloSiEstaInstalada().app("Zed", "dev.zed.Zed", "dev.zed.Zed-Preview"),
        Regla("zed-depuradores", "~/Library/Application Support/Zed/debug_adapters",
              nombre: "Depuradores descargados por Zed",
              detalle: "Adaptadores de depuración (por ejemplo CodeLLDB o el depurador de JavaScript) que Zed descargó.",
              consecuencia: "Zed los vuelve a descargar la próxima vez que depures un programa.")
            .en(.desarrollo).sinPreseleccion().soloSiEstaInstalada().app("Zed", "dev.zed.Zed", "dev.zed.Zed-Preview"),
        Regla("zed-agentes-externos", "~/Library/Application Support/Zed/external_agents",
              nombre: "Agentes de IA descargados por Zed",
              detalle: "Programas de agentes externos (Claude Code, Gemini CLI, Codex…) que Zed instaló para su panel de agentes.",
              consecuencia: "Zed los vuelve a descargar la próxima vez que abras ese agente. Tus sesiones y tu inicio de sesión se guardan en otra parte.")
            .en(.desarrollo).sinPreseleccion().soloSiEstaInstalada().app("Zed", "dev.zed.Zed", "dev.zed.Zed-Preview"),
        Regla("zed-copilot", "~/Library/Application Support/Zed/copilot",
              nombre: "Servidor de Copilot de Zed",
              detalle: "El programa de GitHub Copilot que Zed descargó para sugerir código.",
              consecuencia: "Zed lo vuelve a descargar si usas Copilot.")
            .en(.desarrollo).sinPreseleccion().soloSiEstaInstalada().app("Zed", "dev.zed.Zed", "dev.zed.Zed-Preview"),
        Regla("zed-prettier", "~/Library/Application Support/Zed/prettier",
              nombre: "Prettier de Zed",
              detalle: "La copia de Prettier que Zed instala para dar formato al código.",
              consecuencia: "Zed la vuelve a instalar la próxima vez que des formato a un archivo.")
            .en(.desarrollo).soloSiEstaInstalada().app("Zed", "dev.zed.Zed", "dev.zed.Zed-Preview"),
        Regla("zed-extensiones-trabajo", "~/Library/Application Support/Zed/extensions/work",
              nombre: "Descargas de las extensiones de Zed",
              detalle: "Servidores de lenguaje y herramientas que tus extensiones de Zed descargaron.",
              consecuencia: "Cada extensión vuelve a descargar lo que necesite. Las extensiones siguen instaladas.")
            .en(.desarrollo).sinPreseleccion().soloSiEstaInstalada().app("Zed", "dev.zed.Zed", "dev.zed.Zed-Preview"),
        Regla("zed-extensiones-compilacion", "~/Library/Application Support/Zed/extensions/build",
              nombre: "Compilación de extensiones de Zed",
              detalle: "Herramientas (como el SDK de WebAssembly) que Zed descargó para compilar extensiones en desarrollo.",
              consecuencia: "Si desarrollas una extensión de Zed, se vuelven a descargar al compilarla.")
            .en(.desarrollo).soloSiEstaInstalada().app("Zed", "dev.zed.Zed", "dev.zed.Zed-Preview"),
        Regla("claude-sentry", "~/Library/Application Support/Claude/sentry",
              nombre: "Informes de errores pendientes de Claude",
              detalle: "Informes de fallos que la app Claude guarda para enviarlos a sus desarrolladores.",
              consecuencia: "Nada: solo se pierden informes de errores antiguos.")
            .en(.registros).soloSiEstaInstalada().app("Claude", "com.anthropic.claudefordesktop"),
        Regla("copilot-cli-registros", "~/.copilot/logs",
              nombre: "Registros de GitHub Copilot CLI",
              detalle: "Registros de cada sesión de Copilot en la terminal.",
              consecuencia: "Nada: solo son registros. Tus sesiones y tu configuración no se tocan.")
            .en(.desarrollo),
        Regla("codeium-servidores-viejos", "~/.codeium/bin/*",
              nombre: "Versiones viejas del servidor de Codeium",
              detalle: "Copias anteriores del programa de autocompletado de Codeium/Windsurf (se conserva la más reciente).",
              consecuencia: "Nada: el editor usa la versión más nueva; si alguno pide una vieja, la vuelve a descargar.")
            .en(.desarrollo).conservando(.masReciente).proceso("Codeium", patron: "language_server_macos"),
        Regla("supermaven-versiones-viejas", "~/.supermaven/binary/*",
              nombre: "Versiones viejas de Supermaven",
              detalle: "Copias anteriores del agente de autocompletado de Supermaven (se conserva la más nueva).",
              consecuencia: "Nada: el editor usa la versión más nueva.")
            .en(.desarrollo).conservando(.versionMasAlta).proceso("Supermaven", patron: "sm-agent"),
        Regla("continue-chromium", "~/.continue/.utils/.chromium-browser-snapshots",
              nombre: "Navegador descargado por Continue",
              detalle: "Una copia de Chromium que Continue descarga para leer documentación web.",
              consecuencia: "Continue lo vuelve a descargar si indexas documentación otra vez.")
            .en(.desarrollo).proceso("Continue", patron: ".chromium-browser-snapshots"),
        Regla("continue-registros", "~/.continue/logs",
              nombre: "Registros de Continue",
              detalle: "Registros de la extensión de IA Continue (core.log, prompt.log).",
              consecuencia: "Nada: solo son registros.")
            .en(.desarrollo),
        Regla("cursor-agent-registros", "~/.local/share/cursor-agent",
              nombre: "Registros viejos de Cursor Agent",
              detalle: "Registros de sesiones del agente de Cursor en la terminal con más de una semana.",
              consecuencia: "Nada: solo son registros.")
            .en(.desarrollo).archivos("log").edad(dias: 7),
        Regla("vscode-cli-servidores", "~/.vscode/cli/servers/Stable-*",
              nombre: "Servidores viejos de VS Code (túneles)",
              detalle: "Copias del servidor de VS Code que se descargan al usar «code tunnel» o «code serve-web» (se conserva la más reciente).",
              consecuencia: "Si vuelves a usar una versión anterior por túnel, VS Code la descarga otra vez.")
            .en(.desarrollo).conservando(.masReciente).proceso("VS Code (túnel)", patron: "/.vscode/cli/servers/"),
        Regla("chrome-devtools-mcp-caches", "~/.cache/chrome-devtools-mcp/chrome-profile*/Default/*Cache",
              nombre: "Caché del navegador de Chrome DevTools MCP",
              detalle: "Caché del Chrome que usan los agentes de IA a través de Chrome DevTools MCP.",
              consecuencia: "Ese navegador la vuelve a crear. Las sesiones iniciadas en él no se tocan.")
            .en(.desarrollo).proceso("Chrome DevTools MCP", patron: "chrome-devtools-mcp/chrome-profile"),
        Regla("antigravity-perfil-caches", "~/.gemini/antigravity-browser-profile/Default/*Cache",
              nombre: "Caché del navegador de Antigravity",
              detalle: "Caché del Chrome que el editor Antigravity usa para que su agente navegue.",
              consecuencia: "Antigravity la vuelve a crear. Las sesiones iniciadas en ese navegador no se tocan.")
            .proceso("Antigravity", patron: "antigravity-browser-profile"),
        Regla("docker-scout-sbom", "~/.docker/scout/sbom",
              nombre: "Caché de Docker Scout",
              detalle: "Inventarios de software (SBOM) de imágenes que Docker Scout analizó.",
              consecuencia: "Docker Scout los vuelve a generar al analizar una imagen. Es lo mismo que «docker scout cache prune --sboms».")
            .en(.desarrollo).proceso("Docker Scout", patron: "docker-scout"),
        Regla("orbstack-registros", "~/.orbstack/log",
              nombre: "Registros de OrbStack",
              detalle: "Registros de OrbStack y de su máquina virtual.",
              consecuencia: "Nada: tus contenedores, imágenes y máquinas Linux no se tocan.")
            .en(.desarrollo).hijos().app("OrbStack", "dev.kdrag0n.MacVirt"),
        Regla("lima-registros", "~/.lima",
              nombre: "Registros de las máquinas de Lima",
              detalle: "Registros de consola y del agente de cada máquina virtual de Lima (serial.log, ha.stderr.log…).",
              consecuencia: "Nada: las máquinas virtuales y sus discos no se tocan.")
            .en(.desarrollo).archivos("log").proceso("Lima", patron: "limactl"),
        Regla("colima-registros", "~/.colima/_lima",
              nombre: "Registros de las máquinas de Colima",
              detalle: "Registros de consola y del agente de la máquina virtual de Colima.",
              consecuencia: "Nada: tus contenedores, imágenes y discos no se tocan.")
            .en(.desarrollo).archivos("log").proceso("Colima", patron: "limactl"),
        Regla("podman-imagenes-descargadas", "~/.local/share/containers/podman/machine/*/cache",
              nombre: "Imágenes descargadas de Podman",
              detalle: "Imágenes comprimidas de la máquina virtual de Podman que ya se usaron para crearla.",
              consecuencia: "La próxima vez que crees una máquina con «podman machine init», se vuelve a descargar (alrededor de 1 GB). Tus máquinas actuales no se tocan.")
            .en(.desarrollo).sinPreseleccion().proceso("Podman", patron: "podman"),
        Regla("virtualbox-registros-vm", "~/VirtualBox VMs/*/Logs",
              nombre: "Registros de máquinas de VirtualBox",
              detalle: "Registros (VBox.log y sus copias .1 a .3) de cada máquina virtual de VirtualBox.",
              consecuencia: "Nada: las máquinas virtuales, sus discos y sus instantáneas no se tocan.")
            .en(.registros).app("VirtualBox", "org.virtualbox.app.VirtualBox"),
        Regla("virtualbox-registros-globales", "~/Library/VirtualBox/*.log*",
              nombre: "Registros de VirtualBox",
              detalle: "Registros del servicio de VirtualBox (VBoxSVC.log y sus copias anteriores).",
              consecuencia: "Nada: tu configuración (VirtualBox.xml) y tus máquinas no se tocan.")
            .en(.registros).app("VirtualBox", "org.virtualbox.app.VirtualBox"),
        Regla("vmware-registros", "~/Virtual Machines.localized/*.vmwarevm/vmware*.log",
              nombre: "Registros de máquinas de VMware Fusion",
              detalle: "Registros (vmware.log, vmware-0.log…) que VMware Fusion guarda dentro de cada máquina virtual.",
              consecuencia: "Nada: la máquina virtual y sus discos no se tocan.")
            .en(.registros).app("VMware Fusion", "com.vmware.fusion"),
        Regla("vmware-registros-documentos", "~/Documents/Virtual Machines.localized/*.vmwarevm/vmware*.log",
              nombre: "Registros de máquinas de VMware Fusion (Documentos)",
              detalle: "Registros de las máquinas virtuales de VMware Fusion guardadas en Documentos (ubicación de versiones antiguas).",
              consecuencia: "Nada: la máquina virtual y sus discos no se tocan.")
            .en(.registros).sinPreseleccion().app("VMware Fusion", "com.vmware.fusion"),
        Regla("parallels-registros-vm", "~/Parallels/*.pvm/parallels.log*",
              nombre: "Registros de máquinas de Parallels",
              detalle: "Registros que Parallels Desktop guarda dentro de cada máquina virtual.",
              consecuencia: "Nada: la máquina virtual, sus discos y sus instantáneas no se tocan.")
            .en(.registros).app("Parallels Desktop", "com.parallels.desktop.console"),
        Regla("gcloud-copia-anterior", "~/google-cloud-sdk/.install/.backup",
              nombre: "Copia anterior de Google Cloud CLI",
              detalle: "La versión completa anterior de gcloud que se guardó al actualizar, por si querías volver atrás.",
              consecuencia: "Ya no podrás usar «gcloud components restore» para volver a la versión anterior. gcloud sigue funcionando igual.")
            .en(.desarrollo).proceso("Google Cloud CLI", patron: "google-cloud-sdk"),
        Regla("gcloud-papelera", "~/google-cloud-sdk/.install/.trash",
              nombre: "Papelera de Google Cloud CLI",
              detalle: "Una instalación de gcloud que se apartó después de restaurar una copia anterior.",
              consecuencia: "Nada: gcloud ya no la usa.")
            .en(.desarrollo).proceso("Google Cloud CLI", patron: "google-cloud-sdk"),
        Regla("gcloud-copia-anterior-homebrew", "/opt/homebrew/share/google-cloud-sdk/.install/.backup",
              nombre: "Copia anterior de Google Cloud CLI (Homebrew)",
              detalle: "La versión anterior de gcloud (instalada con Homebrew) que se guardó al actualizar sus componentes, por si querías volver atrás.",
              consecuencia: "Ya no podrás usar «gcloud components restore» para volver a la versión anterior. gcloud sigue funcionando igual.")
            .admin().sinPreseleccion().proceso("Google Cloud CLI", patron: "google-cloud-sdk"),
        Regla("azure-functions-bundles", "~/.azure-functions-core-tools/Functions/ExtensionBundles",
              nombre: "Paquetes de extensiones de Azure Functions",
              detalle: "Paquetes de extensiones que Azure Functions Core Tools descarga para ejecutar funciones en local (se acumulan versiones).",
              consecuencia: "La próxima vez que ejecutes «func start», se descarga la versión que pida tu proyecto (necesita internet).")
            .en(.desarrollo).sinPreseleccion().proceso("Azure Functions Core Tools", patron: "azure-functions-core-tools"),
        Regla("eclipse-oomph-cache", "~/.eclipse/org.eclipse.oomph.p2/cache",
              nombre: "Caché del instalador de Eclipse",
              detalle: "Índices y archivos que el instalador de Eclipse (Oomph) descargó al instalar o actualizar.",
              consecuencia: "Se vuelven a descargar la próxima vez que instales o actualices Eclipse. Tus instalaciones y espacios de trabajo no se tocan.")
            .en(.desarrollo).app("Eclipse", "org.eclipse.platform.ide", "org.eclipse.oomph.setup.installer.product"),
        Regla("sublime-indice", "~/Library/Application Support/Sublime Text*/Index",
              nombre: "Índice de símbolos de Sublime Text",
              detalle: "El índice que Sublime Text crea de tus archivos para «Ir a definición».",
              consecuencia: "Sublime Text vuelve a indexar tus proyectos en segundo plano al abrirlos.")
            .en(.desarrollo).soloSiEstaInstalada().app("Sublime Text", "com.sublimetext.4", "com.sublimetext.3"),
        Regla("xcode-productos", "~/Library/Developer/Xcode/Products",
              nombre: "Productos de compilación de Xcode",
              detalle: "Copias de apps y datos que Xcode guarda fuera de DerivedData (por ejemplo, para el Organizador).",
              consecuencia: "Xcode vuelve a generar o descargar lo que necesite; si guardaste algo aquí a propósito desde el Organizador, se pierde.")
            .en(.desarrollo).revisar().app("Xcode", "com.apple.dt.Xcode"),
        Regla("xcode-otras-caches", "~/Library/Caches/com.apple.dt.*",
              nombre: "Otras cachés de herramientas de Xcode",
              detalle: "Cachés de Instruments, xcodebuild, control de versiones y demás herramientas de Xcode.",
              consecuencia: "Xcode y sus herramientas las vuelven a crear.")
            .en(.desarrollo).excepto("com.apple.dt.Xcode").app("Xcode", "com.apple.dt.Xcode"),
        Regla("xcode-docsets-antiguos", "~/Library/Developer/Shared/Documentation/DocSets",
              nombre: "Documentación antigua de Xcode (docsets)",
              detalle: "Documentación en formato antiguo (docsets) de Xcode 8 o anterior, o generada por herramientas como appledoc.",
              consecuencia: "Las versiones actuales de Xcode no la usan. Si generaste documentación de tus proyectos con appledoc o la consultas en Dash, revísala antes.")
            .en(.desarrollo).revisar().app("Xcode", "com.apple.dt.Xcode"),
        Regla("xcodes-descargas", "~/Library/Application Support/com.robotsandpencils.XcodesApp",
              nombre: "Descargas de Xcode que quedaron (Xcodes)",
              detalle: "Archivos .xip de Xcode (de 7 a 12 GB) y descargas a medias que la app Xcodes dejó tras una instalación interrumpida.",
              consecuencia: "Si querías instalar esa versión, Xcodes la vuelve a descargar.")
            .en(.desarrollo).archivos("xip", "aria2", "dmg").edad(dias: 2).app("Xcodes", "com.robotsandpencils.XcodesApp"),
        Regla("xcodes-cli-descargas", "~/Library/Application Support/com.robotsandpencils.xcodes",
              nombre: "Descargas de Xcode que quedaron (xcodes en terminal)",
              detalle: "Archivos .xip de Xcode y descargas a medias del comando xcodes.",
              consecuencia: "Si querías instalar esa versión, xcodes la vuelve a descargar.")
            .en(.desarrollo).archivos("xip", "aria2").edad(dias: 2).proceso("xcodes", patron: "xcodes"),
        Regla("android-haxm", "~/Library/Android/sdk/extras/intel",
              nombre: "Intel HAXM (acelerador obsoleto)",
              detalle: "El acelerador de emuladores de Intel, que no funciona en Macs con Apple Silicon ni en macOS 11 o posterior.",
              consecuencia: "Nada: el emulador usa el acelerador de macOS (Hypervisor.Framework).")
            .en(.emuladores).app("Android Studio", "com.google.android.studio"),
        Regla("android-m2repository-android", "~/Library/Android/sdk/extras/android/m2repository",
              nombre: "Android Support Repository (obsoleto)",
              detalle: "Repositorio local de librerías de soporte de Android que se usaba antes de 2017; hoy se descargan de Google Maven.",
              consecuencia: "Solo lo usan proyectos muy antiguos que compilen sin internet; los actuales descargan esas librerías solos.")
            .en(.emuladores).revisar().app("Android Studio", "com.google.android.studio"),
        Regla("android-m2repository-google", "~/Library/Android/sdk/extras/google/m2repository",
              nombre: "Google Repository (obsoleto)",
              detalle: "Repositorio local antiguo de librerías de Google Play Services y Firebase; hoy se descargan de Google Maven.",
              consecuencia: "Solo lo usan proyectos muy antiguos; los actuales descargan esas librerías solos.")
            .en(.emuladores).revisar().app("Android Studio", "com.google.android.studio"),
        Regla("android-add-ons", "~/Library/Android/sdk/add-ons",
              nombre: "Complementos antiguos del SDK de Android",
              detalle: "Complementos «Google APIs» para versiones muy antiguas de Android (API 23 o anterior).",
              consecuencia: "Solo los usan proyectos que compilan contra versiones muy antiguas de Android.")
            .en(.emuladores).revisar().app("Android Studio", "com.google.android.studio"),
        Regla("android-sdk-temp", "~/Library/Android/sdk/temp",
              nombre: "Temporales antiguos del SDK de Android",
              detalle: "Descargas (.zip) que dejó el SDK Manager antiguo.",
              consecuencia: "Nada: el SDK Manager actual usa otra carpeta (.temp).")
            .en(.emuladores).app("Android Studio", "com.google.android.studio"),
        Regla("java-volcados-ide", "~/java_error_in_*.hprof",
              nombre: "Volcados de memoria de IntelliJ/Android Studio",
              detalle: "Copias de la memoria que el IDE guardó cuando se quedó sin memoria (suelen ocupar varios GB).",
              consecuencia: "Nada: solo sirven para diagnosticar ese fallo.")
            .en(.registros).edad(dias: 1),
        Regla("java-informes-error-ide", "~/java_error_in_*.log",
              nombre: "Informes de fallo de IntelliJ/Android Studio",
              detalle: "Informes que el IDE escribe en tu carpeta personal cuando su Java falla.",
              consecuencia: "Nada: solo sirven para diagnosticar ese fallo.")
            .en(.registros).edad(dias: 1),
        Regla("java-hs-err", "~/hs_err_pid*.log",
              nombre: "Informes de fallo de Java",
              detalle: "Informes que deja cualquier programa de Java cuando falla (Gradle, Android Studio, herramientas de terminal).",
              consecuencia: "Nada: solo sirven para diagnosticar ese fallo.")
            .en(.registros).edad(dias: 1),
        Regla("ollama-registros", "~/.ollama/logs",
              nombre: "Registros de Ollama",
              detalle: "Registros del servidor de Ollama (server.log y sus copias anteriores).",
              consecuencia: "Nada: tus modelos no se tocan.")
            .en(.registros).proceso("Ollama", patron: "ollama"),
        Regla("kubectl-http-cache-antigua", "~/.kube/http-cache",
              nombre: "Caché antigua de kubectl",
              detalle: "Respuestas de los clústeres de Kubernetes que guardaban versiones antiguas de kubectl.",
              consecuencia: "Nada: kubectl vuelve a pedir los datos al clúster. Tu configuración (~/.kube/config) no se toca.")
            .en(.desarrollo),
        Regla("sdkman-temporales", "~/.sdkman/tmp",
              nombre: "Descargas temporales de SDKMAN",
              detalle: "Archivos que SDKMAN descargó para instalar Java, Gradle, Kotlin y otras herramientas.",
              consecuencia: "Nada: las versiones ya instaladas siguen funcionando. Es lo mismo que «sdk flush tmp».")
            .en(.desarrollo).hijos().edad(dias: 1).sinArchivosAbiertos(),
        Regla("sdkman-archivos-antiguos", "~/.sdkman/archives",
              nombre: "Instaladores guardados por SDKMAN",
              detalle: "Copias comprimidas de herramientas que versiones anteriores de SDKMAN guardaban tras instalarlas.",
              consecuencia: "Nada: las herramientas ya están instaladas.")
            .en(.desarrollo),
        Regla("gradle-build-scan", "~/.gradle/build-scan-data",
              nombre: "Datos de Build Scan de Gradle",
              detalle: "Datos de informes de compilación (Build Scan/Develocity) que Gradle guardó en local.",
              consecuencia: "Nada: solo se pierden datos de informes de compilaciones pasadas.")
            .en(.desarrollo).proceso("Gradle", patron: "gradledaemon"),
    ]
}
