import Darwin
import Foundation

// MARK: - Tipos del índice

/// En qué parte de la carpeta personal está algo. Decide qué búsquedas aplican.
enum Zona: UInt8 {
    /// Escritorio, Documentos, Descargas, Música… (lo que el usuario ve)
    case personal
    /// Carpetas que empiezan con punto
    case oculta
    /// ~/Library
    case library
    /// /Users/Shared
    case compartida
}

enum TipoSensible: UInt8 {
    case keystore, certificado, llaveSSH, secreto, firebase
}

struct ArchivoSensible: Hashable {
    let ruta: String
    let tipo: TipoSensible
    /// En Library son credenciales de una app (su sesión); en tus carpetas, claves tuyas.
    let zona: Zona
    var nombre: String { (ruta as NSString).lastPathComponent }
}

/// Carpetas de proyectos que se regeneran solas.
enum TipoArtefacto: UInt8 {
    case node, pods, compilacion, gradle, cxx, kotlin, web, expo, dart, xcode, swiftpm, cargo, venv

    var descripcion: String {
        switch self {
        case .node: return "dependencias de Node"
        case .pods: return "dependencias de CocoaPods"
        case .compilacion: return "resultado de compilación"
        case .gradle: return "caché de Gradle del proyecto"
        case .cxx: return "compilación nativa (NDK)"
        case .kotlin: return "datos temporales de Kotlin"
        case .web: return "caché de compilación web"
        case .expo: return "caché de Expo"
        case .dart: return "caché de Flutter/Dart"
        case .xcode: return "compilación de Xcode"
        case .swiftpm: return "compilación de Swift"
        case .cargo: return "compilación de Rust/Java"
        case .venv: return "entorno virtual de Python"
        }
    }
}

struct Artefacto: Hashable {
    let ruta: String
    let tipo: TipoArtefacto
}

struct ArchivoIndexado: Hashable {
    let ruta: String
    /// Espacio que ocupa en disco.
    let bytes: Int64
    /// Tamaño lógico (el que se compara para buscar duplicados).
    let tamano: Int64
    let modificado: Int
    let dispositivo: Int32
    let inodo: UInt64
    let zona: Zona

    var url: URL { URL(fileURLWithPath: ruta) }
    var fecha: Date { Date(timeIntervalSince1970: TimeInterval(modificado)) }
    var nombre: String { (ruta as NSString).lastPathComponent }
    var carpeta: String { (ruta as NSString).deletingLastPathComponent }
}

struct InfoCarpeta {
    var bytes: Int64 = 0
    var archivos: Int32 = 0
    /// Última modificación de cualquier archivo dentro (no solo la carpeta).
    var masReciente = 0
    /// Igual, pero sin contar node_modules, build… (la actividad real de un proyecto).
    var masRecientePropio = 0
    var contenido = Contenido()
}

enum TipoCacheInterna: UInt8 { case cache, registros }

// MARK: - Índice

/// Índice completo de la carpeta personal: tamaño, actividad y contenido de cada carpeta.
/// Se construye en una sola pasada paralela y todas las categorías lo consultan.
final class Indice: @unchecked Sendable {
    fileprivate(set) var carpetas: [String: InfoCarpeta] = [:]
    fileprivate(set) var hijos: [String: [String]] = [:]
    fileprivate(set) var grandes: [ArchivoIndexado] = []
    fileprivate(set) var duplicables: [ArchivoIndexado] = []
    fileprivate(set) var instaladores: [ArchivoIndexado] = []
    fileprivate(set) var comprimidos: [ArchivoIndexado] = []
    fileprivate(set) var artefactos: [Artefacto] = []
    fileprivate(set) var sensibles: [ArchivoSensible] = []
    fileprivate(set) var repos: Set<String> = []
    fileprivate(set) var releases: [String] = []
    fileprivate(set) var apps: [String] = []
    fileprivate(set) var cachesInternas: [(ruta: String, tipo: TipoCacheInterna)] = []
    fileprivate(set) var wrappersGradle: [String] = []
    fileprivate(set) var archivosTotales = 0
    fileprivate(set) var bytesTotales: Int64 = 0
    fileprivate(set) var sinPermiso = 0
    fileprivate(set) var duracion: TimeInterval = 0
    fileprivate(set) var raices: [String] = []

    // MARK: Consultas

    func info(_ ruta: String) -> InfoCarpeta? { carpetas[ruta] }

