import AppKit
import Foundation
import Security

/// Lo que dice la firma de código de una app: quién la hizo y qué carpetas compartidas usa.
struct Firma {
    /// Team ID del desarrollador («UBF8T346G9» es Microsoft).
    var equipo: String?
    /// App Groups: las carpetas de `~/Library/Group Containers` que la app tiene derecho a usar.
    var grupos: [String] = []

    static func leer(_ url: URL) -> Firma {
        var codigo: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &codigo) == errSecSuccess, let codigo else { return Firma() }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(codigo, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any] else { return Firma() }
        var f = Firma()
        f.equipo = d[kSecCodeInfoTeamIdentifier as String] as? String
        if let derechos = d[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
            f.grupos = derechos["com.apple.security.application-groups"] as? [String] ?? []
        }
        return f
    }
}

/// Lo que se sabe de una app instalada: su identificador, el de lo que lleva dentro y su firma.
struct DatosApp {
    var visible: String
    /// Identificador de la app, en minúsculas.
    var principal: String?
    /// CFBundleName, CFBundleDisplayName y CFBundleExecutable.
    var nombres: [String] = []
    var version: String?
    /// Identificadores de sus extensiones, ayudantes y apps de inicio (cada uno puede tener su propio contenedor).
    var embebidos: [String] = []
    /// Las que son extensiones de Safari (bloqueadores de contenido, extensiones web…).
    var extensionesSafari: [String] = []
    var equipos: Set<String> = []
    var grupos: Set<String> = []

    private static let anidados: [(carpeta: String, extensiones: Set<String>)] = [
        ("Contents/PlugIns", ["appex"]), ("Contents/Library/LoginItems", ["app"]), ("Contents/Helpers", ["app"]),
        ("Contents/XPCServices", ["xpc"]), ("Contents/Library/SystemExtensions", ["systemextension"]),
        ("Contents/Frameworks", ["app"]),
    ]

    static func leer(_ url: URL) -> DatosApp {
        var d = DatosApp(visible: url.deletingPathExtension().lastPathComponent)
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
            return d
        }
        d.principal = (info["CFBundleIdentifier"] as? String)?.lowercased()
        for clave in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            if let v = info[clave] as? String { d.nombres.append(v) }
        }
        d.version = info["CFBundleShortVersionString"] as? String

        var dentro: [URL] = []
        for (carpeta, extensiones) in anidados {
            for h in Rutas.hijos(url.appendingPathComponent(carpeta)) where extensiones.contains(h.pathExtension) {
                dentro.append(h)
            }
        }
        for h in dentro.prefix(120) {
            let plist = NSDictionary(contentsOf: h.appendingPathComponent("Contents/Info.plist"))
            guard let id = (plist?["CFBundleIdentifier"] as? String)?.lowercased() else { continue }
            d.embebidos.append(id)
            let punto = (plist?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
            if punto?.hasPrefix("com.apple.Safari") == true { d.extensionesSafari.append(id) }
        }
        // Las apps de Apple usan «group.com.apple.…», que ya se reconoce sin leer la firma.
        guard d.principal?.hasPrefix("com.apple.") != true else { return d }
        let conFirmaPropia = dentro.filter {
            $0.pathExtension == "appex" || $0.pathExtension == "systemextension"
                || $0.deletingLastPathComponent().lastPathComponent == "LoginItems"
        }
        for u in [url] + conFirmaPropia.prefix(24) {
            let f = Firma.leer(u)
            if let e = f.equipo, !e.isEmpty { d.equipos.insert(e.uppercased()) }
            d.grupos.formUnion(f.grupos.map { $0.lowercased() })
        }
        return d
    }
}

