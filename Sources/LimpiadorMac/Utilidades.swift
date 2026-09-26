import AppKit
import CoreServices
import CryptoKit
import Foundation

enum Shell {
    /// Ejecuta un programa y devuelve su salida estándar (stderr se descarta).
    /// Si tarda más de `limite` segundos, se detiene.
    @discardableResult
    static func ejecutar(_ programa: String, _ argumentos: [String], limite: TimeInterval = 120) -> (estado: Int32, salida: String) {
        final class Caja: @unchecked Sendable { var datos = Data() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: programa)
        p.arguments = argumentos
        let tubo = Pipe()
        p.standardOutput = tubo
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let caja = Caja()
        let lectura = DispatchGroup()
        lectura.enter()
        DispatchQueue.global().async {
            caja.datos = tubo.fileHandleForReading.readDataToEndOfFile()
            lectura.leave()
        }
        do { try p.run() } catch {
            try? tubo.fileHandleForWriting.close()
            return (-1, "")
        }
        if lectura.wait(timeout: .now() + limite) == .timedOut {
            p.terminate()
            _ = lectura.wait(timeout: .now() + 1)
        }
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: caja.datos, as: UTF8.self))
    }
}

enum Tamanos {
    /// Espacio real ocupado en disco (usa `du`, que es mucho más rápido que recorrer en Swift).
    static func de(_ url: URL) -> Int64 {
        let r = Shell.ejecutar("/usr/bin/du", ["-sk", url.path])
        let ultima = r.salida.split(separator: "\n").last ?? ""
        let kb = Int64(ultima.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        return kb * 1024
    }

    /// Tamaño de cada hijo directo de una carpeta (archivos y carpetas).
    static func hijos(de url: URL) -> [(url: URL, tamano: Int64)] {
        let r = Shell.ejecutar("/usr/bin/du", ["-a", "-k", "-d", "1", url.path])
        var resultado: [(URL, Int64)] = []
        let base = url.standardizedFileURL.path
        for linea in r.salida.split(separator: "\n") {
            let partes = linea.split(separator: "\t", maxSplits: 1)
            guard partes.count == 2, let kb = Int64(partes[0].trimmingCharacters(in: .whitespaces)) else { continue }
            let ruta = String(partes[1])
            if URL(fileURLWithPath: ruta).standardizedFileURL.path == base { continue }
            resultado.append((URL(fileURLWithPath: ruta), kb * 1024))
        }
        return resultado.sorted { $0.1 > $1.1 }
    }
}

enum Fechas {
    static func modificacion(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Fecha de "último uso" según Spotlight, si la tiene.
    static func ultimoUsoSpotlight(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Último uso de un archivo: lo más reciente entre Spotlight y la fecha de modificación.
    static func ultimoUsoArchivo(_ url: URL) -> Date? {
        [ultimoUsoSpotlight(url), modificacion(url)].compactMap { $0 }.max()
    }
}

enum Rutas {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static func enHome(_ rel: String) -> URL { home.appendingPathComponent(rel) }
    static func existe(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    static func existe(_ ruta: String) -> Bool { FileManager.default.fileExists(atPath: ruta) }

    static func esCarpeta(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    static func hijos(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])) ?? []
    }

    static func padre(_ ruta: String) -> String { (ruta as NSString).deletingLastPathComponent }
    static func nombre(_ ruta: String) -> String { (ruta as NSString).lastPathComponent }
}

/// Reglas que impiden borrar cosas importantes pase lo que pase.
enum Seguridad {
    private static let protegidas: Set<String> = {
        let h = Rutas.home.path
        let rel = ["", "Library", "Library/Caches", "Library/Application Support", "Library/Preferences",
                   "Library/Logs", "Library/Containers", "Library/Group Containers", "Library/Keychains",
                   "Library/Mail", "Library/Messages", "Library/Mobile Documents", "Library/CloudStorage",
                   "Library/LaunchAgents", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures",
                   "Public", "Applications", ".Trash", ".ssh", ".gnupg", ".config", ".local", ".cache", ".npm",
                   ".gradle", ".android", ".android/avd"]
        return Set(rel.map { $0.isEmpty ? h : h + "/" + $0 })
    }()

