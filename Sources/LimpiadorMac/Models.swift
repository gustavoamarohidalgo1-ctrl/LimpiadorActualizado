import Foundation

/// Qué tan seguro es borrar un elemento.
enum Riesgo: Int, Comparable, Hashable {
    case seguro, revisar, cuidado

    static func < (a: Riesgo, b: Riesgo) -> Bool { a.rawValue < b.rawValue }

    var etiqueta: String {
        switch self {
        case .seguro: return "Seguro"
        case .revisar: return "Revisar"
        case .cuidado: return "Cuidado"
        }
    }

    var explicacion: String {
        switch self {
        case .seguro: return "Se regenera solo o no se necesita. Puedes borrarlo sin problema."
        case .revisar: return "Probablemente no lo necesitas, pero confirma antes de borrarlo."
        case .cuidado: return "Puede contener datos que quieras conservar."
        }
    }
}

/// Categorías en las que el analizador agrupa lo que encuentra.
enum Categoria: String, CaseIterable, Identifiable, Hashable {
    case emuladores
    case desarrollo
    case cachesApps
    case restos
    case proyectos
    case herramientas
    case instaladores
    case grandes
    case duplicados
    case registros
    case papelera

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .emuladores: return "Emuladores"
        case .desarrollo: return "Cachés de desarrollo"
        case .cachesApps: return "Cachés de aplicaciones"
        case .restos: return "Restos de apps borradas"
        case .proyectos: return "Compilaciones"
        case .herramientas: return "Carpetas ocultas"
        case .instaladores: return "Instaladores olvidados"
        case .grandes: return "Archivos grandes"
        case .duplicados: return "Archivos duplicados"
        case .registros: return "Registros y fallos"
        case .papelera: return "Papelera"
        }
    }

    var subtitulo: String {
        switch self {
        case .emuladores:
            return "Emuladores de Android, imágenes del sistema que no usa ningún emulador y simuladores de iOS."
        case .desarrollo:
            return "Cachés de npm, Gradle, Xcode, CocoaPods, pip y otras herramientas. Se vuelven a descargar solas cuando hacen falta."
        case .cachesApps:
            return "Archivos temporales que guardan los navegadores y las apps. Las apps los regeneran al usarse."
        case .restos:
            return "Carpetas de configuración y datos de programas que ya no están instalados en este Mac."
        case .proyectos:
            return "node_modules, build, Pods y similares dentro de tus proyectos. Se regeneran con npm install o al compilar."
        case .herramientas:
            return "Carpetas ocultas en tu carpeta personal (las que empiezan con punto) que creó alguna herramienta."
        case .instaladores:
            return "Archivos .dmg, .pkg e .iso que ya usaste para instalar algo."
        case .grandes:
            return "Archivos de más de 100 MB en tus carpetas personales, con la última vez que se usaron."
        case .duplicados:
            return "Archivos idénticos (mismo contenido byte a byte) guardados en más de un lugar. Siempre se conserva una copia."
        case .registros:
            return "Registros (logs) de apps y reportes de fallos. Solo sirven para diagnosticar errores."
        case .papelera:
            return "Lo que ya enviaste a la Papelera sigue ocupando espacio hasta que la vacías."
        }
    }

    var icono: String {
        switch self {
        case .emuladores: return "iphone.gen3"
        case .desarrollo: return "hammer.fill"
        case .cachesApps: return "square.stack.3d.up.fill"
        case .restos: return "puzzlepiece.extension.fill"
        case .proyectos: return "shippingbox.fill"
        case .herramientas: return "eye.slash.fill"
        case .instaladores: return "opticaldiscdrive.fill"
        case .grandes: return "doc.fill"
        case .duplicados: return "doc.on.doc.fill"
        case .registros: return "list.bullet.rectangle.fill"
        case .papelera: return "trash.fill"
        }
    }
}

/// Qué hacer con un elemento al limpiarlo.
enum AccionLimpieza: Hashable {
    /// Borra las rutas del elemento (a la Papelera o definitivamente).
    case borrar
    /// Elimina un simulador de iOS con `xcrun simctl delete`.
    case eliminarSimulador(udid: String)
    /// Borra el contenido de un simulador de iOS, sin eliminar el dispositivo.
    case vaciarSimulador(udid: String)
    /// Vacía la Papelera del usuario.
    case vaciarPapelera
}

struct Elemento: Identifiable, Hashable {
    let id = UUID()
    var nombre: String
    var detalle: String
    var rutas: [URL]
    var tamano: Int64 = 0
    var ultimoUso: Date?
    var categoria: Categoria
    var riesgo: Riesgo
    var seleccionado: Bool = false
    var accion: AccionLimpieza = .borrar

    var rutaPrincipal: URL { rutas[0] }

    var diasSinUso: Int? {
        guard let ultimoUso else { return nil }
        return Calendar.current.dateComponents([.day], from: ultimoUso, to: Date()).day
    }
}

struct InfoDisco {
    var total: Int64
    var libre: Int64

    var usado: Int64 { total - libre }
    var fraccionUsada: Double { total > 0 ? Double(usado) / Double(total) : 0 }

    static func actual() -> InfoDisco {
        let url = URL(fileURLWithPath: "/")
        let claves: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let v = try? url.resourceValues(forKeys: claves)
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        let libre = v?.volumeAvailableCapacityForImportantUsage ?? 0
        return InfoDisco(total: total, libre: libre)
    }
}

struct ResultadoLimpieza {
    var elementosLimpiados: Int
    var bytesLimpiados: Int64
    var libreAntes: Int64
    var libreDespues: Int64
    var errores: [String]
    var modo: ModoLimpieza

    var liberadoReal: Int64 { max(0, libreDespues - libreAntes) }
}

enum ModoLimpieza: String, CaseIterable, Identifiable {
    case papelera
    case definitivo

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .papelera: return "Mover a la Papelera"
        case .definitivo: return "Eliminar definitivamente"
        }
    }

    var descripcion: String {
        switch self {
        case .papelera:
            return "Puedes recuperar lo que borres. El espacio se libera cuando vacías la Papelera."
        case .definitivo:
            return "El espacio se libera al instante, pero no hay forma de deshacerlo."
        }
    }
}

enum Formato {
    static func bytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: b)
    }

    static func haceCuanto(_ fecha: Date?) -> String {
        guard let fecha else { return "Sin fecha" }
        let dias = Calendar.current.dateComponents([.day], from: fecha, to: Date()).day ?? 0
        if dias < 1 { return "Hoy" }
        if dias == 1 { return "Ayer" }
        if dias < 30 { return "Hace \(dias) días" }
        let meses = dias / 30
        if meses < 12 { return meses == 1 ? "Hace 1 mes" : "Hace \(meses) meses" }
        let anios = dias / 365
        return anios == 1 ? "Hace 1 año" : "Hace \(anios) años"
    }

    static func rutaCorta(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = url.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}