/// Lo que está instalado en este Mac, para saber qué carpetas son restos y a quién pertenece cada cosa.
struct AppsInstaladas {
    private(set) var bundleIDs: Set<String> = []
    private(set) var fabricantes: Set<String> = []   // "com.google", "us.zoom"…
    private(set) var nombres: Set<String> = []        // coincidencia flexible
    private(set) var nombresExactos: Set<String> = [] // procesos del sistema, comandos
    private(set) var comandos: Set<String> = []
    /// Team ID de las apps instaladas: «UBF8T346G9.Office» es de Microsoft aunque no se llame como ninguna app.
    private(set) var equipos: Set<String> = []
    /// App Groups que declaran las apps en su firma, en minúsculas.
    private(set) var grupos: Set<String> = []
    /// Apps en /Applications (para saber si una copia suelta sobra) y su versión.
    private(set) var idsEnAplicaciones: Set<String> = []
    private(set) var versionEnAplicaciones: [String: String] = [:]
    /// Extensiones de Safari instaladas: su contenedor guarda reglas compiladas y no se limpia.
    private(set) var extensionesSafari: Set<String> = []
    private var nombrePorID: [String: String] = [:]
    private var nombrePorNombre: [String: String] = [:]
    private var versionPorNombre: [String: String] = [:]
    private var nombrePorEquipo: [String: String] = [:]
    private var nombrePorGrupo: [String: String] = [:]

    static func normalizar(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func cargar(appsExtra: [String] = []) -> AppsInstaladas {
        var r = AppsInstaladas()
        let fm = FileManager.default
        let carpetas = ["/Applications", "/System/Applications", Rutas.enHome("Applications").path,
                        "/System/Library/CoreServices", "/Applications/Xcode.app/Contents/Applications",
                        "/Applications/Xcode.app/Contents/Developer/Applications", "/Library/Application Support"]
        var encontradas: [(url: URL, enAplicaciones: Bool)] = []
        var vistas = Set<String>()
        for carpeta in carpetas {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: carpeta), includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if e.level > 3 { e.skipDescendants(); continue }
                guard url.pathExtension == "app", vistas.insert(url.path).inserted else { continue }
                encontradas.append((url, carpeta == "/Applications"))
            }
        }
        // Apps que viven fuera de Aplicaciones (en el Escritorio, en Descargas…) también cuentan.
        for ruta in appsExtra where vistas.insert(ruta).inserted {
            encontradas.append((URL(fileURLWithPath: ruta), false))
        }

        // Cada app se lee en paralelo: su Info.plist, lo que lleva dentro y su firma.
        final class Caja: @unchecked Sendable {
            let candado = NSLock()
            var datos: [Int: DatosApp] = [:]
        }
        let caja = Caja()
        let lista = encontradas
        DispatchQueue.concurrentPerform(iterations: lista.count) { i in
            let d = DatosApp.leer(lista[i].url)
            caja.candado.lock()
            caja.datos[i] = d
            caja.candado.unlock()
        }
        for i in lista.indices {
            if let d = caja.datos[i] { r.agregar(d, enAplicaciones: lista[i].enAplicaciones) }
        }

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

    mutating func agregar(_ d: DatosApp, enAplicaciones: Bool) {
        agregarNombre(d.visible)
        if let id = d.principal {
            agregarBundleID(id, nombre: d.visible)
            if enAplicaciones {
                idsEnAplicaciones.insert(id)
                if let v = d.version, versionEnAplicaciones[id] == nil { versionEnAplicaciones[id] = v }
            }
        }
        for n in d.nombres {
            let k = Self.normalizar(n)
            guard !k.isEmpty else { continue }
            nombres.insert(k)
            if nombrePorNombre[k] == nil { nombrePorNombre[k] = d.visible }
        }
        if let v = d.version {
            for k in ([d.visible] + d.nombres).map(Self.normalizar) where !k.isEmpty && versionPorNombre[k] == nil {
                versionPorNombre[k] = v
            }
        }
        for id in d.embebidos {
            bundleIDs.insert(id)
            if nombrePorID[id] == nil { nombrePorID[id] = d.visible }
        }
        extensionesSafari.formUnion(d.extensionesSafari)
        for e in d.equipos {
            equipos.insert(e)
            if nombrePorEquipo[e] == nil { nombrePorEquipo[e] = d.visible }
        }
        for g in d.grupos {
            grupos.insert(g)
            if nombrePorGrupo[g] == nil { nombrePorGrupo[g] = d.visible }
        }
    }

    mutating func agregarNombre(_ n: String) {
        let k = Self.normalizar(n)
        guard !k.isEmpty else { return }
        nombres.insert(k)
        if nombrePorNombre[k] == nil { nombrePorNombre[k] = n }
    }

