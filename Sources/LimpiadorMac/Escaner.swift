import Foundation

/// Hace el análisis profundo del disco. Cada categoría es un paso independiente.
struct Escaner {
    typealias Progreso = @Sendable (_ fraccion: Double, _ mensaje: String) -> Void
    typealias Entrega = @Sendable (_ elementos: [Elemento]) -> Void

    private let fm = FileManager.default
    private let minimo: Int64 = 1_000_000 // ignora lo que ocupa menos de 1 MB
    private let rutasDeDesarrollo: [(String, String, String, Riesgo, Bool)] = [
        // (ruta relativa al home, nombre, explicación, riesgo, preseleccionado)
        (".npm/_cacache", "Caché de npm", "Paquetes de npm descargados. Se vuelven a descargar con npm install.", .seguro, true),
        (".npm/_npx", "Paquetes temporales de npx", "Herramientas que npx descargó una vez para ejecutarlas.", .seguro, true),
        (".gradle/caches", "Caché de Gradle", "Dependencias y compilaciones de Gradle (Android). Se regenera al compilar. Cierra Android Studio antes de limpiar.", .seguro, true),
        (".gradle/daemon", "Registros del daemon de Gradle", "Logs de procesos de Gradle ya terminados.", .seguro, true),
        (".gradle/.tmp", "Temporales de Gradle", "Archivos temporales de Gradle.", .seguro, true),
        ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData", "Compilaciones intermedias de Xcode. Se regeneran al compilar.", .seguro, true),
        ("Library/Developer/Xcode/iOS DeviceSupport", "Soporte de dispositivos iOS", "Símbolos de iPhones que conectaste. Xcode los vuelve a copiar si hace falta.", .seguro, true),
        ("Library/Developer/Xcode/watchOS DeviceSupport", "Soporte de dispositivos watchOS", "Símbolos de Apple Watch conectados alguna vez.", .seguro, true),
        ("Library/Developer/Xcode/Archives", "Archivos de Xcode (Archives)", "Versiones de apps que archivaste para publicar.", .revisar, false),
        ("Library/Developer/CoreSimulator/Caches", "Caché de simuladores", "Caché de los simuladores de iOS.", .seguro, true),
        ("Library/Caches/CocoaPods", "Caché de CocoaPods", "Pods descargados. Se vuelven a descargar con pod install.", .seguro, true),
        ("Library/Caches/pip", "Caché de pip (Python)", "Paquetes de Python descargados.", .seguro, true),
        ("Library/Caches/Homebrew", "Caché de Homebrew", "Instaladores descargados por brew.", .seguro, true),
        ("Library/Caches/ms-playwright", "Navegadores de Playwright", "Navegadores descargados por Playwright. Se reinstalan con npx playwright install.", .seguro, true),
        ("Library/Caches/electron", "Caché de Electron", "Versiones de Electron descargadas al instalar paquetes.", .seguro, true),
        ("Library/Caches/org.swift.swiftpm", "Caché de Swift Package Manager", "Paquetes de Swift descargados.", .seguro, true),
        ("Library/Caches/Yarn", "Caché de Yarn", "Paquetes de Yarn descargados.", .seguro, true),
        ("Library/Caches/go-build", "Caché de Go", "Compilaciones de Go.", .seguro, true),
        ("Library/Caches/node-gyp", "Caché de node-gyp", "Cabeceras de Node para compilar módulos nativos.", .seguro, true),
        ("Library/pnpm/store", "Almacén de pnpm", "Paquetes de pnpm descargados.", .seguro, true),
        (".cache/uv", "Caché de uv (Python)", "Paquetes de Python descargados por uv.", .seguro, true),
        (".cache/pip", "Caché de pip", "Paquetes de Python descargados.", .seguro, true),
        (".cache/puppeteer", "Navegadores de Puppeteer", "Chrome descargado por Puppeteer. Se vuelve a descargar al instalarlo.", .seguro, true),
        (".cache/firebase", "Caché de Firebase", "Emuladores y herramientas descargadas por Firebase CLI.", .seguro, false),
        (".cache/huggingface", "Modelos de Hugging Face", "Modelos de IA descargados. Si los borras, se vuelven a descargar (pueden pesar mucho).", .revisar, false),
        (".cache/codex-runtimes", "Runtimes de Codex", "Entornos descargados por Codex.", .revisar, false),
        (".bun/install/cache", "Caché de Bun", "Paquetes descargados por Bun.", .seguro, true),
        (".cargo/registry", "Registro de Cargo (Rust)", "Crates de Rust descargados.", .seguro, false),
        (".m2/repository", "Repositorio de Maven", "Dependencias Java descargadas.", .seguro, false),
        (".android/cache", "Caché de Android", "Caché de las herramientas de Android.", .seguro, true),
        (".expo", "Caché de Expo", "Datos y caché de Expo (React Native).", .revisar, false),
    ]

