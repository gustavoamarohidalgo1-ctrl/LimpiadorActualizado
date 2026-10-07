import Foundation

// Reglas del área «macos-usuario-oculto»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// macos-usuario-oculto
extension Catalogo {
    static let macosUsuarioOculto: [Regla] = [
        Regla("nsird-temporal", "$TEMPORAL/TemporaryItems/NSIRD_*",
              nombre: "Guardados a medias que quedaron olvidados",
              detalle: "Carpetas que las apps usan un momento al guardar un archivo y que se quedan si la app se cierra de golpe. A veces guardan copias enteras de lo que estabas guardando (hay casos de más de 15 GB).",
              consecuencia: "Normalmente nada: llevan más de 3 días sin cambios y ninguna app las tiene abiertas. Si alguna app se cerró sola mientras guardabas, comprueba antes que tu archivo se guardó bien.")
            .en(.temporales).revisar().edad(dias: 3).sinArchivosAbiertos(),
        Regla("nsird-caches-usuario", "~/Library/Caches/TemporaryItems/NSIRD_*",
              nombre: "Guardados a medias olvidados (en Cachés)",
              detalle: "Las mismas carpetas de guardado temporal, pero en la carpeta de cachés de tu usuario. Pueden guardar copias enteras de archivos grandes.",
              consecuencia: "Normalmente nada: llevan más de 3 días sin cambios y ninguna app las tiene abiertas. Si alguna app se cerró sola mientras guardabas, comprueba antes que tu archivo se guardó bien.")
            .en(.temporales).revisar().edad(dias: 3).sinArchivosAbiertos(),
        Regla("aerial-usuario-videos", "~/Library/Application Support/com.apple.wallpaper/aerials/videos",
              nombre: "Vídeos Aerial que ya no usas",
              detalle: "Vídeos de paisajes que macOS descargó para tu fondo de pantalla o tu salvapantallas. Cada uno ocupa entre unos 400 MB y más de 1 GB. El que tienes puesto no se toca.",
              consecuencia: "Si vuelves a elegir alguno de estos fondos, macOS lo descargará otra vez. Si tienes activado que los Aerial roten o se mezclen, también los volverá a descargar.")
            .revisar().archivos("mov").edad(dias: 7).sinArchivosAbiertos(),
    ]
}