    /// Espacio que ocupa una ruta (carpeta o archivo).
    func bytes(de url: URL) -> Int64 {
        if let i = carpetas[url.path] { return i.bytes }
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return 0 }
        if (st.st_mode & S_IFMT) == S_IFDIR {
            // Carpeta pequeña o fuera del índice: se mide aparte.
            return estaIndexada(url.path) ? 0 : Tamanos.de(url)
        }
        return Int64(st.st_blocks) * 512
    }

    func masReciente(de urls: [URL]) -> Date? {
        var mejor = 0
        for u in urls {
            if let i = carpetas[u.path] {
                mejor = max(mejor, i.masReciente)
            } else {
                var st = stat()
                if lstat(u.path, &st) == 0 { mejor = max(mejor, Int(st.st_mtimespec.tv_sec)) }
            }
        }
        return mejor > 0 ? Date(timeIntervalSince1970: TimeInterval(mejor)) : nil
    }

    func masRecientePropio(de ruta: String) -> Date? {
        guard let i = carpetas[ruta], i.masRecientePropio > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(i.masRecientePropio))
    }

    func contenido(de urls: [URL]) -> Contenido {
        var c = Contenido()
        for u in urls {
            if let i = carpetas[u.path] { c.sumar(i.contenido) }
        }
        return c
    }

    func sensibles(dentro urls: [URL]) -> [ArchivoSensible] {
        let bases = urls.map(\.path)
        return sensibles.filter { s in bases.contains { s.ruta == $0 || s.ruta.hasPrefix($0 + "/") } }
    }

    func repos(dentro urls: [URL]) -> [String] {
        let bases = urls.map(\.path)
        return repos.filter { r in bases.contains { r == $0 || r.hasPrefix($0 + "/") } }.sorted()
    }

    func releases(dentro urls: [URL]) -> [String] {
        let bases = urls.map(\.path)
        return releases.filter { r in bases.contains { r.hasPrefix($0 + "/") || r == $0 } }
    }

    /// Subcarpetas registradas, de mayor a menor.
    func hijosOrdenados(de ruta: String) -> [(ruta: String, bytes: Int64)] {
        (hijos[ruta] ?? [])
            .compactMap { h in carpetas[h].map { (h, $0.bytes) } }
            .sorted { $0.1 > $1.1 }
    }

    func estaIndexada(_ ruta: String) -> Bool {
        raices.contains { ruta == $0 || ruta.hasPrefix($0 + "/") }
    }

    // MARK: Construcción

    struct Progreso {
        var archivos: Int
        var bytes: Int64
        var ruta: String
    }

    static func construir(accesoTotal: Bool, progreso: (Progreso) -> Void) -> Indice {
        let inicio = Date()
        let indice = Indice()
        let marcador = Marcador()
        let home = Rutas.home.path
        let omitir = rutasOmitidas(home: home, accesoTotal: accesoTotal)
        let candado = NSLock()

        // 1. Recorrido superficial: la carpeta personal hasta 2-3 niveles.
        //    Lo que hay más abajo se reparte en «unidades» que se recorren en paralelo.
        let superficial = Recorrido(marcador: marcador, home: home, accesoTotal: accesoTotal, omitir: omitir)
        var unidades: [Unidad] = []
        let libraryPrefijo = home + "/Library/"
        _ = superficial.recorrer(
            raiz: home, contexto: Acumulador(zona: .personal), umbral: 0,
            cortar: { ruta, nivel in nivel >= (ruta.hasPrefix(libraryPrefijo) ? 3 : 2) },
            alCortar: { unidades.append($0) })
        indice.absorber(superficial)
        if Rutas.existe(URL(fileURLWithPath: "/Users/Shared")) {
            unidades.append(Unidad(ruta: "/Users/Shared", contexto: Acumulador(zona: .compartida)))
        }

        // 2. Unidades en paralelo.
        let lista = unidades
        var resultados = [Acumulador?](repeating: nil, count: unidades.count)
        let grupo = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: grupo) {
            DispatchQueue.concurrentPerform(iterations: lista.count) { i in
                let r = Recorrido(marcador: marcador, home: home, accesoTotal: accesoTotal, omitir: omitir)
                marcador.actual(lista[i].ruta)
                let a = r.recorrer(raiz: lista[i].ruta, contexto: lista[i].contexto, umbral: 1_000_000,
                                   cortar: nil, alCortar: nil)
                candado.lock()
                resultados[i] = a
                indice.absorber(r)
                candado.unlock()
            }
        }
        while grupo.wait(timeout: .now() + 0.15) == .timedOut {
            let m = marcador.leer()
            progreso(Progreso(archivos: m.0, bytes: m.1, ruta: m.2))
        }

        // 3. Sumar cada unidad a sus carpetas superiores.
        for (i, u) in unidades.enumerated() {
            guard let a = resultados[i] else { continue }
            indice.carpetas[u.ruta] = a.info
            guard u.ruta.hasPrefix(home + "/") else { continue }
            var p = (u.ruta as NSString).deletingLastPathComponent
            while p.count >= home.count {
                if var info = indice.carpetas[p] {
                    info.bytes += a.bytes
                    info.archivos += a.archivos
                    info.masReciente = max(info.masReciente, a.masReciente)
                    if !a.esArtefacto { info.masRecientePropio = max(info.masRecientePropio, a.masRecientePropio) }
                    info.contenido.sumar(a.contenido)
                    indice.carpetas[p] = info
                }
                if p == home { break }
                p = (p as NSString).deletingLastPathComponent
            }
        }

        let m = marcador.leer()
        indice.archivosTotales = m.0
        indice.bytesTotales = (indice.carpetas[home]?.bytes ?? 0) + (indice.carpetas["/Users/Shared"]?.bytes ?? 0)
        indice.raices = [home, "/Users/Shared"]
        indice.duracion = Date().timeIntervalSince(inicio)
        progreso(Progreso(archivos: m.0, bytes: indice.bytesTotales, ruta: ""))
        return indice
    }

    private func absorber(_ r: Recorrido) {
        carpetas.merge(r.carpetas) { _, nuevo in nuevo }
        for (k, v) in r.hijos { hijos[k, default: []].append(contentsOf: v) }
        grandes += r.grandes
        duplicables += r.duplicables
        instaladores += r.instaladores
        comprimidos += r.comprimidos
        artefactos += r.artefactos
        sensibles += r.sensibles
        repos.formUnion(r.repos)
        releases += r.releases
        apps += r.apps
        cachesInternas += r.cachesInternas
        wrappersGradle += r.wrappersGradle
        sinPermiso += r.sinPermiso
    }

    /// Carpetas que no se recorren: datos privados de macOS (que además piden permisos)
    /// y, sin Acceso total al disco, las que el sistema bloquea.
    private static func rutasOmitidas(home: String, accesoTotal: Bool) -> Set<String> {
        var rel = [
            ".Trash", "Library/Mail", "Library/Messages", "Library/Safari", "Library/Cookies", "Library/HomeKit",
            "Library/IdentityServices", "Library/Metadata", "Library/Suggestions", "Library/Accounts",
            "Library/Calendars", "Library/Reminders", "Library/Biome", "Library/DuetExpertCenter",
            "Library/PersonalizationPortrait", "Library/Sharing", "Library/Daemon Containers",
            "Library/Autosave Information", "Library/Trial", "Library/Assistant", "Library/ContainerManager",
            "Library/Photos", "Library/Keychains", "Library/Application Support/com.apple.TCC",
            "Library/Application Support/AddressBook", "Library/Application Support/CallHistoryDB",
            "Library/Application Support/CallHistoryTransactions", "Library/Application Support/Knowledge",
            "Library/Application Support/FileProvider", "Library/Application Support/CloudDocs",
            "Library/Application Support/com.apple.sharedfilelist", "Library/Application Support/DifferentialPrivacy",
        ]
        if !accesoTotal {
            rel += ["Library/Containers", "Library/Group Containers", "Library/Mobile Documents",
                    "Library/Application Support/MobileSync"]
        }
        return Set(rel.map { home + "/" + $0 })
    }
}

