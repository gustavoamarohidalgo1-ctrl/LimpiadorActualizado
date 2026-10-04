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

    var veredicto: String {
        switch self {
        case .seguro: return "Puedes borrarlo"
        case .revisar: return "Revísalo antes de borrar"
        case .cuidado: return "No lo borres sin revisar"
        }
    }

    var explicacion: String {
        switch self {
        case .seguro: return "Se regenera solo o no se necesita. Puedes borrarlo sin problema."
        case .revisar: return "Probablemente no lo necesitas, pero confirma antes de borrarlo."
        case .cuidado: return "Puede contener datos que quieras conservar."
        }
    }

    var icono: String {
        switch self {
        case .seguro: return "checkmark.shield.fill"
        case .revisar: return "exclamationmark.triangle.fill"
        case .cuidado: return "xmark.octagon.fill"
        }
    }
}

/// Qué tan grave es cada razón que da el analizador.
enum NivelMotivo: Int, Comparable, Hashable {
    case bien, info, aviso, peligro

    static func < (a: NivelMotivo, b: NivelMotivo) -> Bool { a.rawValue < b.rawValue }
}

/// Una razón concreta de por qué algo es (o no) seguro de borrar.
struct Motivo: Hashable {
    var nivel: NivelMotivo
    var icono: String
    /// Versión corta para la fila de la lista.
    var etiqueta: String
    /// Explicación completa para el panel de detalle.
    var texto: String

    static func bien(_ icono: String, _ etiqueta: String, _ texto: String) -> Motivo {
        Motivo(nivel: .bien, icono: icono, etiqueta: etiqueta, texto: texto)
    }

    static func info(_ icono: String, _ etiqueta: String, _ texto: String) -> Motivo {
        Motivo(nivel: .info, icono: icono, etiqueta: etiqueta, texto: texto)
    }

    static func aviso(_ icono: String, _ etiqueta: String, _ texto: String) -> Motivo {
        Motivo(nivel: .aviso, icono: icono, etiqueta: etiqueta, texto: texto)
    }

    static func peligro(_ icono: String, _ etiqueta: String, _ texto: String) -> Motivo {
        Motivo(nivel: .peligro, icono: icono, etiqueta: etiqueta, texto: texto)
    }
}

/// Lo que hay dentro de una carpeta, contado mientras se indexa el disco.
struct Contenido: Hashable {
    var documentos: Int32 = 0
    var fotos: Int32 = 0
    var videos: Int32 = 0
    var audio: Int32 = 0
    var codigo: Int32 = 0
    var bases: Int32 = 0
    var bibliotecas: Int32 = 0

    mutating func sumar(_ o: Contenido) {
        documentos += o.documentos
        fotos += o.fotos
        videos += o.videos
        audio += o.audio
        codigo += o.codigo
        bases += o.bases
        bibliotecas += o.bibliotecas
    }

    /// Hay suficientes archivos personales como para avisar.
    var esPersonal: Bool {
        documentos > 0 || fotos >= 10 || videos >= 3 || audio >= 5 || bibliotecas > 0
    }

    var resumenPersonal: String {
        var partes: [String] = []
        if bibliotecas > 0 { partes.append(bibliotecas == 1 ? "una biblioteca de fotos o vídeo" : "\(bibliotecas) bibliotecas de fotos o vídeo") }
        if documentos > 0 { partes.append(documentos == 1 ? "1 documento" : "\(documentos) documentos") }
        if fotos > 0 { partes.append(fotos == 1 ? "1 foto" : "\(fotos) fotos") }
        if videos > 0 { partes.append(videos == 1 ? "1 vídeo" : "\(videos) vídeos") }
        if audio > 0 { partes.append(audio == 1 ? "1 audio" : "\(audio) audios") }
        return Formato.lista(partes)
    }

    var vacio: Bool { self == Contenido() }
}

/// Algo que puede estar usando un elemento en este momento.
enum EnUso: Hashable {
    /// Una app o servicio. `claves` son identificadores (com.empresa.app) o nombres.
    case app(nombre: String, claves: [String])
    case emulador(avd: String)
    case simulador(udid: String)
    case gradle
    /// Un programa de terminal: se busca `patron` en la lista de procesos.
    case proceso(nombre: String, patron: String)

    var descripcion: String {
        switch self {
        case .app(let nombre, _): return nombre
        case .emulador(let avd): return "El emulador \(avd.replacingOccurrences(of: "_", with: " "))"
        case .simulador: return "El simulador"
        case .gradle: return "Gradle (Android Studio)"
        case .proceso(let nombre, _): return nombre
        }
    }
}

