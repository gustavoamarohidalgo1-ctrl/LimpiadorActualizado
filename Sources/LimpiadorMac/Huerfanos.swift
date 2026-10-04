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