// MARK: - Recorrido de una parte del disco

fileprivate struct Unidad {
    let ruta: String
    let contexto: Acumulador
}

/// Contadores de una carpeta mientras se recorre, más el contexto que heredan sus hijos.
fileprivate struct Acumulador {
    var bytes: Int64 = 0
    var archivos: Int32 = 0
    var masReciente = 0
    var masRecientePropio = 0
    var contenido = Contenido()

    var zona: Zona
    /// Contar documentos, fotos, claves… (no dentro de node_modules, apps o .git).
    var clasificar = true
    /// Dentro de un artefacto (build, node_modules…): solo se buscan apps para publicar.
    var enArtefacto = false
    /// Guardar las subcarpetas en el índice (no dentro de apps ni de .git).
    var registrarHijos = true
    var registrarse = true
    var esArtefacto = false
    var enCacheInterna = false

    init(zona: Zona) { self.zona = zona }

    var info: InfoCarpeta {
        InfoCarpeta(bytes: bytes, archivos: archivos, masReciente: masReciente,
                    masRecientePropio: masRecientePropio, contenido: contenido)
    }

    func hijo() -> Acumulador {
        var h = Acumulador(zona: zona)
        h.clasificar = clasificar
        h.enArtefacto = enArtefacto
        h.registrarHijos = registrarHijos
        h.registrarse = registrarHijos
        h.enCacheInterna = enCacheInterna
        return h
    }

    mutating func absorber(_ h: Acumulador) {
        bytes += h.bytes
        archivos += h.archivos
        masReciente = max(masReciente, h.masReciente)
        if !h.esArtefacto { masRecientePropio = max(masRecientePropio, h.masRecientePropio) }
        contenido.sumar(h.contenido)
    }
}

