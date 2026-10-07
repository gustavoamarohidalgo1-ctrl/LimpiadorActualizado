import Foundation

/// Apps de Apple y macOS a nivel de usuario. El análisis general se salta todo lo que empieza por «com.apple.»;
/// aquí van solo las cachés de Apple que se pueden borrar sin romper nada.
extension Catalogo {
    static let apple: [Regla] = [
        Regla("safari-cache", "~/Library/Caches/com.apple.Safari",
              nombre: "Caché de Safari",
              detalle: "Páginas, imágenes y scripts que Safari guarda para cargar más rápido.",
              consecuencia: "Las páginas tardarán un poco más la primera vez. No pierdes historial, marcadores ni contraseñas.")
            .accesoTotal().app("Safari", "com.apple.Safari"),
        Regla("safari-contenedor", "~/Library/Containers/com.apple.Safari/Data/Library/Caches",
              nombre: "Caché de Safari (contenedor)",
              detalle: "Más archivos temporales de Safari y de sus extensiones.",
              consecuencia: "Safari los vuelve a crear. No pierdes historial, marcadores ni contraseñas.")
            .accesoTotal().app("Safari", "com.apple.Safari"),
        Regla("musica-cache", "~/Library/Caches/com.apple.Music",
              nombre: "Caché de Música",
              detalle: "Carátulas y datos temporales de la app Música.",
              consecuencia: "Música los vuelve a descargar. Tus canciones y listas no se tocan.")
            .accesoTotal().app("Música", "com.apple.Music"),
        Regla("mapas-cache", "~/Library/Containers/com.apple.Maps/Data/Library/Caches",
              nombre: "Caché de Mapas",
              detalle: "Mapas e imágenes que Mapas descargó.",
              consecuencia: "Mapas los vuelve a descargar cuando los necesite. Tus lugares guardados no se tocan.")
            .accesoTotal().app("Mapas", "com.apple.Maps"),
        Regla("news-cache", "~/Library/Containers/com.apple.news/Data/Library/Caches",
              nombre: "Caché de News",
              detalle: "Artículos e imágenes que News descargó.",
              consecuencia: "News los vuelve a descargar.")
            .accesoTotal().app("News", "com.apple.news"),
        Regla("tv-cache", "~/Library/Containers/com.apple.TV/Data/Library/Caches",
              nombre: "Caché de la app TV",
              detalle: "Imágenes y datos temporales de la app TV.",
              consecuencia: "TV los vuelve a descargar. Las películas y series descargadas no se tocan.")
            .accesoTotal().app("TV", "com.apple.TV"),
        Regla("ayuda-cache", "~/Library/Caches/com.apple.helpd",
              nombre: "Caché de la Ayuda de macOS",
              detalle: "Páginas de ayuda de las apps que macOS guardó.",
              consecuencia: "Nada: se vuelven a cargar al abrir la ayuda."),
        Regla("metal-shaders", "$CACHES/com.apple.metal",
              nombre: "Shaders de Metal",
              detalle: "Programas gráficos que macOS compila para cada app y juego (Metal).",
              consecuencia: "Cada app los vuelve a compilar la próxima vez que la abras (los juegos pueden tardar un poco más en arrancar).")
            .en(.temporales).sinArchivosAbiertos(),
        Regla("contenedores-temporales", "~/Library/Containers/*/Data/tmp",
              nombre: "Temporales de apps de la App Store",
              detalle: "Archivos temporales que las apps con sandbox (como las de la App Store) dejaron en su carpeta privada.",
              consecuencia: "Nada: ninguna app los tiene abiertos y llevan días sin usarse.")
            .en(.temporales).hijos().edad(dias: 3).sinArchivosAbiertos().accesoTotal().excepto("com.apple.*"),
        Regla("grupos-caches", "~/Library/Group Containers/*/Library/Caches",
              nombre: "Cachés compartidas de apps",
              detalle: "Cachés que algunas apps guardan en su carpeta compartida (Group Containers).",
              consecuencia: "Cada app las vuelve a crear cuando las necesita. Tus datos no se tocan.")
            .sinPreseleccion().sinArchivosAbiertos().accesoTotal().excepto("group.com.apple.*", "*.com.apple.*", "com.apple.*"),
    ]
}