    func ejecutar(progreso: Progreso, entrega: Entrega) {
        let apps = AppsInstaladas.cargar()
        let pasos: [(String, () -> [Elemento])] = [
            ("Revisando emuladores y simuladores…", { emuladores() }),
            ("Revisando cachés de desarrollo…", { desarrollo() }),
            ("Revisando cachés de aplicaciones…", { cachesApps() }),
            ("Buscando restos de apps desinstaladas…", { restos(apps) }),
            ("Buscando node_modules y compilaciones en tus proyectos…", { proyectos() }),
            ("Revisando carpetas ocultas…", { herramientas(apps) }),
            ("Buscando instaladores olvidados…", { instaladores() }),
            ("Buscando archivos grandes, antiguos y duplicados…", { grandesYDuplicados() }),
            ("Revisando registros y reportes de fallos…", { registros(apps) }),
            ("Midiendo la Papelera…", { papelera() }),
        ]
        for (i, (mensaje, paso)) in pasos.enumerated() {
            progreso(Double(i) / Double(pasos.count), mensaje)
            let encontrados = paso().filter { $0.tamano >= minimo }
            entrega(encontrados.sorted { $0.tamano > $1.tamano })
        }
        progreso(1, "Análisis terminado")
    }

    // MARK: - Emuladores y simuladores

