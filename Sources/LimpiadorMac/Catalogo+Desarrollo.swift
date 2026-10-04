import Foundation

/// Herramientas de desarrollo, lenguajes, virtualización e IA que el análisis general no cubre.
extension Catalogo {
    static let desarrollo: [Regla] = [
        // MARK: Compiladores y lenguajes
        Regla("bazel-salidas", "/private/var/tmp/_bazel_*",
              nombre: "Compilaciones de Bazel",
              detalle: "Todo lo que Bazel compiló y descargó para tus proyectos (puede ocupar decenas de GB).",
              consecuencia: "La próxima compilación con Bazel empieza desde cero y vuelve a descargar las dependencias.")
            .en(.desarrollo).revisar().proceso("Bazel", patron: "bazel"),
        Regla("cargo-git-db", "~/.cargo/git/db",
              nombre: "Repositorios git de Cargo",
              detalle: "Copias de dependencias de Rust que vienen de repositorios git.",
              consecuencia: "Cargo las vuelve a descargar al compilar (necesita internet).")
            .en(.desarrollo).sinPreseleccion().proceso("Cargo", patron: "/cargo"),
        Regla("cargo-git-checkouts", "~/.cargo/git/checkouts",
              nombre: "Copias de trabajo git de Cargo",
              detalle: "Versiones extraídas de dependencias de Rust que vienen de git.",
              consecuencia: "Cargo las vuelve a extraer al compilar.")
            .en(.desarrollo).proceso("Cargo", patron: "/cargo"),
        Regla("rustup-descargas", "~/.rustup/downloads",
              nombre: "Descargas de rustup",
              detalle: "Paquetes de Rust que rustup descargó para instalar o actualizar.",
              consecuencia: "Nada: Rust ya está instalado.")
            .en(.desarrollo),
        Regla("rustup-temporales", "~/.rustup/tmp",
              nombre: "Temporales de rustup",
              detalle: "Archivos temporales de instalaciones de Rust.",
              consecuencia: "Nada.")
            .en(.desarrollo),
        Regla("rubygems-cache", "~/.gem/ruby/*/cache",
              nombre: "Paquetes descargados de RubyGems",
              detalle: "Los archivos .gem que se descargaron para instalar gemas (las gemas instaladas no se tocan).",
              consecuencia: "Nada: las gemas siguen instaladas; si hace falta, se vuelven a descargar.")
            .en(.desarrollo),
        Regla("bundler-cache", "~/.bundle/cache",
              nombre: "Caché de Bundler",
              detalle: "Gemas descargadas por Bundler.",
              consecuencia: "Bundler las vuelve a descargar si hacen falta.")
            .en(.desarrollo),
        Regla("composer-cache", "~/.composer/cache",
              nombre: "Caché de Composer",
              detalle: "Paquetes de PHP que descargó Composer.",
              consecuencia: "Composer los vuelve a descargar si hacen falta.")
            .en(.desarrollo),
        Regla("nuget-v3-cache", "~/.local/share/NuGet/v3-cache",
              nombre: "Caché de NuGet",
              detalle: "Índices de paquetes de .NET descargados.",
              consecuencia: "NuGet los vuelve a descargar.")
            .en(.desarrollo),
        Regla("nuget-http-cache", "~/.local/share/NuGet/http-cache",
              nombre: "Caché HTTP de NuGet",
              detalle: "Respuestas del servidor de paquetes de .NET.",
              consecuencia: "NuGet las vuelve a descargar.")
            .en(.desarrollo),
        Regla("nuget-plugins-cache", "~/.local/share/NuGet/plugins-cache",
              nombre: "Caché de plugins de NuGet",
              detalle: "Datos temporales de los plugins de NuGet.",
              consecuencia: "Se regeneran.")
            .en(.desarrollo),
        Regla("ivy-cache", "~/.ivy2/cache",
              nombre: "Caché de Ivy (sbt, Ant)",
              detalle: "Dependencias de Java y Scala descargadas.",
              consecuencia: "Se vuelven a descargar al compilar (necesita internet).")
            .en(.desarrollo).sinPreseleccion(),
        Regla("maven-wrapper", "~/.m2/wrapper/dists",
              nombre: "Versiones de Maven descargadas",
              detalle: "Maven descargado por el wrapper (mvnw) de tus proyectos.",
              consecuencia: "El wrapper lo vuelve a descargar la próxima vez que compiles.")
            .en(.desarrollo).sinPreseleccion(),
        Regla("kotlin-native-viejos", "~/.konan/kotlin-native-prebuilt-*",
              nombre: "Versiones antiguas de Kotlin/Native",
              detalle: "Compiladores de Kotlin/Native de versiones anteriores (se conserva la más nueva).",
              consecuencia: "Si un proyecto vuelve a pedir una de esas versiones, Gradle la descarga otra vez.")
            .en(.desarrollo).conservando(.versionMasAlta).proceso("Gradle", patron: "gradledaemon"),
        Regla("cabal-paquetes", "~/.cabal/packages",
              nombre: "Paquetes descargados de Cabal",
              detalle: "Paquetes de Haskell que descargó Cabal.",
              consecuencia: "Cabal los vuelve a descargar si hacen falta.")
            .en(.desarrollo).sinPreseleccion(),
        Regla("hex-paquetes", "~/.hex/packages",
              nombre: "Paquetes descargados de Hex",
              detalle: "Dependencias de Elixir descargadas.",
              consecuencia: "Mix las vuelve a descargar si hacen falta.")
            .en(.desarrollo),
        Regla("julia-compilado", "~/.julia/compiled",
              nombre: "Paquetes precompilados de Julia",
              detalle: "Versiones compiladas de los paquetes de Julia.",
              consecuencia: "Julia los vuelve a compilar la próxima vez que los cargues (tarda unos minutos).")
            .en(.desarrollo).sinPreseleccion(),
        Regla("pyenv-cache", "~/.pyenv/cache",
              nombre: "Descargas de pyenv",
              detalle: "Código fuente de Python que pyenv descargó para instalar versiones.",
              consecuencia: "Nada: las versiones de Python ya están instaladas.")
            .en(.desarrollo),
        Regla("node-gyp-antiguo", "~/.node-gyp",
              nombre: "Cabeceras de Node (node-gyp)",
              detalle: "Cabeceras de Node descargadas para compilar módulos nativos.",
              consecuencia: "Se vuelven a descargar si hacen falta.")
            .en(.desarrollo),
        Regla("pnpm-store-antiguo", "~/.pnpm-store",
              nombre: "Almacén de pnpm",
              detalle: "Paquetes descargados por pnpm (ubicación antigua).",
              consecuencia: "pnpm los vuelve a descargar. Los proyectos ya instalados siguen funcionando.")
            .en(.desarrollo).sinPreseleccion().proceso("pnpm", patron: "pnpm"),
        Regla("volta-descargas", "~/.volta/tools/inventory",
              nombre: "Descargas de Volta",
              detalle: "Instaladores de Node, npm y Yarn que Volta descargó.",
              consecuencia: "Nada: las versiones instaladas siguen funcionando.")
            .en(.desarrollo),
        Regla("prisma-motores", "~/.cache/prisma",
              nombre: "Motores de Prisma",
              detalle: "Binarios que Prisma descarga para cada versión.",
              consecuencia: "Prisma los vuelve a descargar al usarlo.")
            .en(.desarrollo),

        // MARK: Android y Xcode
        Regla("android-cmake-viejos", "~/Library/Android/sdk/cmake/*",
              nombre: "Versiones antiguas de CMake del SDK de Android",
              detalle: "Versiones de CMake que el SDK Manager descargó (se conserva la más nueva).",
              consecuencia: "Si un proyecto pide una de esas versiones, Android Studio la vuelve a descargar.")
            .en(.emuladores).conservando(.versionMasAlta).revisar()
            .app("Android Studio", "com.google.android.studio"),
        Regla("android-ndk-bundle", "~/Library/Android/sdk/ndk-bundle",
              nombre: "NDK antiguo (ndk-bundle)",
              detalle: "La ubicación antigua del NDK; las versiones actuales se instalan en sdk/ndk/<versión>.",
              consecuencia: "Solo los proyectos muy antiguos lo usan; si alguno lo necesita, instálalo de nuevo desde el SDK Manager.")
            .en(.emuladores).revisar().app("Android Studio", "com.google.android.studio"),
        Regla("xcode-xctest-devices", "~/Library/Developer/XCTestDevices",
              nombre: "Simuladores de pruebas de Xcode",
              detalle: "Copias de simuladores que Xcode crea para ejecutar pruebas en paralelo.",
              consecuencia: "Xcode las vuelve a crear la próxima vez que ejecutes pruebas.")
            .en(.desarrollo).app("Xcode", "com.apple.dt.Xcode"),
        Regla("xcode-macos-devicesupport", "~/Library/Developer/Xcode/macOS DeviceSupport/*",
              nombre: "Soporte de depuración de macOS antiguo",
              detalle: "Símbolos de versiones anteriores de macOS para depurar (se conserva la más nueva).",
              consecuencia: "Si depuras en una de esas versiones, Xcode los vuelve a copiar.")
            .en(.desarrollo).conservando(.versionMasAlta).app("Xcode", "com.apple.dt.Xcode"),
        Regla("xcode-toolchains", "~/Library/Developer/Toolchains/*.xctoolchain",
              nombre: "Toolchains de Swift instaladas",
              detalle: "Versiones de Swift que instalaste aparte de Xcode.",
              consecuencia: "Los proyectos que usen esa toolchain dejarán de compilar con ella hasta que la vuelvas a instalar.")
            .en(.desarrollo).revisar(),

        // MARK: Contenedores, máquinas virtuales y nube
        Regla("docker-registros", "~/Library/Containers/com.docker.docker/Data/log",
              nombre: "Registros de Docker Desktop",
              detalle: "Registros de Docker Desktop y de su máquina virtual.",
              consecuencia: "Nada: tus imágenes, contenedores y volúmenes no se tocan.")
            .en(.registros).accesoTotal().app("Docker", "com.docker.docker"),
        Regla("minikube-cache", "~/.minikube/cache",
              nombre: "Caché de minikube",
              detalle: "Imágenes y binarios de Kubernetes que descargó minikube.",
              consecuencia: "minikube los vuelve a descargar al crear un clúster.")
            .en(.desarrollo).proceso("minikube", patron: "minikube"),
        Regla("vagrant-temporales", "~/.vagrant.d/tmp",
              nombre: "Temporales de Vagrant",
              detalle: "Descargas y archivos temporales de Vagrant.",
              consecuencia: "Nada.")
            .en(.desarrollo).proceso("Vagrant", patron: "vagrant"),
        Regla("vagrant-boxes", "~/.vagrant.d/boxes",
              nombre: "Imágenes de Vagrant (boxes)",
              detalle: "Imágenes base de máquinas virtuales descargadas por Vagrant.",
              consecuencia: "Vagrant las vuelve a descargar cuando crees una máquina con ellas. Las máquinas ya creadas pueden necesitarlas.")
            .en(.desarrollo).revisar().proceso("Vagrant", patron: "vagrant"),
        Regla("terraform-plugins", "~/.terraform.d/plugin-cache",
              nombre: "Caché de proveedores de Terraform",
              detalle: "Proveedores de Terraform compartidos entre proyectos.",
              consecuencia: "«terraform init» los vuelve a descargar.")
            .en(.desarrollo).proceso("Terraform", patron: "terraform"),
        Regla("gcloud-registros", "~/.config/gcloud/logs",
              nombre: "Registros de Google Cloud CLI",
              detalle: "Registros de cada comando de gcloud.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros),
        Regla("azure-registros", "~/.azure/logs",
              nombre: "Registros de Azure CLI",
              detalle: "Registros de los comandos de Azure CLI.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros),
        Regla("azure-comandos", "~/.azure/commands",
              nombre: "Índice de comandos de Azure CLI",
              detalle: "Índice que Azure CLI genera para autocompletar comandos.",
              consecuencia: "Azure CLI lo vuelve a generar.")
            .en(.desarrollo),
        Regla("kubernetes-cache", "~/.kube/cache",
              nombre: "Caché de kubectl",
              detalle: "Datos que kubectl guarda sobre tus clústeres para responder más rápido.",
              consecuencia: "kubectl los vuelve a pedir al clúster.")
            .en(.desarrollo),

        // MARK: IA y datos
        Regla("whisper-modelos", "~/.cache/whisper",
              nombre: "Modelos de Whisper",
              detalle: "Modelos de reconocimiento de voz que descargó Whisper.",
              consecuencia: "Se vuelven a descargar la próxima vez que transcribas (pueden ser varios GB).")
            .en(.desarrollo).sinPreseleccion(),
        Regla("keras-datasets", "~/.keras/datasets",
              nombre: "Conjuntos de datos de Keras",
              detalle: "Datos de ejemplo que descargó Keras/TensorFlow.",
              consecuencia: "Se vuelven a descargar si un programa los usa.")
            .en(.desarrollo).sinPreseleccion(),
        Regla("sklearn-datos", "~/scikit_learn_data",
              nombre: "Conjuntos de datos de scikit-learn",
              detalle: "Datos de ejemplo que descargó scikit-learn.",
              consecuencia: "Se vuelven a descargar si un programa los usa.")
            .en(.desarrollo).sinPreseleccion(),
        Regla("lmstudio-modelos", "~/.lmstudio/models",
              nombre: "Modelos de LM Studio",
              detalle: "Modelos de IA que descargaste en LM Studio (suelen ocupar varios GB cada uno).",
              consecuencia: "Tendrás que volver a descargar en LM Studio los modelos que quieras usar.")
            .en(.desarrollo).revisar().app("LM Studio", "ai.elementlabs.lmstudio"),
        Regla("lmstudio-modelos-antiguo", "~/.cache/lm-studio/models",
              nombre: "Modelos de LM Studio (ubicación antigua)",
              detalle: "Modelos de IA que descargaste en versiones anteriores de LM Studio.",
              consecuencia: "Tendrás que volver a descargar en LM Studio los modelos que quieras usar.")
            .en(.desarrollo).revisar().app("LM Studio", "ai.elementlabs.lmstudio"),
    ]

    /// Descargas que no terminaron (navegadores): llevan días sin cambiar.
    static let descargas: [Regla] = [
        Regla("descargas-incompletas", "~/Downloads",
              nombre: "Descargas que no terminaron",
              detalle: "Archivos a medio descargar de Chrome, Safari, Firefox u Opera que llevan días sin avanzar.",
              consecuencia: "Si todavía los quieres, tendrás que descargarlos de nuevo desde el principio.")
            .en(.temporales).archivos("crdownload", "part", "download", "opdownload", "partial").edad(dias: 2).revisar(),
        Regla("escritorio-incompletas", "~/Desktop",
              nombre: "Descargas que no terminaron (Escritorio)",
              detalle: "Archivos a medio descargar en el Escritorio que llevan días sin avanzar.",
              consecuencia: "Si todavía los quieres, tendrás que descargarlos de nuevo desde el principio.")
            .en(.temporales).archivos("crdownload", "part", "download", "opdownload", "partial").edad(dias: 2).revisar(),
    ]
}