    static func sePuedeBorrar(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        let h = Rutas.home.path
        guard p.hasPrefix(h + "/") || p.hasPrefix("/Users/Shared/") else { return false }
        if protegidas.contains(p) { return false }
        if p.contains("/Library/Keychains") || p.contains("/.ssh/") || p.hasSuffix("/.git") { return false }
        // Nunca se borra una llave de firma suelta, aunque alguien la seleccione.
        let ext = url.pathExtension.lowercased()
        if ext == "jks" || ext == "keystore" { return false }
        return true
    }

    /// Comprueba si la app tiene Acceso total al disco (necesario para leer la Papelera y algunas carpetas).
    static func tieneAccesoTotal() -> Bool {
        let prueba = Rutas.enHome("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: prueba.path)) != nil
    }
}

/// Lo que está instalado en este Mac, para saber qué carpetas son restos y a quién pertenece cada cosa.
struct AppsInstaladas {
    private(set) var bundleIDs: Set<String> = []
    private(set) var fabricantes: Set<String> = []   // "com.google", "us.zoom"…
    private(set) var nombres: Set<String> = []        // coincidencia flexible
    private(set) var nombresExactos: Set<String> = [] // procesos del sistema, comandos
    private(set) var comandos: Set<String> = []
    /// Apps en /Applications (para saber si una copia suelta sobra).
    private(set) var idsEnAplicaciones: Set<String> = []
    private var nombrePorID: [String: String] = [:]
    private var nombrePorNombre: [String: String] = [:]

