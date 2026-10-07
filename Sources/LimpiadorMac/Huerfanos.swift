import Foundation

/// Restos de apps desinstaladas a nivel de sistema: agentes y demonios de inicio cuyo programa ya no existe
/// y ayudantes privilegiados que ningún demonio usa. Las comprobaciones se repiten justo antes de borrar.
enum Huerfanos {
    static let carpetasAgentes = ["/Library/LaunchDaemons", "/Library/LaunchAgents"]
    static let carpetaAyudantes = "/Library/PrivilegedHelperTools"

    /// La etiqueta y el programa que lanza un plist de launchd. El programa es `nil` si lo gestiona una app
    /// moderna (BundleProgram, SMAppService): entonces depende de la app y no se toca.
    static func programa(de plist: URL) -> (etiqueta: String, programa: String?)? {
        guard let d = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
        let etiqueta = d["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
        if d["BundleProgram"] != nil { return (etiqueta, nil) }
        let programa = (d["Program"] as? String) ?? (d["ProgramArguments"] as? [String])?.first
        return (etiqueta, programa)
    }

    /// ¿Es un plist de launchd del sistema (no de Apple) cuyo programa ya no existe?
    static func esAgenteHuerfano(_ ruta: String) -> Bool {
        let url = URL(fileURLWithPath: ruta)
        guard carpetasAgentes.contains(url.deletingLastPathComponent().path), url.pathExtension == "plist",
              !url.lastPathComponent.hasPrefix("com.apple."),
              let info = programa(de: url), let p = info.programa, p.hasPrefix("/"),
              !p.hasPrefix("/System/"), !p.hasPrefix("/usr/") else { return false }
        return !Rutas.existeSinSeguir(p)
    }

    /// ¿Es un ayudante de /Library/PrivilegedHelperTools que ningún demonio ni agente usa?
    static func esAyudanteHuerfano(_ ruta: String) -> Bool {
        let url = URL(fileURLWithPath: ruta)
        guard url.deletingLastPathComponent().path == carpetaAyudantes,
              !url.lastPathComponent.hasPrefix("com.apple.") else { return false }
        let nombre = url.lastPathComponent
        for carpeta in carpetasAgentes {
            for plist in Rutas.hijos(URL(fileURLWithPath: carpeta)) where plist.pathExtension == "plist" {
                if plist.deletingPathExtension().lastPathComponent == nombre { return false }
                guard let info = programa(de: plist) else { continue }
                if info.etiqueta == nombre || info.programa == ruta { return false }
            }
        }
        return true
    }

    static func agentes() -> [URL] {
        carpetasAgentes.flatMap { Rutas.hijos(URL(fileURLWithPath: $0)) }.filter { esAgenteHuerfano($0.path) }
    }

    static func ayudantes() -> [URL] {
        Rutas.hijos(URL(fileURLWithPath: carpetaAyudantes)).filter { esAyudanteHuerfano($0.path) }
    }
}

/// Los vídeos Aerial que tienes puestos de fondo de pantalla o de salvapantallas (por su identificador).
enum FondosEnUso {
    /// `nil` si no se puede saber: entonces no se ofrece ningún vídeo.
    static func identificadores() -> Set<String>? {
        let indice = Rutas.enHome("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let datos = try? Data(contentsOf: indice),
              let raiz = try? PropertyListSerialization.propertyList(from: datos, format: nil) else { return nil }
        var r = Set<String>()
        recoger(raiz, en: &r, nivel: 0)
        let byHost = Rutas.enHome("Library/Preferences/ByHost")
        for u in Rutas.hijos(byHost) where u.lastPathComponent.hasPrefix("com.apple.screensaver.") && u.pathExtension == "plist" {
            if let d = try? Data(contentsOf: u), let p = try? PropertyListSerialization.propertyList(from: d, format: nil) {
                recoger(p, en: &r, nivel: 0)
            }
        }
        return r
    }

    private static let patronUUID = try? NSRegularExpression(
        pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    /// Todos los UUID que aparecen en el plist, también dentro de plists guardados como datos.
    static func recoger(_ valor: Any, en r: inout Set<String>, nivel: Int) {
        guard nivel < 32 else { return }
        switch valor {
        case let d as [String: Any]:
            for (k, v) in d {
                buscar(k, en: &r)
                recoger(v, en: &r, nivel: nivel + 1)
            }
        case let a as [Any]:
            for v in a { recoger(v, en: &r, nivel: nivel + 1) }
        case let s as String:
            buscar(s, en: &r)
        case let d as Data:
            if let p = try? PropertyListSerialization.propertyList(from: d, format: nil) {
                recoger(p, en: &r, nivel: nivel + 1)
            } else if let s = String(data: d, encoding: .utf8) {
                buscar(s, en: &r)
            }
        default:
            break
        }
    }

    private static func buscar(_ texto: String, en r: inout Set<String>) {
        guard let patronUUID else { return }
        let rango = NSRange(texto.startIndex..., in: texto)
        for m in patronUUID.matches(in: texto, range: rango) {
            if let rr = Range(m.range, in: texto) { r.insert(texto[rr].uppercased()) }
        }
    }
}