    func emuladores() -> [Elemento] {
        var r: [Elemento] = []
        let avdDir = Rutas.enHome(".android/avd")
        var imagenesUsadas = Set<String>()

        for avd in Rutas.hijos(avdDir) where avd.pathExtension == "avd" {
            let base = avd.deletingPathExtension().lastPathComponent
            let config = (try? String(contentsOf: avd.appendingPathComponent("config.ini"), encoding: .utf8)) ?? ""
            var nombre = base.replacingOccurrences(of: "_", with: " ")
            for linea in config.split(separator: "\n") {
                let kv = linea.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2 else { continue }
                if kv[0] == "avd.ini.displayname" { nombre = kv[1] }
                if kv[0].hasPrefix("image.sysdir") {
                    imagenesUsadas.insert(kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                }
            }
            let ini = avdDir.appendingPathComponent(base + ".ini")
            let ultimo = Fechas.masReciente(avd)
            r.append(Elemento(
                nombre: "Emulador Android: \(nombre)",
                detalle: "Incluye el sistema, las apps instaladas y los datos del emulador. Se puede volver a crear en Android Studio › Device Manager.",
                rutas: Rutas.existe(ini) ? [avd, ini] : [avd],
                ultimoUso: ultimo, categoria: .emuladores, riesgo: .revisar,
                seleccionado: false))

            let snaps = avd.appendingPathComponent("snapshots")
            if Rutas.existe(snaps) {
                r.append(Elemento(
                    nombre: "Snapshots de \(nombre)",
                    detalle: "Estados guardados del emulador. Si los borras, el emulador tardará un poco más en arrancar la próxima vez.",
                    rutas: [snaps], ultimoUso: Fechas.masReciente(snaps),
                    categoria: .emuladores, riesgo: .seguro, seleccionado: false))
            }
        }

        // Imágenes del sistema de Android: sdk/system-images/android-XX/<tipo>/<abi>
        let sdk = Rutas.enHome("Library/Android/sdk")
        let imagenes = sdk.appendingPathComponent("system-images")
        for version in Rutas.hijos(imagenes) where Rutas.esCarpeta(version) {
            for tipo in Rutas.hijos(version) where Rutas.esCarpeta(tipo) {
                for abi in Rutas.hijos(tipo) where Rutas.esCarpeta(abi) {
                    let rel = "system-images/\(version.lastPathComponent)/\(tipo.lastPathComponent)/\(abi.lastPathComponent)"
                    let enUso = imagenesUsadas.contains(rel)
                    r.append(Elemento(
                        nombre: "Imagen Android \(version.lastPathComponent) (\(tipo.lastPathComponent))",
                        detalle: enUso
                            ? "La usa uno de tus emuladores. Si la borras, ese emulador dejará de funcionar."
                            : "Ningún emulador la usa. Se puede volver a descargar desde el SDK Manager.",
                        rutas: [abi], ultimoUso: Fechas.masReciente(abi), categoria: .emuladores,
                        riesgo: enUso ? .cuidado : .seguro, seleccionado: !enUso))
                }
            }
        }

        // Versiones antiguas de build-tools (se conserva la más nueva).
        let bt = sdk.appendingPathComponent("build-tools")
        let versiones = Rutas.hijos(bt).filter { Rutas.esCarpeta($0) }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
        for v in versiones.dropLast() {
            r.append(Elemento(
                nombre: "Android build-tools \(v.lastPathComponent) (versión antigua)",
                detalle: "Ya tienes una versión más nueva. Gradle la vuelve a descargar si algún proyecto la pide.",
                rutas: [v], ultimoUso: Fechas.masReciente(v), categoria: .emuladores,
                riesgo: .seguro, seleccionado: true))
        }

        r.append(contentsOf: simuladoresIOS())
        return Tamanos.medir(r)
    }

    private func simuladoresIOS() -> [Elemento] {
        guard Rutas.existe(Rutas.enHome("Library/Developer/CoreSimulator/Devices")) else { return [] }
        let json = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"]).salida
        guard let datos = json.data(using: .utf8),
              let raiz = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let porRuntime = raiz["devices"] as? [String: [[String: Any]]] else { return [] }
        let iso = ISO8601DateFormatter()
        var r: [Elemento] = []
        for (runtime, dispositivos) in porRuntime {
            let version = runtime.components(separatedBy: "SimRuntime.").last?
                .replacingOccurrences(of: "-", with: " ", options: [], range: nil) ?? runtime
            for d in dispositivos {
                guard let udid = d["udid"] as? String, let nombre = d["name"] as? String,
                      let dataPath = d["dataPath"] as? String else { continue }
                let disponible = d["isAvailable"] as? Bool ?? true
                let ultimo = (d["lastUsedAt"] as? String).flatMap { iso.date(from: $0) }
                let carpeta = URL(fileURLWithPath: dataPath).deletingLastPathComponent()
                if disponible {
                    r.append(Elemento(
                        nombre: "Simulador iOS: \(nombre) (\(version))",
                        detalle: "Borra las apps y datos que instalaste en este simulador. El simulador sigue disponible en Xcode.",
                        rutas: [URL(fileURLWithPath: dataPath)], ultimoUso: ultimo,
                        categoria: .emuladores, riesgo: .revisar, seleccionado: false,
                        accion: .vaciarSimulador(udid: udid)))
                } else {
                    r.append(Elemento(
                        nombre: "Simulador sin sistema: \(nombre)",
                        detalle: "Su versión de iOS ya no está instalada, así que no se puede usar.",
                        rutas: [carpeta], ultimoUso: ultimo, categoria: .emuladores,
                        riesgo: .seguro, seleccionado: true, accion: .eliminarSimulador(udid: udid)))
                }
            }
        }
        return r
    }

    // MARK: - Cachés de desarrollo

    func desarrollo() -> [Elemento] {
        var r: [Elemento] = []
        for (rel, nombre, detalle, riesgo, sel) in rutasDeDesarrollo {
            let url = Rutas.enHome(rel)
            guard Rutas.existe(url) else { continue }
            r.append(Elemento(nombre: nombre, detalle: detalle, rutas: [url],
                              ultimoUso: Fechas.masReciente(url), categoria: .desarrollo,
                              riesgo: riesgo, seleccionado: sel))
        }
        // Distribuciones de Gradle: se conserva la más nueva.
        let dists = Rutas.hijos(Rutas.enHome(".gradle/wrapper/dists"))
            .filter { Rutas.esCarpeta($0) }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
        for (i, d) in dists.enumerated() {
            let esLaUltima = i == dists.count - 1
            let ultimo = Fechas.masReciente(d)
            let viejo = (ultimo.map { Date().timeIntervalSince($0) > 30 * 86400 } ?? true)
            r.append(Elemento(
                nombre: "Gradle \(d.lastPathComponent.replacingOccurrences(of: "gradle-", with: ""))",
                detalle: esLaUltima
                    ? "Tu versión más reciente de Gradle."
                    : "Versión anterior de Gradle. Si un proyecto la necesita, se descarga sola.",
                rutas: [d], ultimoUso: ultimo, categoria: .desarrollo, riesgo: .seguro,
                seleccionado: !esLaUltima && viejo))
        }
        return Tamanos.medir(r)
    }

    // MARK: - Cachés de aplicaciones

    func cachesApps() -> [Elemento] {
        let caches = Rutas.enHome("Library/Caches")
        let yaCubiertas = Set(rutasDeDesarrollo.map { Rutas.enHome($0.0).path })
        var r: [Elemento] = []
        for c in Rutas.hijos(caches) {
            let n = c.lastPathComponent
            if n.hasPrefix("com.apple.") || n.hasPrefix(".") || yaCubiertas.contains(c.path) { continue }
            if n == "CloudKit" || n == "FamilyCircle" || n == "GeoServices" { continue }
            r.append(Elemento(
                nombre: "Caché de \(nombreBonito(n))",
                detalle: "Archivos temporales. La app los vuelve a crear cuando los necesita (al principio puede ir un poco más lenta).",
                rutas: [c], ultimoUso: Fechas.masReciente(c), categoria: .cachesApps,
                riesgo: .seguro, seleccionado: true))
        }
        return Tamanos.medir(r)
    }

    // MARK: - Restos de apps desinstaladas

    func restos(_ apps: AppsInstaladas) -> [Elemento] {
        var r: [Elemento] = []
        let lugares: [(String, String)] = [
            ("Library/Application Support", "Datos de la app"),
            ("Library/Saved Application State", "Estado de ventanas guardado"),
            ("Library/HTTPStorages", "Cookies y datos web"),
            ("Library/WebKit", "Datos web"),
            ("Library/Logs", "Registros"),
        ]
        for (rel, tipo) in lugares {
            for c in Rutas.hijos(Rutas.enHome(rel)) {
                let n = c.lastPathComponent
                if n.hasPrefix(".") { continue }
                let clave = n.replacingOccurrences(of: ".savedState", with: "")
                if apps.estaInstalado(carpeta: clave) { continue }
                r.append(Elemento(
                    nombre: nombreBonito(clave),
                    detalle: "\(tipo) de un programa que no encontré instalado en este Mac.",
                    rutas: [c], ultimoUso: Fechas.masReciente(c), categoria: .restos,
                    riesgo: .revisar, seleccionado: false))
            }
        }

        // Preferencias sueltas (.plist) de apps que ya no están: se agrupan en un solo elemento.
        let prefs = Rutas.hijos(Rutas.enHome("Library/Preferences")).filter {
            $0.pathExtension == "plist"
                && $0.deletingPathExtension().lastPathComponent.split(separator: ".").count >= 3
                && !apps.estaInstalado(carpeta: $0.lastPathComponent)
        }
        if !prefs.isEmpty {
            r.append(Elemento(
                nombre: "Preferencias de \(prefs.count) apps desinstaladas",
                detalle: prefs.prefix(6).map { $0.deletingPathExtension().lastPathComponent }.joined(separator: ", ")
                    + (prefs.count > 6 ? "…" : ""),
                rutas: prefs, ultimoUso: prefs.compactMap(Fechas.modificacion).max(),
                categoria: .restos, riesgo: .revisar, seleccionado: false))
        }

        // Carpeta compartida (/Users/Shared): juegos y apps suelen dejar cosas aquí.
        let compartida = URL(fileURLWithPath: "/Users/Shared")
        for c in Rutas.hijos(compartida) {
            let n = c.lastPathComponent
            if n.hasPrefix(".") || n == "SC Info" { continue }
            if n.hasPrefix("Previously Relocated Items") || n == "Relocated Items" {
                r.append(Elemento(
                    nombre: n, detalle: "Archivos que macOS apartó durante una actualización del sistema. Normalmente ya no hacen falta.",
                    rutas: [c], ultimoUso: Fechas.masReciente(c), categoria: .restos,
                    riesgo: .revisar, seleccionado: false))
                continue
            }
            if apps.estaInstalado(carpeta: n) { continue }
            r.append(Elemento(
                nombre: "\(n) (carpeta compartida)",
                detalle: "Datos que dejó un programa que no encontré instalado.",
                rutas: [c], ultimoUso: Fechas.masReciente(c), categoria: .restos,
                riesgo: .revisar, seleccionado: false))
        }
        return Tamanos.medir(r)
    }

    // MARK: - Proyectos

    private static let raicesProyectos = ["Desktop", "Documents", "Developer", "Projects", "Proyectos", "Code",
                                          "dev", "src", "StudioProjects", "AndroidStudioProjects", "Downloads",
                                          "IdeaProjects", "Sites", "repos", "GitHub"]

    func proyectos() -> [Elemento] {
        var r: [Elemento] = []
        var vistos = Set<String>()
        for raiz in Self.raicesProyectos {
            let url = Rutas.enHome(raiz)
            guard Rutas.existe(url),
                  let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                        options: [.skipsPackageDescendants]) else { continue }
            for case let item as URL in e {
                if e.level > 7 { e.skipDescendants(); continue }
                let v = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                guard v?.isDirectory == true else { continue }
                let n = item.lastPathComponent
                let padre = item.deletingLastPathComponent()
                guard let (tipo, riesgo) = artefacto(nombre: n, en: padre) else {
                    // No entrar en carpetas ocultas grandes que no sean artefactos (.git, etc.)
                    if n.hasPrefix(".") { e.skipDescendants() }
                    continue
                }
                e.skipDescendants()
                guard vistos.insert(item.path).inserted else { continue }
                let ultimo = Fechas.masReciente(padre, ignorando: [n])
                let inactivo = ultimo.map { Date().timeIntervalSince($0) > 30 * 86400 } ?? true
                r.append(Elemento(
                    nombre: "\(padre.lastPathComponent) › \(n)",
                    detalle: tipo + (inactivo ? " El proyecto no se ha tocado en más de un mes." : " Proyecto con actividad reciente."),
                    rutas: [item], ultimoUso: ultimo, categoria: .proyectos,
                    riesgo: riesgo, seleccionado: inactivo && riesgo == .seguro))
            }
        }
        return Tamanos.medir(r)
    }