/// Categorías en las que el analizador agrupa lo que encuentra.
enum Categoria: String, CaseIterable, Identifiable, Hashable {
    case emuladores
    case desarrollo
    case cachesApps
    case temporales
    case sistema
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
        case .temporales: return "Temporales del sistema"
        case .sistema: return "Basura del sistema"
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
            return "Emuladores de Android, sus datos internos, imágenes del sistema y sistemas iOS para simuladores."
        case .desarrollo:
            return "Cachés de Gradle, npm, Xcode y otras herramientas, separadas por versión y según lo que usan tus proyectos."
        case .cachesApps:
            return "Archivos temporales de navegadores y apps, incluidas las cachés internas que guardan junto a sus datos."
        case .temporales:
            return "Temporales y cachés que macOS guarda para tu usuario fuera de tu carpeta (/var/folders). Solo lo que ningún programa tiene abierto."
        case .sistema:
            return "Cachés, registros y descargas de macOS y de apps fuera de tu carpeta. Para borrarlos te pediré la contraseña de administrador."
        case .restos:
            return "Lo que dejaron las apps que ya no están instaladas, agrupado por app: datos, cachés, registros y agentes de inicio."
        case .proyectos:
            return "Carpetas regenerables de tus proyectos (build, node_modules…), agrupadas por proyecto. Tu código no se toca."
        case .herramientas:
            return "Carpetas ocultas de tu carpeta personal, separando sus cachés de su historial y configuración."
        case .instaladores:
            return "Instaladores (.dmg, .pkg, .apk…) y copias sueltas de apps. Te digo si la app ya está instalada."
        case .grandes:
            return "Archivos de más de 100 MB en tus carpetas y los más pesados que hay escondidos en Library."
        case .duplicados:
            return "Archivos idénticos byte a byte. Siempre se conserva una copia, y se descartan los clones que no ocupan espacio extra."
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
        case .temporales: return "gearshape.2.fill"
        case .sistema: return "lock.shield.fill"
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
    /// Elimina un sistema iOS para simuladores con `xcrun simctl runtime delete`.
    case eliminarRuntime(id: String)
    /// Vacía la Papelera del usuario.
    case vaciarPapelera
    /// Borra rutas del sistema (de root) con la contraseña de administrador. No pasa por la Papelera.
    case borrarComoAdmin

    /// Solo borrar rutas pasa por la Papelera. Vaciar un simulador, eliminar un sistema iOS
    /// o vaciar la Papelera no se puede deshacer, elijas el modo que elijas.
    var sePuedeDeshacer: Bool { self == .borrar }

    var descripcionIrreversible: String {
        switch self {
        case .borrar: return "se borra"
        case .eliminarSimulador: return "se elimina el simulador"
        case .vaciarSimulador: return "se borra el contenido del simulador"
        case .eliminarRuntime: return "se elimina el sistema iOS"
        case .vaciarPapelera: return "se vacía la Papelera"
        case .borrarComoAdmin: return "se borra con la contraseña de administrador"
        }
    }
}

struct Elemento: Identifiable, Hashable {
    let id = UUID()
    var nombre: String
    /// Qué es.
    var detalle: String
    /// Qué pasa si lo borras.
    var consecuencia: String
    var rutas: [URL]
    var tamanosRutas: [Int64] = []
    var tamano: Int64 = 0
    /// Tamaño que no sale de las rutas (por ejemplo, un sistema iOS que gestiona Xcode).
    var tamanoFijo: Int64? = nil
    var ultimoUso: Date? = nil
    var categoria: Categoria
    var riesgo: Riesgo
    var seleccionado: Bool = false
    /// Lo que recomendó el análisis (para «Seleccionar lo recomendado»).
    var recomendado = false
    var accion: AccionLimpieza = .borrar
    var motivos: [Motivo] = []
    var enUso: EnUso? = nil
    /// Durante el análisis se comprobó que algo lo está usando.
    var abiertoAhora = false
    /// App o herramienta a la que pertenece.
    var dueno: String? = nil
    /// Disco montado que hay que expulsar antes de borrar (instaladores abiertos).
    var imagenMontada: String? = nil
    var contenido = Contenido()
    /// Duplicados: la copia que se conserva. Si también se va a borrar (o ya no existe), esta no se toca.
    var conservar: String? = nil
    /// Se ofrece aunque ocupe menos de 1 MB (restos que molestan aunque pesen poco).
    var sinMinimo = false

    var rutaPrincipal: URL { rutas[0] }

    var diasSinUso: Int? {
        guard let ultimoUso else { return nil }
        return Calendar.current.dateComponents([.day], from: ultimoUso, to: Date()).day
    }

    /// Solo los motivos que piden atención, del más grave al más leve.
    var avisos: [Motivo] { motivos.filter { $0.nivel >= .aviso } }
}

struct InfoDisco {
    var total: Int64
    /// Libre contando lo «purgable» (lo que macOS borra solo cuando necesita espacio).
    var libre: Int64
    /// Libre ahora mismo, sin contar lo purgable.
    var libreInmediato: Int64 = 0
    var nombre = "Macintosh HD"

    var usado: Int64 { total - libre }
    var fraccionUsada: Double { total > 0 ? Double(usado) / Double(total) : 0 }
    /// Instantáneas locales de Time Machine, cachés de iCloud… macOS las libera solo.
    var purgable: Int64 { max(0, libre - libreInmediato) }

