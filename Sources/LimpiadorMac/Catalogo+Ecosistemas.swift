import Foundation

// Reglas del área «dev-ecosistemas»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// Cachés globales de lenguajes y gestores de paquetes.
extension Catalogo {
    static let ecosistemas: [Regla] = [
        Regla("coursier-cache-antigua", "~/.coursier/cache",
              nombre: "Caché antigua de Coursier",
              detalle: "Dependencias de Scala en la ubicación que usaban versiones antiguas de Coursier y sbt.",
              consecuencia: "Nada si ya usas versiones nuevas; si alguna herramienta antigua la necesita, vuelve a descargar lo que falte.")
            .en(.desarrollo).sinPreseleccion().proceso("Coursier", patron: "coursier"),
        Regla("sbt-boot", "~/.sbt/boot",
              nombre: "Versiones de sbt descargadas",
              detalle: "Copias de sbt y de Scala que el lanzador de sbt descargó para cada versión que usaron tus proyectos.",
              consecuencia: "La próxima vez que abras un proyecto de Scala, sbt descarga la versión que necesite.")
            .en(.desarrollo).sinPreseleccion().proceso("sbt", patron: "sbt-launch"),
        Regla("sbt-zinc", "~/.sbt/*/zinc",
              nombre: "Puentes de compilador de sbt (Zinc)",
              detalle: "Piezas del compilador de Scala que sbt compila una vez por versión.",
              consecuencia: "sbt las vuelve a compilar la primera vez que compiles (tarda un poco).")
            .en(.desarrollo).proceso("sbt", patron: "sbt-launch"),
        Regla("sbt-staging", "~/.sbt/*/staging",
              nombre: "Plugins de sbt descargados desde git",
              detalle: "Copias de plugins de sbt que se descargan desde repositorios git.",
              consecuencia: "sbt los vuelve a descargar al abrir el proyecto.")
            .en(.desarrollo).proceso("sbt", patron: "sbt-launch"),
        Regla("mill-descargas", "~/.cache/mill/download",
              nombre: "Versiones de Mill descargadas",
              detalle: "Copias de la herramienta de compilación Mill (Scala/Java) que su lanzador descargó.",
              consecuencia: "El lanzador vuelve a descargar la versión que pida cada proyecto.")
            .en(.desarrollo).proceso("Mill", patron: "/.cache/mill/"),
        Regla("jbang-cache-urls", "~/.jbang/cache/urls",
              nombre: "Archivos descargados por JBang",
              detalle: "Scripts y archivos remotos que JBang descargó para ejecutarlos.",
              consecuencia: "JBang vuelve a descargar y compilar lo que necesite.")
            .en(.desarrollo).sinPreseleccion().proceso("JBang", patron: "jbang"),
        Regla("jbang-cache-jars", "~/.jbang/cache/jars",
              nombre: "Scripts compilados por JBang",
              detalle: "Versiones ya compiladas de los scripts de Java que ejecutaste con JBang.",
              consecuencia: "JBang vuelve a descargar y compilar lo que necesite.")
            .en(.desarrollo).sinPreseleccion().proceso("JBang", patron: "jbang"),
        Regla("jbang-cache-scripts", "~/.jbang/cache/scripts",
              nombre: "Scripts preparados por JBang",
              detalle: "Copias de scripts que JBang guardó para ejecutarlos.",
              consecuencia: "JBang vuelve a descargar y compilar lo que necesite.")
            .en(.desarrollo).sinPreseleccion().proceso("JBang", patron: "jbang"),
        Regla("jbang-jdks", "~/.jbang/cache/jdks",
              nombre: "Versiones de Java de JBang",
              detalle: "Versiones de Java (JDK) que JBang descargó para ejecutar scripts.",
              consecuencia: "JBang las vuelve a descargar cuando las necesite. Si usas ese Java fuera de JBang (~/.jbang/currentjdk), dejará de funcionar hasta que lo reinstales.")
            .en(.desarrollo).revisar().proceso("JBang", patron: "jbang"),
        Regla("clojure-gitlibs", "~/.gitlibs",
              nombre: "Dependencias git de Clojure",
              detalle: "Copias de librerías de Clojure que vienen de repositorios git (tools.deps).",
              consecuencia: "Se vuelven a descargar; si un proyecto no arranca, ejecuta «clj -Sforce» una vez.")
            .en(.desarrollo).revisar().proceso("Clojure", patron: "clojure"),
        Regla("lein-versiones-viejas", "~/.lein/self-installs",
              nombre: "Versiones antiguas de Leiningen",
              detalle: "Copias de Leiningen de versiones anteriores (se conserva la más nueva).",
              consecuencia: "Si vuelves a usar una versión antigua, se descarga sola.")
            .en(.desarrollo).hijos(conservar: .versionMasAlta).proceso("Leiningen", patron: "leiningen"),
        Regla("konan-cache", "~/.konan/cache",
              nombre: "Descargas de Kotlin/Native",
              detalle: "Archivos comprimidos de herramientas (LLVM, librerías) que Kotlin/Native descargó y ya descomprimió.",
              consecuencia: "Nada: lo descomprimido sigue en su sitio.")
            .en(.desarrollo).proceso("Gradle", patron: "gradledaemon"),
        Regla("konan-dependencias", "~/.konan/dependencies",
              nombre: "Herramientas de Kotlin/Native",
              detalle: "LLVM y librerías de sistema que usa Kotlin Multiplatform para compilar para iOS y macOS.",
              consecuencia: "La próxima compilación para iOS las vuelve a descargar (alrededor de 1 GB).")
            .en(.desarrollo).revisar().proceso("Gradle", patron: "gradledaemon"),
        Regla("dotnet-telemetria", "~/.dotnet/TelemetryStorageService",
              nombre: "Telemetría pendiente de .NET",
              detalle: "Datos de uso del SDK de .NET que no se llegaron a enviar.",
              consecuencia: "Nada: solo se pierden esos datos de uso.")
            .en(.desarrollo).proceso(".NET", patron: "dotnet"),
        Regla("dotnet-plantillas", "~/.templateengine",
              nombre: "Plantillas de «dotnet new»",
              detalle: "Caché e instalaciones de plantillas de proyectos de .NET.",
              consecuencia: "Las plantillas que instalaste con «dotnet new install» tendrás que volver a instalarlas; las que vienen con el SDK se regeneran solas.")
            .en(.desarrollo).revisar().proceso(".NET", patron: "dotnet"),
        Regla("nuget-scratch", "$TEMPORAL/NuGetScratch",
              nombre: "Temporales de NuGet",
              detalle: "Archivos temporales de las restauraciones de paquetes de .NET.",
              consecuencia: "Nada: NuGet crea otros cuando los necesita.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().proceso(".NET", patron: "dotnet"),
        Regla("ghcup-cache", "~/.ghcup/cache",
              nombre: "Descargas de GHCup",
              detalle: "Instaladores de GHC, Cabal y HLS que GHCup descargó, y su lista de versiones.",
              consecuencia: "Nada: lo instalado sigue funcionando. Es lo mismo que «ghcup gc --cache».")
            .en(.desarrollo).proceso("GHCup", patron: "/.ghcup/"),
        Regla("ghcup-registros", "~/.ghcup/logs",
              nombre: "Registros de GHCup",
              detalle: "Registros de las instalaciones de GHC y otras herramientas de Haskell.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).proceso("GHCup", patron: "/.ghcup/"),
        Regla("ghcup-temporales", "~/.ghcup/tmp",
              nombre: "Temporales de GHCup",
              detalle: "Restos de instalaciones de Haskell que no terminaron.",
              consecuencia: "Nada: son restos de instalaciones. Es lo mismo que «ghcup gc --tmpdirs».")
            .en(.desarrollo).edad(dias: 1).sinArchivosAbiertos().proceso("GHCup", patron: "/.ghcup/"),
        Regla("ghcup-papelera", "~/.ghcup/trash",
              nombre: "Papelera de GHCup",
              detalle: "Versiones de herramientas de Haskell que GHCup ya desinstaló pero no pudo borrar del todo.",
              consecuencia: "Nada: GHCup ya no usa esas versiones.")
            .en(.desarrollo).proceso("GHCup", patron: "/.ghcup/"),
        Regla("stack-snapshots", "~/.stack/snapshots",
              nombre: "Paquetes de Haskell compilados por Stack",
              detalle: "Librerías precompiladas de cada snapshot que usaron tus proyectos de Stack.",
              consecuencia: "Stack las vuelve a compilar cuando un proyecto las necesite (puede tardar bastante).")
            .en(.desarrollo).sinPreseleccion().proceso("Stack", patron: "/.stack/"),
        Regla("stack-pantry", "~/.stack/pantry",
              nombre: "Índice y paquetes descargados por Stack",
              detalle: "El índice de Hackage y los paquetes de Haskell que Stack descargó.",
              consecuencia: "Stack vuelve a descargar el índice y los paquetes (necesita internet).")
            .en(.desarrollo).sinPreseleccion().proceso("Stack", patron: "/.stack/"),
        Regla("stack-instaladores", "~/.stack/programs/*/*.tar.*",
              nombre: "Instaladores de GHC descargados por Stack",
              detalle: "Archivos comprimidos de GHC y otras herramientas que Stack ya instaló.",
              consecuencia: "Nada: las herramientas ya están instaladas.")
            .en(.desarrollo).proceso("Stack", patron: "/.stack/"),
        Regla("stack-indices-antiguos", "~/.stack/indices",
              nombre: "Índice antiguo de Stack",
              detalle: "Índice de paquetes de Haskell que usaban versiones antiguas de Stack (anteriores a la 2.0).",
              consecuencia: "Nada si usas Stack 2 o más nuevo.")
            .en(.desarrollo).proceso("Stack", patron: "/.stack/"),
        Regla("stack-setup-exe", "~/.stack/setup-exe-cache",
              nombre: "Programas de configuración de Stack",
              detalle: "Pequeños programas que Stack compila para preparar paquetes.",
              consecuencia: "Stack los vuelve a crear.")
            .en(.desarrollo).proceso("Stack", patron: "/.stack/"),
        Regla("cabal-registros", "~/.cabal/logs",
              nombre: "Registros de Cabal",
              detalle: "Registros de compilación de paquetes de Haskell.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).proceso("Cabal", patron: "cabal"),
        Regla("cabal-xdg-paquetes", "~/.cache/cabal/packages",
              nombre: "Paquetes descargados de Cabal",
              detalle: "Paquetes de Haskell que descargó Cabal (instalaciones nuevas sin ~/.cabal).",
              consecuencia: "Antes de volver a compilar proyectos de Haskell tendrás que ejecutar «cabal update» (vuelve a descargar la lista de paquetes); después, Cabal descarga de nuevo los paquetes que necesite.")
            .en(.desarrollo).sinPreseleccion().proceso("Cabal", patron: "cabal"),
        Regla("cabal-xdg-registros", "~/.cache/cabal/logs",
              nombre: "Registros de Cabal",
              detalle: "Registros de compilación de paquetes de Haskell.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).proceso("Cabal", patron: "cabal"),
        Regla("ghcide-cache", "~/.cache/ghcide",
              nombre: "Índices de Haskell Language Server",
              detalle: "Índices que el editor genera para entender tu código de Haskell.",
              consecuencia: "El editor los regenera al abrir un proyecto (los primeros minutos irá más lento).")
            .en(.desarrollo).proceso("Haskell Language Server", patron: "haskell-language-server"),
        Regla("hie-bios-cache", "~/.cache/hie-bios",
              nombre: "Caché de hie-bios (Haskell)",
              detalle: "Archivos que el editor de Haskell guarda para saber cómo compilar cada proyecto.",
              consecuencia: "Se regeneran al abrir el proyecto.")
            .en(.desarrollo).proceso("Haskell Language Server", patron: "haskell-language-server"),
        Regla("rebar3-hex", "~/.cache/rebar3/hex",
              nombre: "Paquetes descargados por rebar3",
              detalle: "Dependencias de Erlang y Elixir que rebar3 descargó de Hex.",
              consecuencia: "rebar3 las vuelve a descargar si hacen falta.")
            .en(.desarrollo).proceso("rebar3", patron: "rebar3"),
        Regla("kerl-compilaciones", "~/.kerl/builds",
              nombre: "Compilaciones de Erlang (kerl)",
              detalle: "Código fuente compilado de cada versión de Erlang/OTP que instalaste con kerl.",
              consecuencia: "Nada: las instalaciones siguen funcionando. Es lo mismo que «kerl cleanup all».")
            .en(.desarrollo).hijos().proceso("kerl", patron: "kerl"),
        Regla("kerl-descargas", "~/.kerl/archives",
              nombre: "Descargas de Erlang (kerl)",
              detalle: "Código fuente de Erlang/OTP que kerl descargó.",
              consecuencia: "Nada: si compilas otra versión, kerl la descarga.")
            .en(.desarrollo).hijos().proceso("kerl", patron: "kerl"),
        Regla("asdf-erlang-compilaciones", "~/.asdf/plugins/erlang/kerl-home/builds",
              nombre: "Compilaciones de Erlang (asdf)",
              detalle: "Código fuente compilado que el plugin de Erlang de asdf dejó tras instalar.",
              consecuencia: "Nada: las versiones de Erlang ya instaladas siguen funcionando.")
            .en(.desarrollo).hijos().proceso("asdf", patron: "kerl"),
        Regla("asdf-erlang-descargas", "~/.asdf/plugins/erlang/kerl-home/archives",
              nombre: "Descargas de Erlang (asdf)",
              detalle: "Código fuente de Erlang/OTP que el plugin de asdf descargó.",
              consecuencia: "Nada: si instalas otra versión, se descarga.")
            .en(.desarrollo).hijos().proceso("asdf", patron: "kerl"),
        Regla("opam-descargas", "~/.opam/download-cache",
              nombre: "Descargas de opam (OCaml)",
              detalle: "Código fuente de paquetes de OCaml que opam descargó.",
              consecuencia: "opam los vuelve a descargar si los necesita. Es lo mismo que «opam clean --download-cache».")
            .en(.desarrollo).proceso("opam", patron: "/.opam/"),
        Regla("opam-registros", "~/.opam/log",
              nombre: "Registros de opam",
              detalle: "Registros de instalaciones de paquetes de OCaml.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).proceso("opam", patron: "/.opam/"),
        Regla("opam-compilaciones", "~/.opam/*/.opam-switch/build",
              nombre: "Compilaciones a medias de opam",
              detalle: "Carpetas de compilación de paquetes de OCaml que quedaron tras instalar o fallar.",
              consecuencia: "Nada: los paquetes ya están instalados. Es parte de lo que hace «opam clean --switch-cleanup».")
            .en(.desarrollo).proceso("opam", patron: "/.opam/"),
        Regla("opam-copias", "~/.opam/*/.opam-switch/backup",
              nombre: "Copias de seguridad de opam",
              detalle: "Copias del estado de tus entornos de OCaml antes de cada cambio.",
              consecuencia: "Ya no podrás deshacer cambios antiguos de esos entornos con esas copias.")
            .en(.desarrollo).revisar().proceso("opam", patron: "/.opam/"),
        Regla("dune-cache", "~/.cache/dune",
              nombre: "Caché compartida de dune (OCaml)",
              detalle: "Resultados de compilación que dune reutiliza entre proyectos.",
              consecuencia: "La próxima compilación de cada proyecto será más lenta mientras se regenera.")
            .en(.desarrollo).proceso("dune", patron: "dune"),
        Regla("zig-cache-global", "~/.cache/zig",
              nombre: "Caché de Zig",
              detalle: "Compilaciones y paquetes que Zig guarda para reutilizarlos.",
              consecuencia: "Zig vuelve a compilar lo que necesite y a descargar los paquetes de tus proyectos (necesita internet).")
            .en(.desarrollo).sinPreseleccion().proceso("Zig", patron: "bin/zig"),
        Regla("nim-cache", "~/.cache/nim",
              nombre: "Caché de Nim",
              detalle: "Código C intermedio que el compilador de Nim genera para cada programa.",
              consecuencia: "Nim lo vuelve a generar al compilar.")
            .en(.desarrollo).proceso("Nim", patron: "bin/nim"),
        Regla("crystal-cache", "~/.cache/crystal",
              nombre: "Caché de Crystal",
              detalle: "Compilaciones intermedias del compilador de Crystal.",
              consecuencia: "Crystal las vuelve a generar al compilar.")
            .en(.desarrollo).proceso("Crystal", patron: "crystal"),
        Regla("dub-cache", "~/.dub/cache",
              nombre: "Compilaciones de DUB (lenguaje D)",
              detalle: "Resultados de compilar dependencias de D.",
              consecuencia: "DUB las vuelve a compilar.")
            .en(.desarrollo).proceso("DUB", patron: "dub"),
        Regla("r-pak-cache", "~/Library/Caches/org.R-project.R/R/pkgcache",
              nombre: "Caché de paquetes de R (pak)",
              detalle: "Paquetes de R y listas de paquetes que pak descargó.",
              consecuencia: "pak los vuelve a descargar cuando instales paquetes (necesita internet).")
            .en(.desarrollo).app("R", "org.R-project.R", "com.rstudio.desktop"),
        Regla("cargo-install-temporales", "$TEMPORAL/cargo-install*",
              nombre: "Restos de «cargo install»",
              detalle: "Compilaciones de herramientas de Rust que fallaron y dejaron sus archivos.",
              consecuencia: "Nada: son restos de compilaciones que fallaron.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().proceso("Cargo", patron: "cargo"),
        Regla("go-build-temporales", "$TEMPORAL/go-build*",
              nombre: "Restos de compilaciones de Go",
              detalle: "Carpetas de trabajo de Go que no se borraron (compilaciones interrumpidas).",
              consecuencia: "Nada: Go crea carpetas nuevas cada vez que compila.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().proceso("Go", patron: "go-build"),
        Regla("go-sdks-viejos", "~/sdk/go1.*",
              nombre: "Versiones antiguas de Go",
              detalle: "Versiones de Go descargadas con «go install golang.org/dl/goX.Y» (se conserva la más nueva).",
              consecuencia: "Si un proyecto necesita una de esas versiones, ejecuta otra vez «goX.Y download».")
            .en(.desarrollo).revisar().conservando(.versionMasAlta).proceso("Go", patron: "/sdk/go1"),
        Regla("go-dep-cache", "~/go/pkg/dep",
              nombre: "Caché de dep (Go antiguo)",
              detalle: "Dependencias descargadas por dep, el gestor de paquetes de Go anterior a los módulos.",
              consecuencia: "Nada si ya usas módulos de Go.")
            .en(.desarrollo),
        Regla("go-pkg-antiguo", "~/go/pkg/darwin_*",
              nombre: "Paquetes compilados de Go (modo GOPATH)",
              detalle: "Librerías compiladas por versiones antiguas de Go cuando no se usaban módulos.",
              consecuencia: "Nada con Go moderno; si compilas en modo GOPATH, se regeneran.")
            .en(.desarrollo),
        Regla("rubygems-specs", "~/.gem/specs",
              nombre: "Índice de RubyGems",
              detalle: "Listas de gemas disponibles que RubyGems descargó.",
              consecuencia: "Se vuelven a descargar la próxima vez que instales una gema.")
            .en(.desarrollo),
        Regla("rubygems-cache-xdg", "~/.cache/gem",
              nombre: "Caché de RubyGems",
              detalle: "Índices y paquetes .gem que RubyGems descargó.",
              consecuencia: "Se vuelven a descargar si hacen falta.")
            .en(.desarrollo),
        Regla("rubygems-usuario-xdg", "~/.local/share/gem/ruby/*/cache",
              nombre: "Paquetes descargados de RubyGems",
              detalle: "Los archivos .gem que se descargaron para instalar gemas (las gemas instaladas no se tocan).",
              consecuencia: "Nada: las gemas siguen instaladas; si hace falta, se vuelven a descargar.")
            .en(.desarrollo),
        Regla("gem-cache-rbenv", "~/.rbenv/versions/*/lib/ruby/gems/*/cache",
              nombre: "Paquetes .gem descargados (rbenv)",
              detalle: "Copias comprimidas de cada gema instalada en tus versiones de Ruby de rbenv.",
              consecuencia: "Nada: las gemas siguen instaladas. Solo «gem pristine» tendría que volver a descargarlas.")
            .en(.desarrollo).proceso("Ruby", patron: "ruby"),
        Regla("gem-cache-rubies", "~/.rubies/*/lib/ruby/gems/*/cache",
              nombre: "Paquetes .gem descargados (chruby)",
              detalle: "Copias comprimidas de cada gema instalada en tus versiones de Ruby de ruby-install/chruby.",
              consecuencia: "Nada: las gemas siguen instaladas.")
            .en(.desarrollo).proceso("Ruby", patron: "ruby"),
        Regla("gem-cache-asdf", "~/.asdf/installs/ruby/*/lib/ruby/gems/*/cache",
              nombre: "Paquetes .gem descargados (asdf)",
              detalle: "Copias comprimidas de cada gema instalada en tus versiones de Ruby de asdf.",
              consecuencia: "Nada: las gemas siguen instaladas.")
            .en(.desarrollo).proceso("Ruby", patron: "ruby"),
        Regla("gem-cache-mise", "~/.local/share/mise/installs/ruby/*.*.*/lib/ruby/gems/*/cache",
              nombre: "Paquetes .gem descargados (mise)",
              detalle: "Copias comprimidas de cada gema instalada en tus versiones de Ruby de mise.",
              consecuencia: "Nada: las gemas siguen instaladas.")
            .en(.desarrollo).proceso("Ruby", patron: "ruby"),
        Regla("gem-cache-rvm", "~/.rvm/gems/*/cache",
              nombre: "Paquetes .gem descargados (RVM)",
              detalle: "Copias comprimidas de cada gema instalada en tus gemsets de RVM.",
              consecuencia: "Nada: las gemas siguen instaladas.")
            .en(.desarrollo).excepto("default").proceso("Ruby", patron: "ruby"),
        Regla("gem-cache-rvm-global", "~/.rvm/gems/cache",
              nombre: "Paquetes .gem descargados (caché global de RVM)",
              detalle: "Copias comprimidas de las gemas que RVM guarda en su caché compartida entre gemsets.",
              consecuencia: "Nada: las gemas siguen instaladas.")
            .en(.desarrollo).hijos().proceso("Ruby", patron: "ruby"),
        Regla("gem-cache-homebrew", "/opt/homebrew/lib/ruby/gems/*/cache",
              nombre: "Paquetes .gem descargados (Ruby de Homebrew)",
              detalle: "Copias comprimidas de las gemas instaladas con el Ruby de Homebrew.",
              consecuencia: "Nada: las gemas siguen instaladas.")
            .admin().sinPreseleccion().proceso("Ruby", patron: "ruby"),
        Regla("rbenv-fuentes", "~/.rbenv/sources",
              nombre: "Código fuente de Ruby (rbenv)",
              detalle: "Código de Ruby que se guardó al instalar con «rbenv install --keep».",
              consecuencia: "Nada: las versiones de Ruby ya están instaladas.")
            .en(.desarrollo).proceso("rbenv", patron: "ruby-build"),
        Regla("rbenv-descargas", "~/.rbenv/cache",
              nombre: "Descargas de rbenv",
              detalle: "Código fuente de Ruby que ruby-build guardó para no volver a descargarlo.",
              consecuencia: "Nada: las versiones ya están instaladas.")
            .en(.desarrollo).hijos().proceso("rbenv", patron: "ruby-build"),
        Regla("rvm-descargas", "~/.rvm/archives",
              nombre: "Descargas de RVM",
              detalle: "Código fuente de Ruby que RVM descargó.",
              consecuencia: "Nada: las versiones ya están instaladas. Es lo mismo que «rvm cleanup archives».")
            .en(.desarrollo).hijos().proceso("RVM", patron: "/.rvm/"),
        Regla("rvm-fuentes", "~/.rvm/src",
              nombre: "Código fuente compilado por RVM",
              detalle: "Copias del código de Ruby que RVM usó para compilar.",
              consecuencia: "Nada: las versiones de Ruby ya están instaladas. Es lo mismo que «rvm cleanup sources».")
            .en(.desarrollo).hijos().proceso("RVM", patron: "/.rvm/"),
        Regla("rvm-registros", "~/.rvm/log",
              nombre: "Registros de RVM",
              detalle: "Registros de instalaciones de Ruby.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).hijos().proceso("RVM", patron: "/.rvm/"),
        Regla("rvm-temporales", "~/.rvm/tmp",
              nombre: "Temporales de RVM",
              detalle: "Archivos temporales de RVM.",
              consecuencia: "Nada: RVM crea otros cuando los necesita.")
            .en(.desarrollo).hijos().edad(dias: 1).sinArchivosAbiertos().proceso("RVM", patron: "/.rvm/"),
        Regla("rvm-repos", "~/.rvm/repos",
              nombre: "Repositorios descargados por RVM",
              detalle: "Copias de repositorios git de Ruby que RVM descargó.",
              consecuencia: "Nada: RVM los vuelve a descargar si los necesita. Es lo mismo que «rvm cleanup repos».")
            .en(.desarrollo).hijos().proceso("RVM", patron: "/.rvm/"),
        Regla("nodenv-fuentes", "~/.nodenv/sources",
              nombre: "Código fuente de Node (nodenv)",
              detalle: "Código de Node que se guardó al instalar con «nodenv install --keep».",
              consecuencia: "Nada: las versiones ya están instaladas.")
            .en(.desarrollo).proceso("nodenv", patron: "node-build"),
        Regla("nodenv-descargas", "~/.nodenv/cache",
              nombre: "Descargas de nodenv",
              detalle: "Instaladores de Node que node-build guardó.",
              consecuencia: "Nada: las versiones ya están instaladas.")
            .en(.desarrollo).hijos().proceso("nodenv", patron: "node-build"),
        Regla("pyenv-fuentes", "~/.pyenv/sources",
              nombre: "Código fuente de Python (pyenv)",
              detalle: "Código de Python que se guardó al instalar con «pyenv install --keep».",
              consecuencia: "Nada: las versiones de Python ya están instaladas.")
            .en(.desarrollo).proceso("pyenv", patron: "python-build"),
        Regla("asdf-descargas", "~/.asdf/downloads",
              nombre: "Descargas de asdf",
              detalle: "Instaladores y código que los plugins de asdf descargaron.",
              consecuencia: "Nada: las versiones ya están instaladas.")
            .en(.desarrollo).proceso("asdf", patron: "/.asdf/"),
        Regla("mise-descargas", "~/.local/share/mise/downloads",
              nombre: "Descargas de mise",
              detalle: "Instaladores que mise descargó para instalar herramientas.",
              consecuencia: "Nada: las herramientas ya están instaladas.")
            .en(.desarrollo).proceso("mise", patron: "mise"),
        Regla("volta-registros", "~/.volta/log",
              nombre: "Registros de errores de Volta",
              detalle: "Detalles de errores de Volta.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).proceso("Volta", patron: "/.volta/"),
        Regla("volta-temporales", "~/.volta/tmp",
              nombre: "Temporales de Volta",
              detalle: "Descargas y descompresiones a medias de Volta.",
              consecuencia: "Nada: son descargas a medias que Volta ya no usa.")
            .en(.desarrollo).edad(dias: 1).sinArchivosAbiertos().proceso("Volta", patron: "/.volta/"),
        Regla("npm-prebuilds", "~/.npm/_prebuilds",
              nombre: "Binarios precompilados de módulos de Node",
              detalle: "Módulos nativos ya compilados que prebuild-install descargó.",
              consecuencia: "Se vuelven a descargar al instalar paquetes que los necesiten.")
            .en(.desarrollo),
        Regla("npm-libvips", "~/.npm/_libvips",
              nombre: "Descargas de libvips (sharp)",
              detalle: "Librerías de imágenes que descargaban las versiones antiguas de sharp.",
              consecuencia: "Se vuelven a descargar si instalas un proyecto con una versión antigua de sharp.")
            .en(.desarrollo),
        Regla("electron-cache-antigua", "~/.electron",
              nombre: "Descargas antiguas de Electron",
              detalle: "Versiones de Electron que guardaban herramientas antiguas (electron-download).",
              consecuencia: "Nada con herramientas actuales, que usan otra carpeta.")
            .en(.desarrollo),
        Regla("metro-cache", "$TEMPORAL/metro-cache",
              nombre: "Caché de Metro (React Native)",
              detalle: "Código ya transformado que el empaquetador de React Native guarda para arrancar más rápido.",
              consecuencia: "El próximo arranque de Metro tardará más mientras se regenera.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().proceso("Metro", patron: "metro"),
        Regla("jest-cache", "$TEMPORAL/jest_*",
              nombre: "Caché de Jest",
              detalle: "Archivos transformados que Jest guarda para ejecutar las pruebas más rápido.",
              consecuencia: "La próxima ejecución de pruebas tardará algo más.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().proceso("Jest", patron: "jest"),
        Regla("pipx-cache-antigua", "~/.local/pipx/.cache",
              nombre: "Entornos temporales de «pipx run»",
              detalle: "Entornos de Python que pipx creó para ejecutar herramientas una sola vez.",
              consecuencia: "Si vuelves a usar «pipx run», se crean de nuevo.")
            .en(.desarrollo).proceso("pipx", patron: "pipx"),
        Regla("pipx-registros-antiguos", "~/.local/pipx/logs",
              nombre: "Registros de pipx",
              detalle: "Registros de cada comando de pipx.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).proceso("pipx", patron: "pipx"),
        Regla("pipx-papelera", "~/.local/pipx/.trash",
              nombre: "Papelera de pipx",
              detalle: "Entornos de herramientas de Python que pipx ya desinstaló.",
              consecuencia: "Nada: son herramientas que ya desinstalaste.")
            .en(.desarrollo).proceso("pipx", patron: "pipx"),
        Regla("pipx-papelera-appsupport", "~/Library/Application Support/pipx/trash",
              nombre: "Papelera de pipx",
              detalle: "Entornos de herramientas de Python que pipx ya desinstaló.",
              consecuencia: "Nada: son herramientas que ya desinstalaste.")
            .en(.desarrollo).proceso("pipx", patron: "pipx"),
        Regla("pipx-cache-appsupport", "~/Library/Application Support/pipx/.cache",
              nombre: "Entornos temporales de «pipx run»",
              detalle: "Entornos de Python que versiones anteriores de pipx crearon para ejecutar herramientas una vez.",
              consecuencia: "Nada: las versiones actuales usan otra carpeta.")
            .en(.desarrollo).proceso("pipx", patron: "pipx"),
        Regla("virtualenv-datos-antiguos", "~/Library/Application Support/virtualenv",
              nombre: "Datos antiguos de virtualenv",
              detalle: "Paquetes base e información de Python que virtualenv guardaba para crear entornos.",
              consecuencia: "Nada en la mayoría de los casos: virtualenv la vuelve a crear. Si creaste entornos con la opción «--symlink-app-data», tendrás que recrearlos.")
            .en(.desarrollo).sinPreseleccion().proceso("virtualenv", patron: "virtualenv"),
        Regla("pyright-python", "~/.cache/pyright-python",
              nombre: "Copias de Pyright para Python",
              detalle: "Versiones de Pyright (y Node) que el paquete «pyright» de pip descargó.",
              consecuencia: "Se vuelve a descargar la próxima vez que ejecutes pyright.")
            .en(.desarrollo).proceso("Pyright", patron: "pyright"),
        Regla("pip-temporales", "$TEMPORAL/pip-*",
              nombre: "Restos de instalaciones de pip",
              detalle: "Carpetas temporales de pip que quedaron tras instalaciones interrumpidas.",
              consecuencia: "Nada: son restos de instalaciones que no terminaron.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().proceso("pip", patron: "pip"),
        Regla("conda-indice-raiz", "~/*conda3/pkgs/cache",
              nombre: "Índice de paquetes de conda",
              detalle: "Listas de paquetes disponibles que conda descargó.",
              consecuencia: "Se vuelven a descargar la próxima vez que instales algo. Es lo mismo que «conda clean --index-cache».")
            .en(.desarrollo).proceso("conda", patron: "/bin/conda"),
        Regla("conda-indice-forge", "~/miniforge3/pkgs/cache",
              nombre: "Índice de paquetes de conda (Miniforge)",
              detalle: "Listas de paquetes disponibles que conda o mamba descargaron.",
              consecuencia: "Se vuelven a descargar la próxima vez que instales algo.")
            .en(.desarrollo).proceso("conda", patron: "/bin/conda"),
        Regla("conda-indice-mambaforge", "~/mambaforge/pkgs/cache",
              nombre: "Índice de paquetes de conda (Mambaforge)",
              detalle: "Listas de paquetes disponibles que conda o mamba descargaron.",
              consecuencia: "Se vuelven a descargar la próxima vez que instales algo.")
            .en(.desarrollo).proceso("conda", patron: "/bin/conda"),
        Regla("conda-indice-opt", "~/opt/*conda3/pkgs/cache",
              nombre: "Índice de paquetes de Anaconda",
              detalle: "Listas de paquetes disponibles que conda descargó.",
              consecuencia: "Se vuelven a descargar la próxima vez que instales algo.")
            .en(.desarrollo).proceso("conda", patron: "/bin/conda"),
        Regla("conda-indice-usuario", "~/.conda/pkgs/cache",
              nombre: "Índice de paquetes de conda (usuario)",
              detalle: "Listas de paquetes disponibles que conda descargó.",
              consecuencia: "Se vuelven a descargar la próxima vez que instales algo.")
            .en(.desarrollo).proceso("conda", patron: "/bin/conda"),
        Regla("phpstan-cache", "$TEMPORAL/phpstan",
              nombre: "Caché de PHPStan",
              detalle: "Resultados de análisis de código PHP que PHPStan guarda.",
              consecuencia: "El próximo análisis tardará más.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().proceso("PHPStan", patron: "phpstan"),
        Regla("phpbrew-descargas", "~/.phpbrew/distfiles",
              nombre: "Descargas de phpbrew",
              detalle: "Código fuente de PHP que phpbrew descargó.",
              consecuencia: "Nada: las versiones de PHP ya están instaladas.")
            .en(.desarrollo).proceso("phpbrew", patron: "phpbrew"),
        Regla("phpbrew-compilaciones", "~/.phpbrew/build",
              nombre: "Compilaciones de phpbrew",
              detalle: "Código de PHP ya compilado de cada versión que instalaste.",
              consecuencia: "Instalar extensiones incluidas en PHP con «phpbrew ext install» puede necesitar recompilar.")
            .en(.desarrollo).revisar().proceso("phpbrew", patron: "phpbrew"),
        Regla("phpbrew-temporales", "~/.phpbrew/tmp",
              nombre: "Temporales de phpbrew",
              detalle: "Archivos temporales de phpbrew.",
              consecuencia: "Nada: phpbrew crea otros cuando los necesita.")
            .en(.desarrollo).edad(dias: 1).sinArchivosAbiertos().proceso("phpbrew", patron: "phpbrew"),
        Regla("phpbrew-cache", "~/.phpbrew/cache",
              nombre: "Caché de phpbrew",
              detalle: "Listas de versiones y extensiones que phpbrew descargó.",
              consecuencia: "Se vuelven a descargar.")
            .en(.desarrollo).proceso("phpbrew", patron: "phpbrew"),
        Regla("cpanm-trabajo", "~/.cpanm/work",
              nombre: "Compilaciones de módulos de Perl (cpanm)",
              detalle: "Carpetas donde cpanm descargó y compiló módulos de Perl.",
              consecuencia: "Nada: los módulos ya están instalados.")
            .en(.desarrollo).hijos().edad(dias: 2).sinArchivosAbiertos().proceso("cpanm", patron: "cpanm"),
        Regla("perlbrew-compilaciones", "~/perl5/perlbrew/build",
              nombre: "Compilaciones de Perl (perlbrew)",
              detalle: "Código de Perl ya compilado.",
              consecuencia: "Nada: las versiones de Perl ya están instaladas. Es lo mismo que «perlbrew clean».")
            .en(.desarrollo).hijos().proceso("perlbrew", patron: "perlbrew"),
        Regla("perlbrew-descargas", "~/perl5/perlbrew/dists",
              nombre: "Descargas de perlbrew",
              detalle: "Código fuente de Perl que perlbrew descargó.",
              consecuencia: "Nada: las versiones de Perl ya están instaladas. Es lo mismo que «perlbrew clean».")
            .en(.desarrollo).hijos().proceso("perlbrew", patron: "perlbrew"),
        Regla("conan2-paquetes", "~/.conan2/p",
              nombre: "Paquetes de C/C++ de Conan",
              detalle: "Librerías de C y C++ que Conan descargó o compiló.",
              consecuencia: "La próxima vez que ejecutes «conan install» se vuelven a descargar o compilar (puede tardar mucho). Los paquetes que creaste tú con «conan create» y no subiste a un servidor tendrás que volver a crearlos.")
            .en(.desarrollo).revisar().proceso("Conan", patron: "conan"),
        Regla("conan1-compilaciones", "~/.conan/data/*/*/*/*/build",
              nombre: "Compilaciones de Conan 1",
              detalle: "Carpetas de compilación de librerías de C/C++ que ya están empaquetadas.",
              consecuencia: "Nada: los paquetes ya compilados se conservan.")
            .en(.desarrollo).proceso("Conan", patron: "conan"),
        Regla("vcpkg-binarios", "~/.cache/vcpkg/archives",
              nombre: "Caché binaria de vcpkg",
              detalle: "Librerías de C/C++ ya compiladas que vcpkg guarda para reutilizarlas.",
              consecuencia: "vcpkg las vuelve a compilar cuando un proyecto las necesite (puede tardar).")
            .en(.desarrollo).sinPreseleccion().proceso("vcpkg", patron: "vcpkg"),
        Regla("ccache-antiguo", "~/.ccache",
              nombre: "Caché de ccache",
              detalle: "Resultados de compilación de C/C++ que ccache guarda (ubicación antigua).",
              consecuencia: "Las próximas compilaciones serán más lentas mientras se vuelve a llenar. Tu configuración (ccache.conf) no se toca.")
            .en(.desarrollo).hijos().excepto("ccache.conf").proceso("ccache", patron: "ccache"),
        Regla("pants-cache", "~/.cache/pants",
              nombre: "Caché de Pants",
              detalle: "Herramientas, dependencias y resultados de compilación que guarda el sistema de compilación Pants.",
              consecuencia: "Pants vuelve a descargar y calcular todo en la próxima ejecución (tarda).")
            .en(.desarrollo).sinPreseleccion().proceso("Pants", patron: "pantsd"),
        Regla("tuist-cache", "~/.cache/tuist",
              nombre: "Caché de Tuist",
              detalle: "Binarios, manifiestos y proyectos que Tuist genera para tus apps de iOS.",
              consecuencia: "Tuist vuelve a descargar o compilar lo que necesite. Si tienes un proyecto generado con binarios en caché, vuelve a ejecutar «tuist generate» antes de compilarlo.")
            .en(.desarrollo).sinPreseleccion().app("Xcode", "com.apple.dt.Xcode"),
        Regla("kotlin-daemon-registros", "$TEMPORAL/kotlin-daemon.*.log",
              nombre: "Registros del daemon de Kotlin",
              detalle: "Registros del proceso que compila Kotlin en segundo plano.",
              consecuencia: "Nada: solo son registros.")
            .en(.registros).edad(dias: 1).sinArchivosAbiertos(),
        Regla("nix-cache", "~/.cache/nix",
              nombre: "Caché de Nix",
              detalle: "Evaluaciones, índices de cachés binarias y descargas de repositorios que Nix guarda.",
              consecuencia: "Nix vuelve a descargar y evaluar lo que necesite (la primera vez irá más lento).")
            .en(.desarrollo).proceso("Nix", patron: "/bin/nix"),
    ]
}
