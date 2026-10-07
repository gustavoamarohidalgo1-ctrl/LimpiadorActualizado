import Foundation

// Reglas del área «dev-proyectos»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// Cachés globales ligadas a proyectos y herramientas de compilación.
extension Catalogo {
    static let proyectosDev: [Regla] = [
        Regla("maestro-resultados", "~/.maestro/tests",
              nombre: "Resultados de pruebas de Maestro",
              detalle: "Registros, capturas de pantalla (también las de takeScreenshot) y vídeos que Maestro guarda cada vez que ejecutas pruebas.",
              consecuencia: "Pierdes los informes y las capturas de pruebas pasadas. Maestro los borra solo a los 14 días. Si usas Maestro para sacar capturas para la tienda, guárdalas antes.")
            .en(.desarrollo).sinPreseleccion().hijos().edad(dias: 3).proceso("Maestro", patron: "maestro"),
        Regla("packer-cache", "~/.cache/packer",
              nombre: "Descargas de Packer",
              detalle: "Imágenes ISO y otros archivos que Packer descargó para crear máquinas virtuales.",
              consecuencia: "Packer los vuelve a descargar la próxima vez que crees una imagen. Pueden ser varios GB.")
            .en(.desarrollo).revisar().proceso("Packer", patron: "packer"),
        Regla("godot-plantillas-antiguas", "~/Library/Application Support/Godot/export_templates/*",
              nombre: "Plantillas de exportación de Godot antiguas",
              detalle: "Plantillas para exportar juegos con versiones anteriores de Godot. Se conserva la de la versión más nueva y las de Godot .NET no se tocan.",
              consecuencia: "Si vuelves a exportar con una de esas versiones, Godot te pedirá descargarlas otra vez (cerca de 1 GB cada una). Tus proyectos no se tocan.")
            .en(.desarrollo).revisar().conservando(.versionMasAlta).excepto("*.mono", ".DS_Store").soloSiEstaInstalada().app("Godot", "org.godotengine.godot"),
    ]
}