    /// Si una carpeta es un artefacto regenerable de un proyecto, dice qué es.
    private func artefacto(nombre n: String, en padre: URL) -> (String, Riesgo)? {
        func hay(_ archivo: String) -> Bool { Rutas.existe(padre.appendingPathComponent(archivo)) }
        if Rutas.existe(padre.appendingPathComponent(n).appendingPathComponent("pyvenv.cfg")) {
            return ("Entorno virtual de Python. Se puede recrear, pero tendrás que reinstalar los paquetes.", .revisar)
        }
        switch n {
        case "node_modules":
            return ("Dependencias de Node. Se regeneran con npm install.", .seguro)
        case "Pods" where hay("Podfile"):
            return ("Dependencias de CocoaPods. Se regeneran con pod install.", .seguro)
        case "build" where hay("build.gradle") || hay("build.gradle.kts") || hay("pubspec.yaml") || hay("CMakeLists.txt"):
            return ("Resultado de compilación. Se regenera al compilar.", .seguro)
        case ".gradle" where hay("settings.gradle") || hay("settings.gradle.kts") || hay("build.gradle") || hay("gradlew"):
            return ("Caché de Gradle del proyecto. Se regenera al compilar.", .seguro)
        case ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular":
            return ("Caché de compilación web. Se regenera al compilar.", .seguro)
        case ".expo" where hay("package.json"):
            return ("Caché de Expo. Se regenera al iniciar el proyecto.", .seguro)
        case ".dart_tool" where hay("pubspec.yaml"):
            return ("Caché de Flutter/Dart. Se regenera con flutter pub get.", .seguro)
        case "DerivedData":
            return ("Compilación de Xcode. Se regenera al compilar.", .seguro)
        case ".build" where hay("Package.swift"):
            return ("Compilación de Swift/Xcode. Se regenera al compilar.", .seguro)
        case "target" where hay("Cargo.toml") || hay("pom.xml"):
            return ("Resultado de compilación (Rust/Java). Se regenera al compilar.", .seguro)
        case ".venv":
            return ("Entorno virtual de Python. Se puede recrear, pero tendrás que reinstalar los paquetes.", .revisar)
        case "venv" where hay("requirements.txt") || hay("pyproject.toml") || hay("setup.py"):
            return ("Entorno virtual de Python. Se puede recrear, pero tendrás que reinstalar los paquetes.", .revisar)
        default:
            return nil
        }
    }

