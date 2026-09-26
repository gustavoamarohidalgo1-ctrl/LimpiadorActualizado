import AppKit
import CoreServices
import Foundation

enum Shell {
    /// Ejecuta un programa y devuelve su salida estándar (stderr se descarta).
    @discardableResult
    static func ejecutar(_ programa: String, _ argumentos: [String]) -> (estado: Int32, salida: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: programa)
        p.arguments = argumentos
        let tubo = Pipe()
        p.standardOutput = tubo
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let datos = tubo.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: datos, as: UTF8.self))
    }
}

enum Tamanos {
    /// Espacio real ocupado en disco (usa `du`, que es mucho más rápido que recorrer en Swift).
    static func de(_ url: URL) -> Int64 {
        let r = Shell.ejecutar("/usr/bin/du", ["-sk", url.path])
        let primera = r.salida.split(separator: "\n").last ?? ""
        let kb = Int64(primera.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        return kb * 1024
    }

    static func de(_ urls: [URL]) -> Int64 {
        urls.reduce(0) { $0 + de($1) }
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

    /// Calcula el tamaño de muchos elementos en paralelo.
    static func medir(_ elementos: [Elemento]) -> [Elemento] {
        var copia = elementos
        let candado = NSLock()
        DispatchQueue.concurrentPerform(iterations: elementos.count) { i in
            let t = de(elementos[i].rutas)
            candado.lock()
            copia[i].tamano = t
            candado.unlock()
        }
        return copia
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

    /// La fecha más reciente entre la carpeta y sus hijos directos.
    /// Sirve para saber cuándo se usó por última vez una carpeta sin recorrerla entera.
    static func masReciente(_ url: URL, ignorando: Set<String> = []) -> Date? {
        var mejor = modificacion(url)
        let hijos = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for h in hijos where !ignorando.contains(h.lastPathComponent) {
            if let d = modificacion(h), d > (mejor ?? .distantPast) { mejor = d }
        }
        return mejor
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

    static func esCarpeta(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    static func hijos(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])) ?? []
    }
}

/// Reglas que impiden borrar cosas importantes pase lo que pase.
enum Seguridad {
    private static let protegidas: Set<String> = {
        let h = Rutas.home.path
        let rel = ["", "Library", "Library/Caches", "Library/Application Support", "Library/Preferences",
                   "Library/Logs", "Library/Containers", "Library/Group Containers", "Library/Keychains",
                   "Library/Mail", "Library/Messages", "Library/Mobile Documents", "Library/CloudStorage",
                   "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications",
                   ".Trash", ".ssh", ".gnupg", ".config", ".local", ".cache", ".npm", ".gradle", ".android"]
        return Set(rel.map { $0.isEmpty ? h : h + "/" + $0 })
    }()

    static func sePuedeBorrar(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        let h = Rutas.home.path
        guard p.hasPrefix(h + "/") || p.hasPrefix("/Users/Shared/") else { return false }
        if protegidas.contains(p) { return false }
        if p.contains("/Library/Keychains") || p.contains("/.ssh/") { return false }
        return true
    }

    /// Comprueba si la app tiene Acceso total al disco (necesario para leer la Papelera y algunas carpetas).
    static func tieneAccesoTotal() -> Bool {
        let prueba = Rutas.enHome("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: prueba.path)) != nil
    }
}

/// Lo que está instalado en este Mac, para saber qué carpetas son restos.
struct AppsInstaladas {
    private(set) var bundleIDs: Set<String> = []
    private(set) var fabricantes: Set<String> = []   // "com.google", "us.zoom"…
    private(set) var nombres: Set<String> = []        // coincidencia flexible
    private(set) var nombresExactos: Set<String> = [] // procesos del sistema, comandos
    private(set) var comandos: Set<String> = []

    static func normalizar(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func cargar() -> AppsInstaladas {
        var r = AppsInstaladas()
        let fm = FileManager.default
        let carpetas = ["/Applications", "/System/Applications", Rutas.enHome("Applications").path,
                        "/System/Library/CoreServices", "/Applications/Xcode.app/Contents/Applications",
                        "/Applications/Xcode.app/Contents/Developer/Applications",
                        "/Library/Application Support"]
        for carpeta in carpetas {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: carpeta),
                                        includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if e.level > 3 { e.skipDescendants(); continue }
                guard url.pathExtension == "app" else { continue }
                r.agregarApp(url)
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { r.agregarBundleID(id) }
            if let n = app.localizedName { r.nombres.insert(normalizar(n)) }
        }
        // Procesos y componentes del sistema: sus carpetas nunca son "restos".
        for dir in ["/usr/libexec", "/usr/sbin", "/usr/bin", "/System/Library/PrivateFrameworks",
                    "/System/Library/Frameworks", "/System/Library/CoreServices"] {
            for n in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
                r.nombresExactos.insert(normalizar((n as NSString).deletingPathExtension))
            }
        }
        // Comandos instalados (para las carpetas ocultas de herramientas).
        let rutasComandos = ["/opt/homebrew/bin", "/usr/local/bin", Rutas.enHome(".local/bin").path,
                             Rutas.enHome(".npm-global/bin").path, Rutas.enHome(".bun/bin").path,
                             Rutas.enHome(".cargo/bin").path, "/opt/homebrew/lib/node_modules",
                             "/usr/local/lib/node_modules"]
        for dir in rutasComandos {
            for n in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
                r.comandos.insert(normalizar(n))
                r.nombresExactos.insert(normalizar(n))
            }
        }
        return r
    }

    private mutating func agregarApp(_ url: URL) {
        nombres.insert(Self.normalizar(url.deletingPathExtension().lastPathComponent))
        guard let b = Bundle(url: url) else { return }
        if let id = b.bundleIdentifier { agregarBundleID(id) }
        for clave in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            if let v = b.infoDictionary?[clave] as? String { nombres.insert(Self.normalizar(v)) }
        }
    }