    static func normalizar(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func cargar(appsExtra: [String] = []) -> AppsInstaladas {
        var r = AppsInstaladas()
        let fm = FileManager.default
        let carpetas = ["/Applications", "/System/Applications", Rutas.enHome("Applications").path,
                        "/System/Library/CoreServices", "/Applications/Xcode.app/Contents/Applications",
                        "/Applications/Xcode.app/Contents/Developer/Applications", "/Library/Application Support"]
        for carpeta in carpetas {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: carpeta), includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if e.level > 3 { e.skipDescendants(); continue }
                guard url.pathExtension == "app" else { continue }
                r.agregarApp(url, enAplicaciones: carpeta == "/Applications")
            }
        }
        // Apps que viven fuera de Aplicaciones (en el Escritorio, en Descargas…) también cuentan.
        for ruta in appsExtra { r.agregarApp(URL(fileURLWithPath: ruta), enAplicaciones: false) }

        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { r.agregarBundleID(id, nombre: app.localizedName) }
            if let n = app.localizedName { r.agregarNombre(n) }
        }
        // Procesos y componentes del sistema: sus carpetas nunca son «restos».
        for dir in ["/usr/libexec", "/usr/sbin", "/usr/bin", "/System/Library/PrivateFrameworks",
                    "/System/Library/Frameworks", "/System/Library/CoreServices"] {
            for n in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
                r.nombresExactos.insert(normalizar((n as NSString).deletingPathExtension))
            }
        }
        // Homebrew: fórmulas (comandos) y casks (apps).
        for dir in ["/opt/homebrew/Cellar", "/usr/local/Cellar"] {
            for n in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] { r.agregarComando(n) }
        }
        for dir in ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"] {
            for n in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] { r.agregarNombre(n); r.agregarComando(n) }
        }
        // Comandos instalados: el PATH real de la terminal más los sitios habituales.
        var rutasComandos = Set(["/opt/homebrew/bin", "/usr/local/bin", Rutas.enHome(".local/bin").path,
                                 Rutas.enHome(".npm-global/bin").path, Rutas.enHome(".bun/bin").path,
                                 Rutas.enHome(".cargo/bin").path, "/opt/homebrew/lib/node_modules",
                                 "/usr/local/lib/node_modules", Rutas.enHome(".local/share/uv/tools").path,
                                 Rutas.enHome(".local/pipx/venvs").path])
        rutasComandos.formUnion(pathDeLaTerminal())
        for version in (try? fm.contentsOfDirectory(atPath: Rutas.enHome(".nvm/versions/node").path)) ?? [] {
            rutasComandos.insert(Rutas.enHome(".nvm/versions/node/\(version)/bin").path)
        }
        for dir in rutasComandos {
            for n in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] { r.agregarComando(n) }
        }
        return r
    }

    /// El PATH que ve tu terminal (incluye lo que agregan .zshrc y los instaladores).
    private static func pathDeLaTerminal() -> [String] {
        let salida = Shell.ejecutar("/bin/zsh", ["-lic", "print -r -- __PATH__$PATH"], limite: 4).salida
        guard let linea = salida.split(separator: "\n").last(where: { $0.hasPrefix("__PATH__") }) else { return [] }
        return linea.dropFirst(8).split(separator: ":").map(String.init)
    }

    private mutating func agregarApp(_ url: URL, enAplicaciones: Bool) {
        let visible = url.deletingPathExtension().lastPathComponent
        agregarNombre(visible)
        guard let b = Bundle(url: url) else { return }
        if let id = b.bundleIdentifier {
            agregarBundleID(id, nombre: visible)
            if enAplicaciones { idsEnAplicaciones.insert(id.lowercased()) }
        }
        for clave in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            if let v = b.infoDictionary?[clave] as? String {
                let k = Self.normalizar(v)
                nombres.insert(k)
                if nombrePorNombre[k] == nil { nombrePorNombre[k] = visible }
            }
        }
    }

    private mutating func agregarNombre(_ n: String) {
        let k = Self.normalizar(n)
        guard !k.isEmpty else { return }
        nombres.insert(k)
        if nombrePorNombre[k] == nil { nombrePorNombre[k] = n }
    }

    private mutating func agregarComando(_ n: String) {
        let k = Self.normalizar(n)
        guard !k.isEmpty else { return }
        comandos.insert(k)
        nombresExactos.insert(k)
    }

    private mutating func agregarBundleID(_ id: String, nombre: String?) {
        let l = id.lowercased()
        bundleIDs.insert(l)
        if let nombre, nombrePorID[l] == nil { nombrePorID[l] = nombre }
        // El «fabricante» (com.google.xxx -> google) también cuenta: muchas apps
        // guardan sus datos en una carpeta con el nombre de la empresa.
        let partes = l.split(separator: ".")
        if partes.count >= 2 {
            nombres.insert(Self.normalizar(String(partes[1])))
            fabricantes.insert(partes.prefix(2).joined(separator: "."))
        }
        if let ultima = partes.last { nombres.insert(Self.normalizar(String(ultima))) }
    }

    /// Carpetas de macOS o genéricas que nunca se consideran restos.
    private static let ignorar: Set<String> = [
        "addressbook", "animoji", "callhistorydb", "callhistorytransactions", "categories", "clouddocs",
        "crashreporter", "differentialprivacy", "diskimages", "facetime", "fileprovider", "intelligenceflow",
        "knowledge", "music", "sesstorage", "appsubscriptions", "defaultstore", "defaultstoreshm",
        "defaultstorewal", "mobilesync", "icloud", "dock", "syncservices", "cef", "electron", "caches",
        "askpermission", "homekit", "mail", "safari", "photos", "contacts", "calendars", "notes", "reminders",
        "stocks", "weather", "maps", "news", "tv", "podcasts", "books", "shortcuts", "siri", "voicememos",
        "com", "org", "net", "io", "app", "apps", "data", "storage", "backups", "temp", "tmp", "logs",
        "instruments", "xcode", "simulator", "coresimulator", "developer", "java", "python", "node",
        "accounts", "identityservices", "diagnosticreports", "avatarcacheindex", "mobilemeaccounts",
        "tokenbucketratelimiter", "contextstoreagent", "loginwindow", "pbs", "mbuseragent",
        "networkserviceproxy", "familycircle", "coreparsec", "keychains", "limpiadormac", "geoservices",
        "cloudkit", "passkit", "familycircled", "sharedfilelistd", "localizationswitcherd",
    ]

    /// Decide si una carpeta pertenece a algo que sigue instalado.
    func estaInstalado(carpeta: String) -> Bool {
        let l = carpeta.lowercased()
        if l.hasPrefix("com.apple.") || l.contains("group.com.apple.") || l.hasPrefix("apple") { return true }
        let n = Self.normalizar((carpeta as NSString).deletingPathExtension)
        if n.count < 3 || Self.ignorar.contains(n) || nombresExactos.contains(n) { return true }

        if l.contains(".") && l.split(separator: ".").count >= 3 {
            // Parece un identificador de app (com.empresa.app).
            let id = Self.sinExtension(l)
            if bundleIDs.contains(id) { return true }
            // Mismo fabricante que una app instalada (com.microsoft.office con Word instalado): se respeta.
            if fabricantes.contains(id.split(separator: ".").prefix(2).joined(separator: ".")) { return true }
            for b in bundleIDs where id.hasPrefix(b + ".") || b.hasPrefix(id + ".") { return true }
            let partes = id.split(separator: ".").map { Self.normalizar(String($0)) }
            // com.empresa.app: coincide si «app» es una app instalada.
            if let ultima = partes.last, ultima.count >= 4, nombres.contains(ultima) { return true }
            return false
        }

        for nombre in nombres where nombre.count >= 4 {
            if nombre == n { return true }
            // «BraveSoftware» empieza por «brave»; «AndroidStudio» contiene «android».
            if n.count >= 4 && (nombre.contains(n) || n.hasPrefix(nombre)) { return true }
        }
        return nombres.contains(n)
    }

    /// Nombre visible de la app a la que pertenece una carpeta («com.brave.Browser» → «Brave Browser»).
    func nombreApp(para carpeta: String) -> String? {
        let l = Self.sinExtension(carpeta.lowercased())
        if let n = nombrePorID[l] { return n }
        for (id, n) in nombrePorID where l.hasPrefix(id + ".") || id.hasPrefix(l + ".") { return n }
        let n = Self.normalizar(carpeta)
        if let v = nombrePorNombre[n] { return v }
        if n.count >= 4 {
            for (k, v) in nombrePorNombre where k.count >= 4 && (k.hasPrefix(n) || n.hasPrefix(k)) { return v }
        }
        return nil
    }

    /// ¿Existe un comando con un nombre parecido al de la carpeta oculta?
    func comandoPara(carpetaOculta: String) -> String? {
        let n = Self.normalizar(carpetaOculta)
        guard n.count >= 3 else { return nil }
        if comandos.contains(n) { return n }
        let base = Self.normalizar(String(carpetaOculta.dropFirst().split(separator: "-").first ?? ""))
        if base.count >= 3, comandos.contains(base) { return base }
        return nil
    }

    private static func sinExtension(_ s: String) -> String {
        for ext in [".plist", ".savedstate", ".binarycookies"] where s.hasSuffix(ext) { return String(s.dropLast(ext.count)) }
        return s
    }
}