/// Contadores compartidos entre hilos para mostrar el progreso.
fileprivate final class Marcador: @unchecked Sendable {
    private let candado = NSLock()
    private var archivos = 0
    private var bytes: Int64 = 0
    private var ruta = ""

    func sumar(_ a: Int, _ b: Int64) {
        candado.lock(); archivos += a; bytes += b; candado.unlock()
    }

    func actual(_ r: String) {
        candado.lock(); ruta = r; candado.unlock()
    }

    func leer() -> (Int, Int64, String) {
        candado.lock(); defer { candado.unlock() }
        return (archivos, bytes, ruta)
    }
}

fileprivate final class Recorrido {
    var carpetas: [String: InfoCarpeta] = [:]
    var hijos: [String: [String]] = [:]
    var grandes: [ArchivoIndexado] = []
    var duplicables: [ArchivoIndexado] = []
    var instaladores: [ArchivoIndexado] = []
    var comprimidos: [ArchivoIndexado] = []
    var artefactos: [Artefacto] = []
    var sensibles: [ArchivoSensible] = []
    var repos: Set<String> = []
    var releases: [String] = []
    var apps: [String] = []
    var cachesInternas: [(ruta: String, tipo: TipoCacheInterna)] = []
    var wrappersGradle: [String] = []
    var sinPermiso = 0

    private let marcador: Marcador
    private let home: String
    private let appSupport: String
    private let accesoTotal: Bool
    private let omitir: Set<String>
    private var pendientesArchivos = 0
    private var pendientesBytes: Int64 = 0

    init(marcador: Marcador, home: String, accesoTotal: Bool, omitir: Set<String>) {
        self.marcador = marcador
        self.home = home
        self.appSupport = home + "/Library/Application Support/"
        self.accesoTotal = accesoTotal
        self.omitir = omitir
    }

    /// Recorre `raiz` y devuelve sus totales. Si `cortar` dice que sí, esa carpeta no se recorre
    /// aquí: se entrega a `alCortar` para recorrerla en otro hilo.
    func recorrer(raiz: String, contexto: Acumulador, umbral: Int64,
                  cortar: ((String, Int) -> Bool)?, alCortar: ((Unidad) -> Void)?) -> Acumulador {
        guard let raizC = strdup(raiz) else { return contexto }
        defer { free(raizC) }
        var argumentos: [UnsafeMutablePointer<CChar>?] = [raizC, nil]
        guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return contexto }
        defer { fts_close(fts) }

        var pila = ContiguousArray<Acumulador>()
        pila.reserveCapacity(64)
        var resultado = contexto

        func cerrar(_ e: UnsafeMutablePointer<FTSENT>) {
            let a = pila.removeLast()
            if a.registrarse && (a.bytes >= umbral) {
                let ruta = String(cString: e.pointee.fts_path)
                carpetas[ruta] = a.info
                if e.pointee.fts_level > 0 {
                    hijos[(ruta as NSString).deletingLastPathComponent, default: []].append(ruta)
                }
            }
            if pila.isEmpty { resultado = a } else { pila[pila.count - 1].absorber(a) }
        }

        while let e = fts_read(fts) {
            let nivel = Int(e.pointee.fts_level)
            switch Int32(e.pointee.fts_info) {
            case FTS_D:
                while pila.count > nivel { cerrarSinRuta(&pila, &resultado) }
                var a = pila.last?.hijo() ?? contexto
                let st = e.pointee.fts_statp.pointee
                a.bytes = Int64(st.st_blocks) * 512
                a.masReciente = Int(st.st_mtimespec.tv_sec)
                a.masRecientePropio = a.masReciente
                let nombre = nombreDe(e)
                var saltar = false

                if nivel > 0 {
                    let ruta = String(cString: e.pointee.fts_path)
                    if nivel <= 3 && omitir.contains(ruta) {
                        saltar = true
                    } else if let cortar, cortar(ruta, nivel) {
                        a.bytes = 0
                        alCortar?(Unidad(ruta: ruta, contexto: pila.last?.hijo() ?? contexto))
                        saltar = true
                    } else {
                        examinarCarpeta(nombre: nombre, ruta: ruta, acumulador: &a, padre: pila.last ?? contexto,
                                        saltar: &saltar)
                    }
                } else {
                    // Raíz de una unidad: se examina igual que cualquier carpeta.
                    let ruta = String(cString: e.pointee.fts_path)
                    examinarCarpeta(nombre: nombre, ruta: ruta, acumulador: &a, padre: contexto, saltar: &saltar)
                }
                pila.append(a)
                if saltar { fts_set(fts, e, FTS_SKIP) }

            case FTS_DP, FTS_DNR, FTS_ERR:
                if Int32(e.pointee.fts_info) == FTS_DNR { sinPermiso += 1 }
                while pila.count > nivel + 1 { cerrarSinRuta(&pila, &resultado) }
                if pila.count == nivel + 1 { cerrar(e) }

            case FTS_F:
                while pila.count > nivel { cerrarSinRuta(&pila, &resultado) }
                guard !pila.isEmpty else { continue }
                archivo(e, &pila[pila.count - 1])

            case FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard !pila.isEmpty else { continue }
                pila[pila.count - 1].bytes += Int64(e.pointee.fts_statp.pointee.st_blocks) * 512

            case FTS_NS:
                sinPermiso += 1

            default:
                break
            }
        }
        while !pila.isEmpty { cerrarSinRuta(&pila, &resultado) }
        marcador.sumar(pendientesArchivos, pendientesBytes)
        pendientesArchivos = 0
        pendientesBytes = 0
        return resultado
    }

    /// Cierre de emergencia (no debería pasar): suma la carpeta a su padre sin registrarla.
    private func cerrarSinRuta(_ pila: inout ContiguousArray<Acumulador>, _ resultado: inout Acumulador) {
        let a = pila.removeLast()
        if pila.isEmpty { resultado = a } else { pila[pila.count - 1].absorber(a) }
    }

    @inline(__always)
    private func nombreDe(_ e: UnsafeMutablePointer<FTSENT>) -> String {
        let p = e.pointee.fts_path + (Int(e.pointee.fts_pathlen) - Int(e.pointee.fts_namelen))
        return String(cString: p)
    }

    // MARK: Carpetas

    private static let paquetes: Set<String> = [
        "app", "framework", "bundle", "plugin", "appex", "xpc", "kext", "xcarchive", "dsym", "xcframework",
        "docset", "qlgenerator", "mdimporter", "prefpane", "saver", "systemextension", "driver",
    ]
    private static let bibliotecas: Set<String> = [
        "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band", "aplibrary",
    ]
    private static let cachesInternasNombres: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "GraphiteDawnCache",
        "ShaderCache", "GrShaderCache", "component_crx_cache", "extensions_crx_cache", "optimization_guide_model_store",
    ]
    private static let codigoDeTerceros: Set<String> = ["node_modules", "site-packages", "vendor", "Pods", "__pycache__"]
    private static let componentes: Set<String> = ["plugins", "extensions", "packages", "lib", "runtimes", "versions",
                                                    "bin", "toolchains", "sdk", "downloads"]

    private func examinarCarpeta(nombre: String, ruta: String, acumulador a: inout Acumulador, padre: Acumulador,
                                 saltar: inout Bool) {
        let ext = (nombre as NSString).pathExtension.lowercased()
        if ruta == home + "/Library" { a.zona = .library }

        if nombre == ".git" {
            repos.insert((ruta as NSString).deletingLastPathComponent)
            a.clasificar = false
            a.registrarHijos = false
            return
        }
        if nombre.hasPrefix(".") && a.zona == .personal { a.zona = .oculta }

        if !ext.isEmpty && Self.bibliotecas.contains(ext) {
            a.contenido.bibliotecas += 1
            a.clasificar = false
            a.registrarHijos = false
            // La fototeca está protegida: sin permiso, ni se intenta.
            if ext == "photoslibrary" && !accesoTotal { saltar = true }
            return
        }
        if !ext.isEmpty && Self.paquetes.contains(ext) {
            if ext == "app" && (a.zona == .personal || a.zona == .compartida) && padre.clasificar { apps.append(ruta) }
            a.clasificar = false
            a.registrarHijos = false
            return
        }
        if Self.codigoDeTerceros.contains(nombre) { a.clasificar = false }
        // En carpetas de herramientas, sus componentes (plugins, runtimes…) no son archivos tuyos.
        if a.zona == .oculta && Self.componentes.contains(nombre.lowercased()) { a.clasificar = false }

        // Artefactos de proyectos: solo en tus carpetas (en Library o en carpetas ocultas son de las apps).
        if padre.clasificar && !padre.enArtefacto && (padre.zona == .personal || padre.zona == .compartida) {
            let carpetaPadre = (ruta as NSString).deletingLastPathComponent
            if carpetaPadre != home, let tipo = Self.artefacto(nombre: nombre, ruta: ruta, padre: carpetaPadre) {
                artefactos.append(Artefacto(ruta: ruta, tipo: tipo))
                a.enArtefacto = true
                a.clasificar = false
                a.esArtefacto = true
                return
            }
        }

        // Cachés que las apps (sobre todo las de Electron/Chromium) guardan junto a sus datos.
        if !a.enCacheInterna && ruta.hasPrefix(appSupport) {
            let padreNombre = ((ruta as NSString).deletingLastPathComponent as NSString).lastPathComponent
            if Self.cachesInternasNombres.contains(nombre)
                || ((nombre == "CacheStorage" || nombre == "ScriptCache") && padreNombre == "Service Worker") {
                cachesInternas.append((ruta, .cache))
                a.enCacheInterna = true
            } else if nombre == "logs" || nombre == "Logs" || nombre == "Crashpad" {
                cachesInternas.append((ruta, .registros))
                a.enCacheInterna = true
            }
        }
    }

    private static func artefacto(nombre: String, ruta: String, padre: String) -> TipoArtefacto? {
        func hay(_ archivo: String) -> Bool { access(padre + "/" + archivo, F_OK) == 0 }
        let gradle = { hay("build.gradle") || hay("build.gradle.kts") || hay("settings.gradle") || hay("settings.gradle.kts") }
        switch nombre {
        case "node_modules": return .node
        case "Pods": return hay("Podfile") ? .pods : nil
        case "build":
            return gradle() || hay("pubspec.yaml") || hay("CMakeLists.txt") || hay("package.json") ? .compilacion : nil
        case ".gradle": return gradle() || hay("gradlew") ? .gradle : nil
        case ".cxx": return gradle() ? .cxx : nil
        case ".kotlin": return gradle() ? .kotlin : nil
        case ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular", ".vite":
            return hay("package.json") ? .web : nil
        case ".expo": return hay("package.json") ? .expo : nil
        case ".dart_tool": return hay("pubspec.yaml") ? .dart : nil
        case "DerivedData": return .xcode
        case ".build": return hay("Package.swift") ? .swiftpm : nil
        case "target": return hay("Cargo.toml") || hay("pom.xml") ? .cargo : nil
        default:
            if nombre.lowercased().contains("env") && access(ruta + "/pyvenv.cfg", F_OK) == 0 { return .venv }
            return nil
        }
    }

    // MARK: Archivos

    private func archivo(_ e: UnsafeMutablePointer<FTSENT>, _ a: inout Acumulador) {
        let st = e.pointee.fts_statp.pointee
        var b = Int64(st.st_blocks) * 512
        // Un archivo con varios enlaces solo se libera al borrar todos: se reparte su tamaño.
        if st.st_nlink > 1 { b /= Int64(st.st_nlink) }
        let mt = Int(st.st_mtimespec.tv_sec)
        a.bytes += b
        a.archivos += 1
        if mt > a.masReciente { a.masReciente = mt }
        if mt > a.masRecientePropio { a.masRecientePropio = mt }

        pendientesArchivos += 1
        pendientesBytes += b
        if pendientesArchivos >= 4096 {
            marcador.sumar(pendientesArchivos, pendientesBytes)
            pendientesArchivos = 0
            pendientesBytes = 0
        }

        let largoNombre = Int(e.pointee.fts_namelen)
        let nombre = e.pointee.fts_path + (Int(e.pointee.fts_pathlen) - largoNombre)
        let tamano = Int64(st.st_size)

        if a.enArtefacto {
            // Dentro de build/: solo interesan las apps compiladas para publicar.
            if tamano > 1_000_000 {
                let clave = claveExtension(nombre, largoNombre)
                if clave == extAPK || clave == extAAB || clave == extIPA {
                    let n = String(cString: nombre).lowercased()
                    if Self.esRelease(n) { releases.append(String(cString: e.pointee.fts_path)) }
                }
            }
            return
        }
        guard a.clasificar else { return }

        let clave = claveExtension(nombre, largoNombre)
        let tipo = tablaExtensiones[clave] ?? .otro
        switch tipo {
        case .documento:
            a.contenido.documentos += 1
        case .foto:
            if tamano >= 150_000 { a.contenido.fotos += 1 }
        case .video:
            if tamano >= 2_000_000 { a.contenido.videos += 1 }
        case .audio:
            if tamano >= 1_000_000 { a.contenido.audio += 1 }
        case .codigo:
            a.contenido.codigo += 1
        case .base:
            a.contenido.bases += 1
        case .clave:
            clasificarClave(e, clave: clave, tamano: tamano, acumulador: &a)
        case .instalador:
            if clave == extAAB || ((clave == extAPK || clave == extIPA) && Self.esRelease(String(cString: nombre).lowercased())) {
                releases.append(String(cString: e.pointee.fts_path))
            }
            if clave != extAAB && a.zona == .personal && tamano >= 1_000_000 {
                instaladores.append(indexado(e, st, b, a.zona))
            }
        case .comprimido:
            if a.zona == .personal && tamano >= 5_000_000 { comprimidos.append(indexado(e, st, b, a.zona)) }
        case .json, .plist, .properties:
            let n = String(cString: nombre)
            if n == "google-services.json" || n == "GoogleService-Info.plist" {
                sensibles.append(ArchivoSensible(ruta: String(cString: e.pointee.fts_path), tipo: .firebase, zona: a.zona))
            } else if n == "credentials.json" || n.hasPrefix("service-account") || n.hasPrefix("client_secret") {
                sensibles.append(ArchivoSensible(ruta: String(cString: e.pointee.fts_path), tipo: .secreto, zona: a.zona))
            } else if n == "gradle-wrapper.properties" {
                wrappersGradle.append(String(cString: e.pointee.fts_path))
            }
        case .otro:
            nombresEspeciales(e, nombre: nombre, largo: largoNombre, zona: a.zona)
        }

        if b >= 50_000_000 { grandes.append(indexado(e, st, b, a.zona)) }
        if a.zona == .personal && tamano >= 1_000_000 && tipo != .instalador {
            duplicables.append(indexado(e, st, b, a.zona))
        }
    }

    private func clasificarClave(_ e: UnsafeMutablePointer<FTSENT>, clave: UInt64, tamano: Int64,
                                 acumulador a: inout Acumulador) {
        let ruta = String(cString: e.pointee.fts_path)
        let nombre = (ruta as NSString).lastPathComponent.lowercased()
        if clave == extKEY && tamano >= 20_000 {
            // Un .key grande es una presentación de Keynote, no una clave.
            a.contenido.documentos += 1
            return
        }
        if clave == extJKS || clave == extKEYSTORE {
            if nombre == "debug.keystore" { return }   // la de depuración se regenera sola
            sensibles.append(ArchivoSensible(ruta: ruta, tipo: .keystore, zona: a.zona))
            return
        }
        // Certificados públicos de autoridades que traen muchas librerías: no son de nadie.
        let publicos = ["cacert", "ca-cert", "ca_cert", "ca-bundle", "ca_bundle", "ca-certificates", "certifi", "root-ca", "rootca"]
        if nombre == "cert.pem" || publicos.contains(where: { nombre.contains($0) }) { return }
        sensibles.append(ArchivoSensible(ruta: ruta, tipo: .certificado, zona: a.zona))
    }

    private func nombresEspeciales(_ e: UnsafeMutablePointer<FTSENT>, nombre: UnsafePointer<CChar>, largo: Int, zona: Zona) {
        // .env, .env.local, .npmrc, .netrc… y llaves SSH (id_rsa, id_ed25519…)
        if nombre[0] == 46 /* . */ {
            let n = String(cString: nombre)
            let plantilla = [".example", ".template", ".sample", ".dist", ".defaults"].contains { n.hasSuffix($0) }
            if (n == ".env" || n.hasPrefix(".env.")) && !plantilla || n == ".netrc" || n == ".pypirc" {
                sensibles.append(ArchivoSensible(ruta: String(cString: e.pointee.fts_path), tipo: .secreto, zona: zona))
            } else if n == ".npmrc" {
                // Solo es secreto si guarda un token de acceso.
                let ruta = String(cString: e.pointee.fts_path)
                if let texto = try? String(contentsOfFile: ruta, encoding: .utf8), texto.contains("_auth") || texto.contains("token") {
                    sensibles.append(ArchivoSensible(ruta: ruta, tipo: .secreto, zona: zona))
                }
            }
        } else if largo >= 5 && nombre[0] == 105 && nombre[1] == 100 && nombre[2] == 95 /* id_ */ {
            let n = String(cString: nombre)
            if ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"].contains(n) {
                sensibles.append(ArchivoSensible(ruta: String(cString: e.pointee.fts_path), tipo: .llaveSSH, zona: zona))
            }
        }
    }

    private func indexado(_ e: UnsafeMutablePointer<FTSENT>, _ st: stat, _ b: Int64, _ zona: Zona) -> ArchivoIndexado {
        ArchivoIndexado(ruta: String(cString: e.pointee.fts_path), bytes: b, tamano: Int64(st.st_size),
                        modificado: Int(st.st_mtimespec.tv_sec), dispositivo: st.st_dev, inodo: st.st_ino, zona: zona)
    }

    /// app-release.aab sí; app-debug.apk o app-release-unsigned.apk no.
    static func esRelease(_ n: String) -> Bool {
        n.contains("release") && !n.contains("unsigned") && !n.contains("debugsigned") && !n.contains("debug")
    }
}