    private mutating func agregarBundleID(_ id: String) {
        let l = id.lowercased()
        bundleIDs.insert(l)
        // El "fabricante" (com.google.xxx -> google) también cuenta: muchas apps
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
        "tokenbucketratelimiter", "contextstoreagent", "loginwindow", "pbs", "mbuseragent", "networkserviceproxy", "familycircle", "coreparsec", "keychains",
    ]

    /// Decide si una carpeta pertenece a algo que sigue instalado.
    func estaInstalado(carpeta: String) -> Bool {
        let l = carpeta.lowercased()
        if l.hasPrefix("com.apple.") || l.contains("group.com.apple.") || l.hasPrefix("apple") { return true }
        let n = Self.normalizar((carpeta as NSString).deletingPathExtension)
        if n.count < 3 || Self.ignorar.contains(n) || nombresExactos.contains(n) { return true }

        if l.contains(".") && l.split(separator: ".").count >= 3 {
            // Parece un identificador de app (com.empresa.app).
            let id = l.hasSuffix(".plist") ? String(l.dropLast(6)) : l
            if bundleIDs.contains(id) { return true }
            // Mismo fabricante que una app instalada (com.microsoft.office con Word instalado): se respeta.
            if fabricantes.contains(id.split(separator: ".").prefix(2).joined(separator: ".")) { return true }
            for b in bundleIDs where id.hasPrefix(b + ".") || b.hasPrefix(id + ".") { return true }
            let partes = id.split(separator: ".").map { Self.normalizar(String($0)) }
            // com.empresa.app: coincide si "app" es una app instalada.
            if let ultima = partes.last, ultima.count >= 4, nombres.contains(ultima) { return true }
            return false
        }

        for nombre in nombres where nombre.count >= 4 {
            if nombre == n { return true }
            // "BraveSoftware" empieza por "brave"; "AndroidStudio" contiene "android".
            if n.count >= 4 && (nombre.contains(n) || n.hasPrefix(nombre)) { return true }
        }
        return nombres.contains(n)
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
}

import CryptoKit

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
}
