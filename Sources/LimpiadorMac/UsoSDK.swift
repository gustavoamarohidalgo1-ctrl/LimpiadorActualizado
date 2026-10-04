import Foundation

/// Qué partes del SDK de Android usan tus proyectos, leído de sus build.gradle(.kts) y libs.versions.toml.
/// Sirve para saber con exactitud qué plataformas, build-tools y NDK sobran.
struct UsoSDK {
    /// Niveles de API con los que compila algún proyecto (compileSdk).
    var plataformas: Set<Int> = []
    var buildTools: Set<String> = []
    var ndk: Set<String> = []
    /// Algún proyecto elige la plataforma o el NDK con una variable (Flutter, React Native…): no se sabe cuál.
    var plataformaIncierta = false
    var ndkIncierto = false
    /// Cuántos archivos de Gradle se leyeron.
    var archivos = 0

    static func leer(_ rutas: [String]) -> UsoSDK {
        var u = UsoSDK()
        for ruta in rutas {
            guard let texto = try? String(contentsOfFile: ruta, encoding: .utf8) else { continue }
            u.archivos += 1
            u.analizar(texto)
        }
        return u
    }

    mutating func analizar(_ texto: String) {
        for linea in texto.split(separator: "\n") {
            let l = linea.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("//") || l.hasPrefix("#") || l.hasPrefix("*") { continue }
            if l.contains("compileSdk") {
                if let n = Self.captura(Self.reCompile, l).flatMap({ Int($0) }) { plataformas.insert(n) } else { plataformaIncierta = true }
            }
            if l.contains("buildToolsVersion"), let v = Self.captura(Self.reBuildTools, l) { buildTools.insert(v) }
            if l.contains("ndkVersion") {
                if let v = Self.captura(Self.reNDK, l) { ndk.insert(v) } else { ndkIncierto = true }
            }
        }
    }

    /// «android-34» o «android-34-ext10» → 34. Las vistas previas («android-UpsideDownCake») no tienen número.
    static func numeroPlataforma(_ carpeta: String) -> Int? {
        guard carpeta.hasPrefix("android-") else { return nil }
        let digitos = carpeta.dropFirst(8).prefix { $0.isNumber }
        return Int(digitos)
    }

    private static let reCompile = try! NSRegularExpression(pattern: #"\bcompileSdk\w*\s*[=:]?\s*\(?\s*["']?(\d{2,3})\b"#)
    private static let reBuildTools = try! NSRegularExpression(pattern: #"\bbuildToolsVersion\s*[=:]?\s*\(?\s*["']([0-9][0-9.]*)["']"#)
    private static let reNDK = try! NSRegularExpression(pattern: #"\bndkVersion\s*[=:]?\s*\(?\s*["']([0-9][0-9.]*)["']"#)

    private static func captura(_ re: NSRegularExpression, _ s: String) -> String? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