    // MARK: - Carpetas ocultas de herramientas

    private static let ocultasConocidas: Set<String> = [
        ".Trash", ".ssh", ".gnupg", ".config", ".local", ".cache", ".npm", ".gradle", ".android", ".m2",
        ".cargo", ".rustup", ".nvm", ".vscode", ".zsh_sessions", ".docker", ".kube", ".aws", ".azure",
        ".oh-my-zsh", ".claude", ".git", ".cups", ".bun", ".pyenv", ".rbenv", ".sdkman", ".swiftpm",
        ".expo", ".CFUserTextEncoding", ".DS_Store",
    ]
    private static let subcarpetasBasura: Set<String> = ["cache", "caches", "logs", "log", "tmp", ".tmp", "temp",
                                                          "crashpad", "crash-reports", "Cache", "Logs"]

    func herramientas(_ apps: AppsInstaladas) -> [Elemento] {
        var r: [Elemento] = []
        for c in Rutas.hijos(Rutas.home) {
            let n = c.lastPathComponent
            guard n.hasPrefix("."), Rutas.esCarpeta(c), !Self.ocultasConocidas.contains(n) else { continue }
            let comando = apps.comandoPara(carpetaOculta: n)
            // Muchas herramientas se instalan dentro de su propia carpeta (~/.opencode/bin/opencode).
            let traeSuPrograma = Rutas.esCarpeta(c.appendingPathComponent("bin"))
            let instalado = comando != nil || traeSuPrograma || apps.estaInstalado(carpeta: String(n.dropFirst()))
            let ultimo = Fechas.masReciente(c)
            let dias = ultimo.map { Int(Date().timeIntervalSince($0) / 86400) } ?? 9999
            let detalle: String
            let riesgo: Riesgo
            if instalado {
                detalle = "Configuración e historial de una herramienta instalada\(comando.map { " (comando «\($0)»)" } ?? ""). Si la borras, perderás su configuración."
                riesgo = .cuidado
            } else if dias < 30 {
                detalle = "Se usó \(Formato.haceCuanto(ultimo).lowercased()), así que probablemente la herramienta sigue en uso. Bórrala solo si ya no la usas."
                riesgo = .cuidado
            } else {
                detalle = "Lleva \(Formato.haceCuanto(ultimo).lowercased().replacingOccurrences(of: "hace ", with: "")) sin usarse y no encontré el programa que la creó: probablemente sea un resto."
                riesgo = .revisar
            }
            r.append(Elemento(
                nombre: n, detalle: detalle, rutas: [c], ultimoUso: ultimo, categoria: .herramientas,
                riesgo: riesgo, seleccionado: false))

            for sub in Rutas.hijos(c) where Self.subcarpetasBasura.contains(sub.lastPathComponent) && Rutas.esCarpeta(sub) {
                r.append(Elemento(
                    nombre: "\(n) › \(sub.lastPathComponent)",
                    detalle: sub.lastPathComponent.lowercased().contains("log")
                        ? "Registros de \(n). Solo sirven para diagnosticar errores."
                        : "Archivos temporales de \(n). Se regeneran solos.",
                    rutas: [sub], ultimoUso: Fechas.masReciente(sub), categoria: .herramientas,
                    riesgo: .seguro, seleccionado: true))
            }
        }
        return Tamanos.medir(r)
    }