/// Qué está funcionando ahora mismo: apps abiertas, emuladores, Gradle…
struct Procesos {
    struct AppAbierta {
        let nombre: String
        let bundleID: String
    }

    var apps: [AppAbierta] = []
    /// Cada proceso (programa y argumentos), en minúsculas.
    var lineas: [String] = []
    /// Nombres normalizados de los programas en ejecución.
    var programas: Set<String> = []
    var avds: Set<String> = []
    var simuladores: Set<String> = []
    var gradle = false

    static func capturar() -> Procesos {
        var p = Procesos()
        for a in NSWorkspace.shared.runningApplications {
            guard let n = a.localizedName else { continue }
            p.apps.append(AppAbierta(nombre: n, bundleID: a.bundleIdentifier?.lowercased() ?? ""))
        }
        let ps = Shell.ejecutar("/bin/ps", ["-axww", "-o", "args="], limite: 10).salida
        for linea in ps.split(separator: "\n") {
            let l = String(linea)
            p.lineas.append(l.lowercased())
            p.programas.insert(AppsInstaladas.normalizar(programa(de: l)))
            if l.contains("qemu-system") || l.contains("/emulator ") {
                if let r = l.range(of: "-avd ") {
                    let resto = l[r.upperBound...]
                    if let nombre = resto.split(separator: " ").first { p.avds.insert(String(nombre)) }
                }
            }
            if l.contains("GradleDaemon") || l.contains("org.gradle.launcher.daemon") { p.gradle = true }
        }
        let json = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "-j"], limite: 15).salida
        if let d = json.data(using: .utf8),
           let raiz = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let porRuntime = raiz["devices"] as? [String: [[String: Any]]] {
            for lista in porRuntime.values {
                for dispositivo in lista where (dispositivo["state"] as? String) == "Booted" {
                    if let udid = dispositivo["udid"] as? String { p.simuladores.insert(udid) }
                }
            }
        }
        return p
    }

    /// «/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --type=…» → «Google Chrome»
    private static func programa(de linea: String) -> String {
        if let r = linea.range(of: ".app/Contents/MacOS/") {
            let resto = linea[r.upperBound...]
            return resto.components(separatedBy: " -").first ?? String(resto)
        }
        let primero = linea.split(separator: " ").first.map(String.init) ?? linea
        return (primero as NSString).lastPathComponent
    }

    func estaEnUso(_ u: EnUso) -> Bool {
        switch u {
        case .app(_, let claves): return appAbierta(claves) != nil
        case .emulador(let avd): return avds.contains(avd)
        case .simulador(let udid): return simuladores.contains(udid)
        case .gradle: return gradle
        case .proceso(_, let patron): return lineas.contains { $0.contains(patron) }
        }
    }

    /// Nombre de la app (o servicio) abierta que coincide con alguna clave.
    func appAbierta(_ claves: [String]) -> String? {
        let ids = claves.map { $0.lowercased() }.filter { $0.contains(".") }
        let nombres = claves.map(AppsInstaladas.normalizar).filter { $0.count >= 4 }
        for a in apps {
            if !a.bundleID.isEmpty {
                for id in ids where a.bundleID == id || a.bundleID.hasPrefix(id + ".") || id.hasPrefix(a.bundleID + ".") {
                    return a.nombre
                }
            }
            let n = AppsInstaladas.normalizar(a.nombre)
            if nombres.contains(where: { n == $0 || n.hasPrefix($0) }) { return a.nombre }
        }
        // Servicios sin ventana (agentes, ayudantes)
        for prog in programas where prog.count >= 4 {
            if nombres.contains(where: { prog.hasPrefix($0) }) { return prog }
        }
        return nil
    }
}

enum Huella {
    /// SHA-256 del contenido completo de un archivo, leído por bloques.
    static func sha256(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            guard let bloque = try? h.read(upToCount: 4 * 1024 * 1024), !bloque.isEmpty else { break }
            hasher.update(data: bloque)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Huella rápida: los primeros y los últimos 64 KB. Descarta archivos distintos sin leerlos enteros.
    static func parcial(_ url: URL, tamano: Int64) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        guard let inicio = try? h.read(upToCount: 65_536) else { return nil }
        hasher.update(data: inicio)
        if tamano > 131_072 {
            try? h.seek(toOffset: UInt64(tamano - 65_536))
            if let fin = try? h.read(upToCount: 65_536) { hasher.update(data: fin) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
