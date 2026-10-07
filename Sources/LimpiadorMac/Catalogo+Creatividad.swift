import Foundation

// Reglas del área «creatividad»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// Foto, vídeo, audio y diseño: cachés de render, previsualizaciones y bibliotecas descargables.
extension Catalogo {
    static let creatividad: [Regla] = [
        Regla("fcp-proxies", "~/Movies/*.fcpbundle/*/Transcoded Media/Proxy Media",
              nombre: "Archivos proxy de Final Cut Pro",
              detalle: "Copias en baja calidad de tus vídeos que Final Cut crea para editar con fluidez.",
              consecuencia: "Final Cut puede volver a crearlas desde los originales (Archivo › Transcodificar medios). Si esta biblioteca solo tiene proxies (por ejemplo, te la pasaron sin los originales) o los originales están en un disco desconectado, verás «medios no disponibles» hasta que los conectes.")
            .revisar().app("Final Cut Pro", "com.apple.FinalCut"),
        Regla("fcp-optimizados", "~/Movies/*.fcpbundle/*/Transcoded Media/High Quality Media",
              nombre: "Medios optimizados de Final Cut Pro",
              detalle: "Copias en ProRes de tus vídeos que Final Cut crea para que la edición vaya más fluida (suelen ocupar mucho).",
              consecuencia: "Final Cut usará los originales y puede volver a crearlas (Archivo › Transcodificar medios). Si los originales ya no existen (venían de una tarjeta que borraste o de un disco que ya no tienes), perderás esos vídeos para siempre.")
            .cuidado().app("Final Cut Pro", "com.apple.FinalCut"),
        Regla("fcp-copias-seguridad", "~/Movies/Final Cut*Backups*/*",
              nombre: "Copias de seguridad antiguas de bibliotecas de Final Cut",
              detalle: "Copias automáticas de la base de datos de cada biblioteca (no incluyen vídeos).",
              consecuencia: "Se conserva la copia más reciente de cada biblioteca; ya no podrás volver a versiones más antiguas de tus proyectos. Si ya borraste la biblioteca, la copia que se conserva es lo único que queda de ella.")
            .en(.grandes).revisar().hijos(conservar: .masReciente).edad(dias: 30).excepto(".localized").app("Final Cut Pro", "com.apple.FinalCut"),
        Regla("motion-cache", "~/Library/Caches/com.apple.motionapp",
              nombre: "Caché de Motion",
              detalle: "Datos temporales de Motion.",
              consecuencia: "Motion la vuelve a crear al abrirse. Tus proyectos no se tocan.")
            .soloSiEstaInstalada().app("Motion", "com.apple.motionapp", "com.apple.Motion"),
        Regla("compressor-cache", "~/Library/Caches/com.apple.Compressor",
              nombre: "Caché de Compressor",
              detalle: "Datos temporales de Compressor.",
              consecuencia: "Compressor la vuelve a crear al abrirse. Tus vídeos no se tocan.")
            .soloSiEstaInstalada().app("Compressor", "com.apple.Compressor"),
        Regla("logic-cache", "~/Library/Caches/com.apple.logic10",
              nombre: "Caché de Logic Pro",
              detalle: "Datos temporales de Logic Pro.",
              consecuencia: "Logic la vuelve a crear al abrirse y volverá a comprobar tus plugins (Audio Units), lo que puede tardar unos minutos. Tus proyectos y sonidos no se tocan.")
            .sinPreseleccion().soloSiEstaInstalada().app("Logic Pro", "com.apple.logic10"),
        Regla("garageband-lecciones", "/Library/Application Support/GarageBand/Learn to Play/Basic Lessons/*",
              nombre: "Lecciones descargadas de GarageBand",
              detalle: "Lecciones de piano y guitarra (vídeo) que GarageBand descargó; cada una ocupa cientos de MB.",
              consecuencia: "Si vuelves a abrir una de esas lecciones, GarageBand la descarga otra vez. Las dos lecciones básicas que trae GarageBand no se tocan. Se borran sin pasar por la Papelera.")
            .admin().cuidado().excepto("Piano Lesson 1.mwand", "Guitar Lesson 1.mwand").soloSiEstaInstalada().app("GarageBand", "com.apple.garageband10"),
        Regla("resolve-cacheclip", "~/Movies/CacheClip",
              nombre: "Caché de render de DaVinci Resolve",
              detalle: "Clips que Resolve renderizó para reproducir sin cortes y los medios optimizados que hayas generado.",
              consecuencia: "Resolve vuelve a generar la caché y los medios optimizados cuando hagan falta (la primera reproducción irá más lenta). Si tus vídeos originales están en un disco desconectado, no podrás reproducir esos clips hasta conectarlo. Tus proyectos no se tocan.")
            .revisar().app("DaVinci Resolve", "com.blackmagic-design.DaVinciResolve", "com.blackmagic-design.DaVinciResolveLite"),
        Regla("photoshop-cache-fuentes", "~/Library/Application Support/Adobe/Adobe Photoshop */CT Font Cache",
              nombre: "Caché de fuentes de Photoshop",
              detalle: "Índice de fuentes que Photoshop crea para la herramienta de texto.",
              consecuencia: "Photoshop la vuelve a crear al abrirse (el primer arranque irá algo más lento). Tus documentos y fuentes no se tocan.")
            .soloSiEstaInstalada().app("Adobe Photoshop", "com.adobe.Photoshop"),
        Regla("sketch-cache", "~/Library/Application Support/com.bohemiancoding.sketch3/cache",
              nombre: "Caché interna de Sketch",
              detalle: "Datos temporales que Sketch guarda junto a su configuración.",
              consecuencia: "Sketch la vuelve a crear. Tus documentos y plugins no se tocan. Abre Sketch antes para que sincronice los documentos de tu espacio de trabajo.")
            .sinPreseleccion().soloSiEstaInstalada().app("Sketch", "com.bohemiancoding.sketch3"),
        Regla("blender-descargas-extensiones", "~/Library/Application Support/Blender/*/extensions/*/.blender_ext/cache",
              nombre: "Descargas de extensiones de Blender",
              detalle: "Paquetes .zip de extensiones que Blender descargó para instalarlas.",
              consecuencia: "Nada: las extensiones ya están instaladas; si reinstalas alguna, Blender la vuelve a descargar.")
            .archivos("zip").soloSiEstaInstalada().app("Blender", "org.blenderfoundation.blender"),
        Regla("gimp-cache", "~/Library/Application Support/GIMP/*/cache",
              nombre: "Caché de GIMP",
              detalle: "Datos temporales que GIMP guarda junto a su configuración.",
              consecuencia: "GIMP la vuelve a crear al abrirse. Tus imágenes y ajustes no se tocan.")
            .sinArchivosAbiertos().soloSiEstaInstalada().app("GIMP", "org.gimp.gimp-3.0", "org.gimp.gimp-3.2"),
        Regla("gimp-temporales", "~/Library/Application Support/GIMP/*/tmp",
              nombre: "Temporales de GIMP",
              detalle: "Archivos temporales de GIMP.",
              consecuencia: "Nada: GIMP crea otros cuando los necesita. Tus imágenes no se tocan.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().soloSiEstaInstalada().app("GIMP", "org.gimp.gimp-3.0", "org.gimp.gimp-3.2"),
        Regla("darktable-miniaturas", "~/.cache/darktable/mipmaps-*.d",
              nombre: "Miniaturas de darktable",
              detalle: "Vistas previas de tus fotos que darktable genera para la mesa de luz.",
              consecuencia: "darktable las vuelve a generar al navegar por tus fotos. Tus fotos y ediciones no se tocan.")
            .sinArchivosAbiertos().app("darktable", "org.darktable"),
        Regla("obs-perfilado", "~/Library/Application Support/obs-studio/profiler_data",
              nombre: "Datos de rendimiento de OBS",
              detalle: "Mediciones de rendimiento que OBS guarda en cada sesión.",
              consecuencia: "Nada: solo sirven para diagnosticar problemas de rendimiento. Tus escenas y ajustes no se tocan.")
            .en(.registros).app("OBS", "com.obsproject.obs-studio"),
        Regla("handbrake-registros", "~/Library/Containers/fr.handbrake.HandBrake/Data/Library/Application Support/HandBrake/EncodeLogs",
              nombre: "Registros de conversiones de HandBrake",
              detalle: "Un registro por cada vídeo que convertiste con HandBrake.",
              consecuencia: "Nada: solo se pierden registros antiguos. Tus vídeos convertidos no se tocan.")
            .en(.registros).hijos().edad(dias: 7).accesoTotal().app("HandBrake", "fr.handbrake.HandBrake"),
        Regla("handbrake-registros-antiguo", "~/Library/Application Support/HandBrake/EncodeLogs",
              nombre: "Registros de conversiones de HandBrake (versiones antiguas)",
              detalle: "Registros de conversiones de versiones antiguas de HandBrake.",
              consecuencia: "Nada: solo se pierden registros antiguos. Tus vídeos convertidos no se tocan.")
            .en(.registros).hijos().edad(dias: 7).app("HandBrake", "fr.handbrake.HandBrake"),
        Regla("handbrake-vistas-previas", "~/Library/Containers/fr.handbrake.HandBrake/Data/Library/Application Support/HandBrake/Previews",
              nombre: "Vistas previas de HandBrake",
              detalle: "Vídeos de prueba que HandBrake genera al pulsar «Vista previa».",
              consecuencia: "Nada: HandBrake los borra al abrirse y crea otros cuando hagan falta. Tus vídeos no se tocan.")
            .en(.temporales).edad(dias: 1).accesoTotal().sinArchivosAbiertos().app("HandBrake", "fr.handbrake.HandBrake"),
        Regla("kodi-paquetes", "~/Library/Application Support/Kodi/addons/packages",
              nombre: "Paquetes descargados de complementos de Kodi",
              detalle: "Archivos .zip de los complementos que Kodi descargó para instalarlos o actualizarlos.",
              consecuencia: "Nada: los complementos ya están instalados. Solo pierdes la opción de volver a una versión anterior de un complemento.")
            .en(.instaladores).app("Kodi", "org.xbmc.kodi"),
        Regla("kodi-temporales", "~/.kodi/temp",
              nombre: "Temporales de Kodi",
              detalle: "Archivos temporales de Kodi.",
              consecuencia: "Nada: Kodi crea otros al abrirse. Tu biblioteca y tus ajustes no se tocan.")
            .en(.temporales).edad(dias: 1).sinArchivosAbiertos().app("Kodi", "org.xbmc.kodi"),
        Regla("plex-actualizaciones", "~/Library/Application Support/Plex Media Server/Updates",
              nombre: "Actualizaciones descargadas de Plex Media Server",
              detalle: "Instaladores de actualizaciones que Plex descargó.",
              consecuencia: "Nada: Plex descarga la siguiente cuando haga falta. Tu biblioteca no se toca.")
            .en(.instaladores).edad(dias: 3).app("Plex Media Server", "com.plexapp.plexmediaserver"),
        Regla("plex-informes-fallos", "~/Library/Application Support/Plex Media Server/Crash Reports",
              nombre: "Informes de fallos de Plex Media Server",
              detalle: "Informes que Plex guarda cuando el servidor falla.",
              consecuencia: "Nada: solo sirven para diagnosticar fallos antiguos. Tu biblioteca no se toca.")
            .en(.registros).app("Plex Media Server", "com.plexapp.plexmediaserver"),
        Regla("topaz-video-modelos", "~/Library/Application Support/Topaz Labs LLC/Topaz Video*/models",
              nombre: "Modelos de IA de Topaz Video",
              detalle: "Modelos de inteligencia artificial que Topaz descargó (pueden ocupar decenas de GB).",
              consecuencia: "Topaz vuelve a descargar los que necesite la próxima vez que proceses un vídeo, lo que tarda. Necesitarás internet y que tu licencia siga activa para descargarlos. Tus vídeos no se tocan.")
            .en(.grandes).revisar().app("Topaz Video", "com.topazlabs.Topaz-Video-AI", "com.topazlabs.Topaz-Video"),
    ]
}