    // MARK: - Instaladores

    func instaladores() -> [Elemento] {
        let extensiones: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
        var r: [Elemento] = []
        for raiz in ["Downloads", "Desktop", "Documents"] {
            guard let e = fm.enumerator(at: Rutas.enHome(raiz), includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if url.lastPathComponent == "node_modules" { e.skipDescendants(); continue }
                if e.level > 4 { e.skipDescendants(); continue }
                guard extensiones.contains(url.pathExtension.lowercased()) else { continue }
                let ultimo = Fechas.ultimoUsoArchivo(url)
                let dias = ultimo.map { Date().timeIntervalSince($0) / 86400 } ?? 999
                r.append(Elemento(
                    nombre: url.lastPathComponent,
                    detalle: "Instalador. Si ya instalaste el programa, no lo necesitas. Siempre puedes volver a descargarlo.",
                    rutas: [url], ultimoUso: ultimo, categoria: .instaladores,
                    riesgo: .seguro, seleccionado: dias > 7))
            }
        }
        return Tamanos.medir(r)
    }

    // MARK: - Archivos grandes y duplicados

    private static let noEntrar: Set<String> = ["node_modules", "build", "Pods", "site-packages", "DerivedData",
                                                 ".build", "venv", ".venv", "Library"]

    /// Recorre las carpetas personales una sola vez y saca los archivos grandes y los duplicados.
    func grandesYDuplicados() -> [Elemento] {
        let limiteGrande: Int64 = 100 * 1024 * 1024
        let limiteDuplicado: Int64 = 10 * 1024 * 1024
        let instaladores: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
        let claves: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey,
                                        .fileAllocatedSizeKey, .fileSizeKey]
        var r: [Elemento] = []
        var porTamano: [Int: [URL]] = [:]

