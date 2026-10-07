import Foundation

/// Una regla del catálogo: una ruta conocida que se puede limpiar, con todo lo que hace falta para explicarla.
///
/// Se escribe así (el orden de los modificadores da igual):
///
///     Regla("steam-shaders", "~/Library/Application Support/Steam/steamapps/shadercache/*",
///           nombre: "Shaders de juegos de Steam",
///           detalle: "Shaders precompilados de cada juego.",
///           consecuencia: "Steam los vuelve a compilar la próxima vez que abras el juego.")
///         .en(.cachesApps).app("Steam", "com.valvesoftware.steam")
///
/// En el patrón, `~` es la carpeta personal, `$TEMPORAL` y `$CACHES` las carpetas de tu usuario en /var/folders,
/// y `*` cualquier nombre en ese nivel (también vale `cmake-build-*`).
struct Regla {
    enum Modo: Equatable {
        /// Se ofrece cada ruta que coincide con el patrón.
        case carpeta
        /// Se ofrece cada cosa que hay dentro de cada ruta que coincide.
        case hijos
        /// Se ofrecen los archivos con estas extensiones que hay dentro (hasta 4 niveles).
        case archivos([String])
    }

    enum Conservar: Equatable {
        case nada
        /// En modo hijos: se conserva el que se modificó por última vez.
        case masReciente
        /// En modo hijos: se conserva el de versión más alta («2.10» > «2.9»).
        case versionMasAlta
    }

    let id: String
    let patron: String
    let nombre: String
    let detalle: String
    let consecuencia: String
    private(set) var modo: Modo = .carpeta
    private(set) var conservar: Conservar = .nada
    /// Solo se ofrece lo que lleva al menos estos días sin cambios.
    private(set) var edadMinimaDias = 0
    private(set) var categoria: Categoria = .cachesApps
    private(set) var riesgo: Riesgo = .seguro
    private(set) var preseleccionar = true
    /// Es de root: se borra con la contraseña de administrador y no pasa por la Papelera.
    private(set) var requiereAdmin = false
    private(set) var requiereAccesoTotal = false
    private(set) var app: String?
    private(set) var bundleIDs: [String] = []
    private(set) var proceso: (nombre: String, patron: String)?
    /// Solo si la app sigue instalada (si no, lo que dejó ya sale en «Restos de apps borradas»).
    private(set) var soloSiInstalada = false
    /// Se deja fuera lo que algún programa tiene abierto ahora mismo (según `lsof`).
    private(set) var siNadaLoTieneAbierto = false
    /// Nombres que nunca se ofrecen aunque coincidan con el patrón (por ejemplo, «com.apple.*»).
    private(set) var exclusiones: [String] = []

    init(_ id: String, _ patron: String, nombre: String, detalle: String, consecuencia: String) {
        self.id = id
        self.patron = patron
        self.nombre = nombre
        self.detalle = detalle
        self.consecuencia = consecuencia
    }

    // MARK: Modificadores

    func en(_ c: Categoria) -> Regla { var r = self; r.categoria = c; return r }

    /// Probablemente sobra, pero conviene mirarlo: va a la Papelera y no se marca solo.
    func revisar() -> Regla { var r = self; r.riesgo = .revisar; r.preseleccionar = false; return r }

    /// Puede tener algo importante: el usuario tiene que confirmarlo expresamente.
    func cuidado() -> Regla { var r = self; r.riesgo = .cuidado; r.preseleccionar = false; return r }

    /// Seguro, pero no se marca solo (por ejemplo, porque volver a descargarlo tarda).
    func sinPreseleccion() -> Regla { var r = self; r.preseleccionar = false; return r }

    /// La app dueña: si está abierta, no se toca.
    func app(_ nombre: String, _ ids: String...) -> Regla { var r = self; r.app = nombre; r.bundleIDs = ids; return r }

    /// Un programa de terminal: si su proceso está en marcha, no se toca.
    func proceso(_ nombre: String, patron: String) -> Regla { var r = self; r.proceso = (nombre, patron); return r }

    func soloSiEstaInstalada() -> Regla { var r = self; r.soloSiInstalada = true; return r }

    func hijos(conservar: Conservar = .nada) -> Regla { var r = self; r.modo = .hijos; r.conservar = conservar; return r }

    func archivos(_ extensiones: String...) -> Regla {
        var r = self; r.modo = .archivos(extensiones.map { $0.lowercased() }); return r
    }

    func edad(dias: Int) -> Regla { var r = self; r.edadMinimaDias = dias; return r }

    func admin() -> Regla { var r = self; r.requiereAdmin = true; r.categoria = .sistema; return r }

    func accesoTotal() -> Regla { var r = self; r.requiereAccesoTotal = true; return r }

    /// Para temporales: no ofrecer lo que un programa tenga abierto.
    func sinArchivosAbiertos() -> Regla { var r = self; r.siNadaLoTieneAbierto = true; return r }

    /// En modo carpeta con comodines: conservar una de las coincidencias («discord/0.0.*» → la versión más alta).
    func conservando(_ c: Conservar) -> Regla { var r = self; r.conservar = c; return r }

    /// Deja fuera las rutas en las que alguna carpeta se llama así (admite `*`: «com.apple.*»).
    func excepto(_ nombres: String...) -> Regla { var r = self; r.exclusiones += nombres; return r }
}

/// Una carpeta regenerable dentro de un proyecto (por ejemplo, la «Library» de un proyecto de Unity).
struct ReglaArtefacto {
    /// Nombre de la carpeta. Admite `*` («cmake-build-*»).
    let carpeta: String
    /// Archivos o carpetas que tiene que haber junto a ella (basta uno). Admiten `*` («*.csproj»).
    let marcadores: [String]
    /// Qué es, en pocas palabras: «caché de Unity».
    let descripcion: String
    let consecuencia: String
    var riesgo: Riesgo = .seguro
    /// Nombres ambiguos (dist, out, public…): solo cuentan si git los ignora.
    var soloSiIgnoradaPorGit = false
}

/// Todas las reglas conocidas. Cada área vive en su propio archivo (`Catalogo+Area.swift`).
enum Catalogo {
    static let reglas: [Regla] = [apple, aplicaciones, desarrollo, descargas, sistema, porAreas].flatMap { $0 }
    static let artefactos: [ReglaArtefacto] = artefactosDeProyecto + artefactosExtra
}
