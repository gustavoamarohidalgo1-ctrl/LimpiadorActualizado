import Foundation

/// Las reglas de cada área del barrido (un archivo Catalogo+<Área>.swift por área).
extension Catalogo {
    static let porAreas: [Regla] = [navegadores, comunicacion, appleUsuario, sistemaAdmin, herramientasDev, iaDatos, creatividad, juegos].flatMap { $0 }
}