    mutating func agregarComando(_ n: String) {
        let k = Self.normalizar(n)
        guard !k.isEmpty else { return }
        comandos.insert(k)
        nombresExactos.insert(k)
    }

    mutating func agregarBundleID(_ id: String, nombre: String?) {
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

    // MARK: Carpetas compartidas

    /// «UBF8T346G9.Office» → («UBF8T346G9», «Office»). Un Team ID son 10 letras mayúsculas y números.
    static func separarEquipo(_ s: String) -> (equipo: String, resto: String)? {
        let partes = s.split(separator: ".", maxSplits: 1)
        guard partes.count == 2, partes[0].count == 10, !partes[1].isEmpty else { return nil }
        let equipo = partes[0]
        guard equipo.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }),
              equipo.contains(where: { $0.isNumber }), equipo.contains(where: { $0.isLetter }) else { return nil }
        return (String(equipo), String(partes[1]))
    }

    /// Quita lo que identifica a una carpeta compartida: «UBF8T346G9.Office» → «Office», «group.com.x.y» → «com.x.y».
    static func sinPrefijoDeGrupo(_ s: String) -> String {
        var r = s
        if let (_, resto) = separarEquipo(r) { r = resto }
        if r.lowercased().hasPrefix("group."), r.count > 6 { r = String(r.dropFirst(6)) }
        return r
    }

    // MARK: Consultas

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
        // Carpetas compartidas: la firma de las apps dice exactamente cuáles usan.
        if grupos.contains(Self.sinExtension(l)) { return true }
        if let (equipo, resto) = Self.separarEquipo(carpeta) {
            // Si sigue instalada alguna app del mismo desarrollador, se respeta.
            return equipos.contains(equipo) || estaInstalado(carpeta: resto)
        }
        if l.hasPrefix("group.") {
            return carpeta.count <= 6 || estaInstalado(carpeta: String(carpeta.dropFirst(6)))
        }
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
    /// Si hay varias candidatas, gana la coincidencia más larga (y siempre la misma).
    func nombreApp(para carpeta: String) -> String? {
        let l = Self.sinExtension(carpeta.lowercased())
        if let n = nombrePorGrupo[l] { return n }
        if let (equipo, resto) = Self.separarEquipo(carpeta) {
            return nombreApp(para: resto) ?? nombrePorEquipo[equipo]
        }
        if l.hasPrefix("group."), carpeta.count > 6 { return nombreApp(para: String(carpeta.dropFirst(6))) }
        if let n = nombrePorID[l] { return n }
        let porID = nombrePorID.filter { l.hasPrefix($0.key + ".") || $0.key.hasPrefix(l + ".") }
        if let mejor = porID.max(by: { ($0.key.count, $1.key) < ($1.key.count, $0.key) }) { return mejor.value }
        let n = Self.normalizar(carpeta)
        if let v = nombrePorNombre[n] { return v }
        if n.count >= 4 {
            let parecidos = nombrePorNombre.filter { $0.key.count >= 4 && ($0.key.hasPrefix(n) || n.hasPrefix($0.key)) }
            if let mejor = parecidos.max(by: { ($0.key.count, $1.key) < ($1.key.count, $0.key) }) { return mejor.value }
        }
        return nil
    }

    private static let sufijosGenericos = ["desktop", "app", "client", "community", "mac", "macos", "osx", "us"]

    /// La app instalada que corresponde al nombre de un instalador: el mismo nombre,
    /// o con un sufijo genérico («dockerdesktop» → Docker, «zoom» → zoom.us). Nunca por un prefijo suelto.
    func appParaInstalador(_ base: String) -> (nombre: String, version: String?)? {
        guard base.count >= 3 else { return nil }
        if let n = nombrePorNombre[base] { return (n, versionPorNombre[base]) }
        guard base.count >= 4 else { return nil }
        for sufijo in Self.sufijosGenericos {
            if base.hasSuffix(sufijo), base.count - sufijo.count >= 3 {
                let k = String(base.dropLast(sufijo.count))
                if let n = nombrePorNombre[k] { return (n, versionPorNombre[k]) }
            }
            let k = base + sufijo
            if let n = nombrePorNombre[k] { return (n, versionPorNombre[k]) }
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
