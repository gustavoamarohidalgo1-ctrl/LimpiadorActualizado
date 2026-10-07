import Foundation

/// Las reglas de cada área del barrido (un archivo Catalogo+<Área>.swift por área).
extension Catalogo {
    static let porAreas: [Regla] = [appleUsuario, sistemaAdmin, creatividad, juegos].flatMap { $0 }
}