// MARK: - Extensiones

fileprivate enum TipoArchivo: UInt8 {
    case otro, documento, foto, video, audio, codigo, base, clave, instalador, comprimido, json, plist, properties
}

/// Convierte la extensión (hasta 16 letras, en minúsculas) en un número para compararla rápido.
@inline(__always)
fileprivate func claveExtension(_ p: UnsafePointer<CChar>, _ n: Int) -> UInt64 {
    var i = n - 1
    let tope = max(0, n - 18)
    while i >= tope {
        if p[i] == 46 { break }
        i -= 1
    }
    guard i > 0, i >= tope, p[i] == 46 else { return 0 }
    let largo = n - i - 1
    guard largo >= 1 && largo <= 16 else { return 0 }
    var k: UInt64 = 14_695_981_039_346_656_037
    var j = i + 1
    while j < n {
        var c = UInt8(bitPattern: p[j])
        if c >= 65 && c <= 90 { c += 32 }
        k = (k ^ UInt64(c)) &* 1_099_511_628_211
        j += 1
    }
    return k
}

fileprivate func claveDe(_ ext: String) -> UInt64 {
    ext.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
}

fileprivate let extAPK = claveDe("apk")
fileprivate let extAAB = claveDe("aab")
fileprivate let extIPA = claveDe("ipa")
fileprivate let extKEY = claveDe("key")
fileprivate let extJKS = claveDe("jks")
fileprivate let extKEYSTORE = claveDe("keystore")