        for c in Rutas.hijos(Rutas.home) {
            let n = c.lastPathComponent
            guard !n.hasPrefix("."), n != "Library", n != "Applications", Rutas.esCarpeta(c) else { continue }
            guard let e = fm.enumerator(at: c, includingPropertiesForKeys: claves,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                guard let v = try? url.resourceValues(forKeys: Set(claves)) else { continue }
                if v.isDirectory == true {
                    if Self.noEntrar.contains(url.lastPathComponent)
                        || Rutas.existe(url.appendingPathComponent("pyvenv.cfg")) { e.skipDescendants() }
                    continue
                }
                guard v.isRegularFile == true else { continue }
                let ocupado = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                let bytes = v.fileSize ?? 0
                if Int64(bytes) >= limiteDuplicado { porTamano[bytes, default: []].append(url) }
                guard ocupado >= limiteGrande, !instaladores.contains(url.pathExtension.lowercased()) else { continue }
                var el = Elemento(
                    nombre: url.lastPathComponent,
                    detalle: "Archivo grande en \(Formato.rutaCorta(url.deletingLastPathComponent())). Revisa si todavía lo necesitas.",
                    rutas: [url], ultimoUso: Fechas.ultimoUsoArchivo(url), categoria: .grandes,
                    riesgo: .cuidado, seleccionado: false)
                el.tamano = ocupado
                r.append(el)
            }
        }

