import AppKit
import CoreServices
import CryptoKit
import Foundation

enum Shell {
    /// Ejecuta un programa y devuelve su salida estándar (stderr se descarta).
    /// Si tarda más de `limite` segundos, se detiene y la salida se da por vacía.
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
        var completo = lectura.wait(timeout: .now() + limite) != .timedOut
        if !completo {
            p.terminate()
            completo = lectura.wait(timeout: .now() + 2) != .timedOut
            // Si ni así termina, se le obliga: esperar para siempre colgaría el análisis.
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        p.waitUntilExit()
        // Si la lectura no terminó (un proceso hijo sigue con la salida abierta), no se toca: sigue en otro hilo.
        return (p.terminationStatus, completo ? String(decoding: caja.datos, as: UTF8.self) : "")
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
    /// La carpeta personal. `LIMPIADORMAC_HOME` permite analizar una carpeta de prueba (tests y diagnóstico).
    static let home: URL = {
        if let prueba = ProcessInfo.processInfo.environment["LIMPIADORMAC_HOME"], !prueba.isEmpty {
            return URL(fileURLWithPath: prueba, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()
    static func enHome(_ rel: String) -> URL { home.appendingPathComponent(rel) }
    static func existe(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    static func existe(_ ruta: String) -> Bool { FileManager.default.fileExists(atPath: ruta) }

    /// Existe aunque sea un enlace roto (no lo sigue).
    static func existeSinSeguir(_ ruta: String) -> Bool {
        var st = stat()
        return lstat(ruta, &st) == 0
    }

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

    /// ¿Alguna carpeta superior de `ruta` está en el conjunto?
    static func estaDentro(_ ruta: String, de conjunto: Set<String>) -> Bool {
        var actual = Substring(ruta)
        while let barra = actual.lastIndex(of: "/"), barra > actual.startIndex {
            actual = actual[..<barra]
            if conjunto.contains(String(actual)) { return true }
        }
        return false
    }
}

/// Carpetas que macOS reserva para tu usuario fuera de la carpeta personal (/var/folders/…).
enum Sistema {
    /// Temporales de tu usuario. macOS borra lo viejo al reiniciar, pero en un Mac que casi nunca se reinicia se acumula.
    static let temporal: String? = ruta(Int32(_CS_DARWIN_USER_TEMP_DIR))
    /// Cachés de tu usuario: compiladores, shaders, apps…
    static let caches: String? = ruta(Int32(_CS_DARWIN_USER_CACHE_DIR))

    private static func ruta(_ nombre: Int32) -> String? {
        let tam = confstr(nombre, nil, 0)
        guard tam > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: tam)
        guard confstr(nombre, &buffer, tam) > 0 else { return nil }
        let r = String(cString: buffer)
        guard r.count > 1 else { return nil }
        return URL(fileURLWithPath: r).standardizedFileURL.path
    }
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
                   ".gradle", ".android", ".android/avd", ".vscode", ".vscode/extensions", ".cursor",
                   ".cursor/extensions"]
        return Set(rel.map { $0.isEmpty ? h : h + "/" + $0 })
    }()

    /// Carpetas de sistema de tu usuario: se puede borrar lo que tienen dentro, nunca ellas mismas.
    private static let raicesSistema: [String] = [Sistema.temporal, Sistema.caches].compactMap { $0 }.map(normalizada)

    /// La ruta real, sin «/private» delante de /var y /tmp (macOS lo quita o no según si el archivo existe).
    static func normalizada(_ ruta: String) -> String {
        var p = URL(fileURLWithPath: ruta).standardizedFileURL.resolvingSymlinksInPath().path
        for prefijo in ["/private/var/", "/private/tmp/", "/private/etc/"] where p.hasPrefix(prefijo) {
            p = String(p.dropFirst("/private".count))
        }
        return p
    }

    static func sePuedeBorrar(_ url: URL) -> Bool {
        let p = normalizada(url.path)
        // Nunca se borra una llave de firma, un llavero, una llave SSH ni el historial de git, aunque alguien lo seleccione.
        let ext = url.pathExtension.lowercased()
        if ext == "jks" || ext == "keystore" { return false }
        if p.contains("/Library/Keychains") || p.contains("/.ssh/") || p.hasSuffix("/.ssh")
            || p.hasSuffix("/.git") || p.contains("/.git/") { return false }

        let h = Rutas.home.path
        if p == h || p.hasPrefix(h + "/") || p.hasPrefix("/Users/Shared/") { return !protegidas.contains(p) && p != h }
        if let raiz = raicesSistema.first(where: { p.hasPrefix($0 + "/") }) { return p.count > raiz.count + 1 }
        return esVersionDeHomebrew(p) || esInstaladorDeMacOS(p)
    }

    /// «/opt/homebrew/Cellar/node/20.1.0»: una versión concreta de una fórmula (nunca la fórmula entera).
    static func esVersionDeHomebrew(_ p: String) -> Bool {
        for cellar in ["/opt/homebrew/Cellar/", "/usr/local/Cellar/"] where p.hasPrefix(cellar) {
            return p.dropFirst(cellar.count).split(separator: "/").count == 2
        }
        return false
    }

    /// «/Applications/Install macOS Sonoma.app»
    static func esInstaladorDeMacOS(_ p: String) -> Bool {
        let prefijo = "/Applications/Install macOS "
        return p.hasPrefix(prefijo) && p.hasSuffix(".app") && !p.dropFirst("/Applications/".count).contains("/")
    }

    /// Comprueba si la app tiene Acceso total al disco (necesario para leer la Papelera y algunas carpetas).
    static func tieneAccesoTotal() -> Bool {
        let prueba = Rutas.enHome("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: prueba.path)) != nil
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
    /// Las claves de carpetas compartidas («group.com.x.y», «EQUIPO.x») se comparan sin ese prefijo.
    func appAbierta(_ claves: [String]) -> String? {
        let todas = claves + claves.map(AppsInstaladas.sinPrefijoDeGrupo)
        let ids = todas.map { $0.lowercased() }.filter { $0.contains(".") }
        let nombres = todas.map(AppsInstaladas.normalizar).filter { $0.count >= 4 }
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

/// Archivos que los programas tienen abiertos ahora mismo (según `lsof`).
struct ArchivosAbiertos {
    var rutas: [String] = []
    /// `false` si no se pudo saber: entonces no se ofrece nada que dependa de esto.
    var disponible = false

    static func capturar() -> ArchivosAbiertos {
        var r = ArchivosAbiertos()
        let salida = Shell.ejecutar("/usr/sbin/lsof", ["-n", "-P", "-w", "-F", "n", "-u", String(getuid())], limite: 40).salida
        for linea in salida.split(separator: "\n") where linea.first == "n" {
            var ruta = String(linea.dropFirst())
            guard ruta.hasPrefix("/") else { continue }
            if ruta.hasPrefix("/private/var/") || ruta.hasPrefix("/private/tmp/") { ruta = String(ruta.dropFirst(8)) }
            r.rutas.append(ruta)
        }
        r.disponible = !r.rutas.isEmpty
        return r
    }

    /// Nombres de lo que hay directamente dentro de `carpeta` y algún programa tiene abierto (o dentro).
    func hijosEnUso(de carpeta: String) -> Set<String> {
        let prefijo = carpeta + "/"
        var r = Set<String>()
        for ruta in rutas where ruta.hasPrefix(prefijo) {
            if let primero = ruta.dropFirst(prefijo.count).split(separator: "/").first { r.insert(String(primero)) }
        }
        return r
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