    static func actual() -> InfoDisco {
        let url = URL(fileURLWithPath: "/")
        let claves: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                           .volumeAvailableCapacityKey, .volumeLocalizedNameKey]
        let v = try? url.resourceValues(forKeys: claves)
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        let libre = v?.volumeAvailableCapacityForImportantUsage ?? 0
        var d = InfoDisco(total: total, libre: libre)
        d.libreInmediato = Int64(v?.volumeAvailableCapacity ?? 0)
        if let n = v?.volumeLocalizedName, !n.isEmpty { d.nombre = n }
        return d
    }
}

/// El Mac en el que se ejecuta la app (para el encabezado).
struct InfoMac: Sendable {
    var modelo = "Mac"
    var chip = ""
    var memoria: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    /// Instantáneas locales de Time Machine en el disco de arranque.
    var instantaneas = 0

    var descripcion: String {
        var partes = [modelo]
        if !chip.isEmpty { partes.append(chip) }
        partes.append("\(memoria / 1_073_741_824) GB de memoria")
        return partes.joined(separator: " · ")
    }

    /// Tarda alrededor de un segundo: se llama fuera del hilo principal.
    static func actual() -> InfoMac {
        var m = InfoMac()
        if let modelo = sysctl("hw.model") { m.modelo = modelo }
        if let chip = sysctl("machdep.cpu.brand_string") { m.chip = chip }
        // El nombre comercial («MacBook Air») solo lo da system_profiler.
        let json = Shell.ejecutar("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"], limite: 20).salida
        if let d = json.data(using: .utf8),
           let raiz = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let hw = (raiz["SPHardwareDataType"] as? [[String: Any]])?.first {
            if let n = hw["machine_name"] as? String, !n.isEmpty { m.modelo = n }
            if let c = hw["chip_type"] as? String, !c.isEmpty { m.chip = c }
        }
        let tm = Shell.ejecutar("/usr/bin/tmutil", ["listlocalsnapshots", "/"], limite: 15).salida
        m.instantaneas = tm.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
        return m
    }

    private static func sysctl(_ nombre: String) -> String? {
        var tam = 0
        guard sysctlbyname(nombre, nil, &tam, nil, 0) == 0, tam > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: tam)
        guard sysctlbyname(nombre, &buffer, &tam, nil, 0) == 0 else { return nil }
        let r = String(cString: buffer)
        return r.isEmpty ? nil : r
    }
}

struct ResultadoLimpieza: Identifiable {
    let id = UUID()
    var elementosLimpiados: Int
    var bytesLimpiados: Int64
    var libreAntes: Int64
    var libreDespues: Int64
    var errores: [String]
    var modo: ModoLimpieza
    /// Elementos que no se tocaron porque algo los estaba usando.
    var omitidos: [String] = []
    /// Elementos que iban a eliminarse definitivamente pero se enviaron a la Papelera por seguridad.
    var forzadosAPapelera = 0
    /// Cuántas cosas se pueden devolver a su sitio con «Deshacer».
    var restaurables = 0
    /// Elementos que se limpiaron por completo.
    var hechos: Set<UUID> = []

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
            return "Puedes deshacerlo con un clic (salvo vaciar simuladores, sistemas iOS o la Papelera). El espacio se libera cuando vacías la Papelera."
        case .definitivo:
            return "El espacio se libera al instante. Por seguridad, lo marcado como Revisar o Cuidado va igual a la Papelera."
        }
    }
}

enum Formato {
    static func bytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.allowsNonnumericFormatting = false   // «0 KB», no «Zero KB»
        return f.string(fromByteCount: b)
    }

    static func numero(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "es_PE")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func haceCuanto(_ fecha: Date?) -> String {
        guard let fecha else { return "Sin fecha" }
        let segundos = Date().timeIntervalSince(fecha)
        if segundos < 3600 { return "Hace \(max(1, Int(segundos / 60))) min" }
        if segundos < 86400 { return "Hace \(Int(segundos / 3600)) h" }
        let dias = Int(segundos / 86400)
        if dias == 1 { return "Ayer" }
        if dias < 30 { return "Hace \(dias) días" }
        let meses = dias / 30
        if meses < 12 { return meses == 1 ? "Hace 1 mes" : "Hace \(meses) meses" }
        let anios = dias / 365
        return anios == 1 ? "Hace 1 año" : "Hace \(anios) años"
    }

    static func rutaCorta(_ url: URL) -> String { rutaCorta(url.path) }

    static func rutaCorta(_ p: String) -> String {
        let home = Rutas.home.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    /// "a, b y c"
    static func lista(_ partes: [String]) -> String {
        switch partes.count {
        case 0: return ""
        case 1: return partes[0]
        default: return partes.dropLast().joined(separator: ", ") + " y " + partes.last!
        }
    }

    /// "a, b, c y 4 más"
    static func listaCorta(_ partes: [String], maximo: Int = 3) -> String {
        guard partes.count > maximo else { return lista(partes) }
        return partes.prefix(maximo).joined(separator: ", ") + " y \(partes.count - maximo) más"
    }
}