        // Copias de seguridad de iPhone/iPad
        for b in Rutas.hijos(Rutas.enHome("Library/Application Support/MobileSync/Backup")) where Rutas.esCarpeta(b) {
            var el = Elemento(nombre: "Copia de seguridad de iPhone/iPad",
                              detalle: "Copia local de un dispositivo. Bórrala solo si ya tienes otra copia (por ejemplo en iCloud).",
                              rutas: [b], ultimoUso: Fechas.masReciente(b), categoria: .grandes,
                              riesgo: .cuidado, seleccionado: false)
            el.tamano = Tamanos.de(b)
            r.append(el)
        }

        r.append(contentsOf: duplicados(porTamano))
        return r
    }

    private func duplicados(_ porTamano: [Int: [URL]]) -> [Elemento] {
        var r: [Elemento] = []
        let descargas = Rutas.enHome("Downloads").path + "/"
        for (bytes, urls) in porTamano where urls.count > 1 {
            var porHash: [String: [URL]] = [:]
            for u in urls {
                if let h = Huella.sha256(u) { porHash[h, default: []].append(u) }
            }
            for (_, iguales) in porHash where iguales.count > 1 {
                // Se conserva la copia que no está en Descargas y, entre esas, la más antigua.
                let ordenadas = iguales.sorted { a, b in
                    let da = a.path.hasPrefix(descargas), db = b.path.hasPrefix(descargas)
                    if da != db { return !da }
                    let ca = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantFuture
                    let cb = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantFuture
                    return ca < cb
                }
                let original = ordenadas[0]
                for copia in ordenadas.dropFirst() {
                    var el = Elemento(
                        nombre: copia.lastPathComponent,
                        detalle: "Copia idéntica de \(Formato.rutaCorta(original)), que se conserva.",
                        rutas: [copia], ultimoUso: Fechas.ultimoUsoArchivo(copia), categoria: .duplicados,
                        riesgo: .revisar, seleccionado: copia.path.hasPrefix(descargas))
                    el.tamano = Int64(bytes)
                    r.append(el)
                }
            }
        }
        return r
    }

    // MARK: - Registros

    func registros(_ apps: AppsInstaladas) -> [Elemento] {
        var r: [Elemento] = []
        for c in Rutas.hijos(Rutas.enHome("Library/Logs")) {
            let n = c.lastPathComponent
            if n.hasPrefix(".") { continue }
            // Los de apps desinstaladas ya aparecen en "Restos".
            if !apps.estaInstalado(carpeta: n) { continue }
            r.append(Elemento(
                nombre: n == "DiagnosticReports" ? "Reportes de fallos" : "Registros de \(nombreBonito(n))",
                detalle: "Archivos de registro. Solo sirven para diagnosticar errores.",
                rutas: [c], ultimoUso: Fechas.masReciente(c), categoria: .registros,
                riesgo: .seguro, seleccionado: true))
        }
        return Tamanos.medir(r)
    }

    // MARK: - Papelera

    func papelera() -> [Elemento] {
        let trash = Rutas.enHome(".Trash")
        guard (try? fm.contentsOfDirectory(atPath: trash.path))?.isEmpty == false else { return [] }
        var el = Elemento(nombre: "Contenido de la Papelera",
                          detalle: "Vaciarla borra definitivamente lo que ya enviaste a la Papelera.",
                          rutas: [trash], ultimoUso: Fechas.masReciente(trash), categoria: .papelera,
                          riesgo: .revisar, seleccionado: false, accion: .vaciarPapelera)
        el.tamano = Tamanos.de(trash)
        return [el]
    }

    // MARK: - Utilidades

    /// "com.google.Chrome" -> "Chrome (com.google.Chrome)"
    private func nombreBonito(_ n: String) -> String {
        let partes = n.split(separator: ".")
        if partes.count >= 3, let ultima = partes.last {
            return "\(ultima) (\(n))"
        }
        return n
    }
}