fileprivate let tablaExtensiones: [UInt64: TipoArchivo] = {
    var t: [UInt64: TipoArchivo] = [:]
    func agregar(_ tipo: TipoArchivo, _ lista: String) {
        for e in lista.split(separator: " ") { t[claveDe(String(e))] = tipo }
    }
    agregar(.documento, "pdf doc docx xls xlsx ppt pptx pages numbers odt ods odp rtf psd ai sketch fig xd indd afdesign afphoto procreate kra xcf blend epub")
    agregar(.foto, "jpg jpeg heic heif dng cr2 cr3 nef arw raf orf rw2")
    agregar(.video, "mp4 mov m4v avi mkv mts m2ts 3gp webm")
    agregar(.audio, "mp3 m4a wav aiff aif flac aac ogg")
    agregar(.codigo, "swift kt kts java js jsx ts tsx py rb go rs c cc cpp h hpp m mm cs php dart vue svelte scala")
    agregar(.base, "sqlite sqlite3 db realm sqlitedb")
    agregar(.clave, "jks keystore p12 pfx p8 mobileprovision provisionprofile pem key")
    agregar(.instalador, "dmg pkg mpkg iso xip apk xapk ipa aab")
    agregar(.comprimido, "zip rar 7z tar gz tgz bz2 xz zst")
    agregar(.json, "json")
    agregar(.plist, "plist")
    agregar(.properties, "properties")
    return t
}()
