import Foundation

// Reglas del área «nube-descargas»: cada ruta y su riesgo se comprobaron por separado antes de añadirla.

/// Nube, sincronización, descargas y copias de seguridad.
extension Catalogo {
    static let nubeDescargas: [Regla] = [
        Regla("dropbox-cache-clasica", "~/Dropbox*/.dropbox.cache",
              nombre: "Caché de Dropbox",
              detalle: "Copias temporales que Dropbox guarda en la carpeta oculta .dropbox.cache de tu Dropbox (archivos que borraste o cambiaste hace poco).",
              consecuencia: "Nada: tus archivos de Dropbox no se tocan. Dropbox vacía esta carpeta por su cuenta cada 3 días; esto solo lo adelanta.")
            .hijos().edad(dias: 1).app("Dropbox", "com.getdropbox.dropbox"),
        Regla("dropbox-informes-fallos", "~/Library/Group Containers/com.dropbox.client.crashpad/*",
              nombre: "Informes de fallos de Dropbox",
              detalle: "Informes que Dropbox guarda cuando se cierra de golpe.",
              consecuencia: "Nada: solo sirven para diagnosticar fallos antiguos. Tus archivos no se tocan.")
            .en(.registros).accesoTotal().excepto(".*", "settings.dat").soloSiEstaInstalada().app("Dropbox", "com.getdropbox.dropbox"),
        Regla("google-drive-miniaturas", "~/Library/Application Support/Google/DriveFS/*/thumbnails_cache",
              nombre: "Miniaturas de Google Drive",
              detalle: "Vistas previas de tus archivos de Drive.",
              consecuencia: "Drive las vuelve a crear cuando las necesita. Tus archivos no se tocan.")
            .hijos().soloSiEstaInstalada().app("Google Drive", "com.google.drivefs"),
        Regla("edge-actualizador-descargas", "~/Library/Application Support/Microsoft/EdgeUpdater/crx_cache",
              nombre: "Actualizaciones descargadas de Microsoft Edge",
              detalle: "El último paquete de actualización de Edge que descargó su actualizador.",
              consecuencia: "Nada: Edge ya está actualizado. La próxima actualización se descargará completa.")
            .en(.instaladores).proceso("Actualizador de Edge", patron: "EdgeUpdater"),
        Regla("edge-actualizador-descargas-sistema", "/Library/Application Support/Microsoft/EdgeUpdater/crx_cache",
              nombre: "Actualizaciones descargadas de Edge (para todo el Mac)",
              detalle: "El último paquete de actualización de Edge instalado para todos los usuarios.",
              consecuencia: "Nada: Edge ya está actualizado. La próxima actualización se descargará completa.")
            .admin().sinPreseleccion().proceso("Actualizador de Edge", patron: "EdgeUpdater"),
        Regla("squirrel-actualizaciones-antiguas", "~/Library/Application Support/*.ShipIt",
              nombre: "Actualizaciones viejas de apps (Squirrel)",
              detalle: "Carpetas de actualización que dejaron versiones antiguas de apps como GitHub Desktop, GitKraken o Discord.",
              consecuencia: "Nada: las versiones actuales de esas apps guardan sus actualizaciones en otro sitio. Si alguna tenía una actualización a medias, la vuelve a descargar.")
            .en(.instaladores).edad(dias: 7).proceso("Actualizador ShipIt", patron: "ShipIt"),
        Regla("google-keystone-cache-sistema", "/Library/Caches/com.google.SoftwareUpdate.*",
              nombre: "Caché del actualizador antiguo de Google",
              detalle: "Archivos temporales de Google Software Update (Keystone), el actualizador antiguo de Chrome.",
              consecuencia: "Nada: se vuelve a crear si hace falta.")
            .admin().sinPreseleccion().edad(dias: 7).proceso("Google Software Update", patron: "GoogleSoftwareUpdate"),
        Regla("mega-papelera-local", "~/MEGA*/.debris/*-*-*",
              nombre: "Papelera local de MEGA",
              detalle: "Archivos que MEGA apartó en la carpeta oculta .debris porque se borraron o cambiaron en la nube.",
              consecuencia: "Se borran solo esas copias apartadas; tus archivos sincronizados no se tocan. Si alguno te hacía falta, quizá siga en la papelera de tu cuenta MEGA.")
            .en(.temporales).revisar().edad(dias: 14).excepto("tmp").app("MEGA", "mega.mac"),
        Regla("onedrive-registros-appstore", "~/Library/Containers/com.microsoft.OneDrive-mac/Data/Library/Logs",
              nombre: "Registros de OneDrive (App Store)",
              detalle: "Registros de la versión de OneDrive de la App Store de hace más de una semana.",
              consecuencia: "Nada: solo son registros. Tus archivos y la sincronización no se tocan.")
            .en(.registros).archivos("odl", "odlgz", "odlsent", "log").edad(dias: 7).accesoTotal().excepto("ListSync", "ObfuscationStringMap.txt").soloSiEstaInstalada().app("OneDrive", "com.microsoft.OneDrive-mac"),
        Regla("onedrive-registros-sistema", "/Library/Logs/Microsoft/OneDrive",
              nombre: "Registros viejos de OneDrive (sistema)",
              detalle: "Registros del servicio y del actualizador de OneDrive para todo el Mac.",
              consecuencia: "Nada: solo se pierden registros de hace más de dos semanas.")
            .admin().sinPreseleccion().archivos("odl", "odlgz", "odlsent", "log").edad(dias: 14).app("OneDrive", "com.microsoft.OneDrive"),
        Regla("backblaze-registros", "/Library/Backblaze.bzpkg/bzdata/bzlogs",
              nombre: "Registros viejos de Backblaze",
              detalle: "Registros que Backblaze guarda de cada día. A veces llegan a ocupar varios GB.",
              consecuencia: "Nada: tu copia de seguridad no se toca (solo se borran archivos de registro, nunca carpetas).")
            .admin().sinPreseleccion().archivos("log").edad(dias: 2).sinArchivosAbiertos(),
        Regla("borg-cache", "~/.cache/borg",
              nombre: "Caché de BorgBackup",
              detalle: "Índice local de tus repositorios de Borg (sirve para no volver a copiar lo que ya está guardado).",
              consecuencia: "La próxima copia con Borg tardará más mientras la reconstruye leyendo el repositorio. Tus copias no se tocan.")
            .revisar().proceso("BorgBackup", patron: "borg"),
        Regla("apple-configurator-descargas", "~/Library/Group Containers/K36BKF7T3D.group.com.apple.configurator/Library/Caches",
              nombre: "Descargas de Apple Configurator",
              detalle: "Apps de iPhone y iPad (.ipa) y otras descargas que Apple Configurator guardó para instalarlas en tus dispositivos.",
              consecuencia: "Apple Configurator vuelve a descargar lo que necesite. Si guardabas aquí apps que ya no están en la App Store, se perderán. La carpeta Firmware (sistemas IPSW) no se toca.")
            .revisar().hijos().accesoTotal().excepto("Firmware").app("Apple Configurator", "com.apple.configurator.ui"),
        Regla("itunes-bibliotecas-anteriores", "~/Music/iTunes/Previous iTunes Libraries",
              nombre: "Copias viejas de la biblioteca de iTunes",
              detalle: "Copias de la base de datos de iTunes que se guardaron al actualizar iTunes o al pasar a la app Música (se conserva la más reciente).",
              consecuencia: "Nada: tus canciones no se tocan. Solo pierdes la opción de volver a una biblioteca antigua.")
            .en(.grandes).revisar().hijos(conservar: .masReciente).edad(dias: 30).app("Música", "com.apple.Music", "com.apple.iTunes"),
        Regla("torrents-incompletos", "~/Downloads",
              nombre: "Torrents a medio descargar",
              detalle: "Archivos incompletos de qBittorrent (.!qB), µTorrent (.!ut) o BitTorrent (.!bt) que llevan una semana sin avanzar.",
              consecuencia: "Si todavía quieres esos torrents, tendrás que descargarlos de nuevo.")
            .en(.temporales).revisar().archivos("!qb", "!ut", "!bt").edad(dias: 7).sinArchivosAbiertos(),
        Regla("qbittorrent-partes-no-deseadas", "~/Downloads/*/.unwanted",
              nombre: "Partes de torrents que no elegiste",
              detalle: "Trozos de archivos que qBittorrent guarda en la carpeta oculta .unwanted cuando desmarcas archivos de un torrent.",
              consecuencia: "Nada: son trozos de archivos que decidiste no descargar. Si vuelves a marcarlos en qBittorrent, los descargará otra vez.")
            .en(.temporales).revisar().edad(dias: 7).app("qBittorrent", "org.qbittorrent.qBittorrent"),
        Regla("chrome-temporales-descargas", "~/Downloads/.com.google.Chrome.*",
              nombre: "Temporales de Chrome en Descargas",
              detalle: "Archivos ocultos que Chrome crea al guardar o comprobar descargas y que se quedaron tras un cierre inesperado.",
              consecuencia: "Normalmente nada: son copias temporales. Si Chrome se cerró justo al terminar una descarga, puede ser esa descarga: si te falta algo de esos días, descárgalo de nuevo.")
            .en(.temporales).revisar().edad(dias: 7).sinArchivosAbiertos(),
        Regla("chrome-temporales-escritorio", "~/Desktop/.com.google.Chrome.*",
              nombre: "Temporales de Chrome en el Escritorio",
              detalle: "Archivos ocultos que Chrome dejó en el Escritorio tras un cierre inesperado.",
              consecuencia: "Normalmente nada: son copias temporales que Chrome no llegó a renombrar. Si te falta algo que guardaste o arrastraste desde Chrome esos días, puede estar aquí.")
            .en(.temporales).revisar().edad(dias: 7).sinArchivosAbiertos(),
        Regla("contenedores-registros", "~/Library/Containers/*/Data/Library/Logs",
              nombre: "Registros de apps de la App Store",
              detalle: "Registros que las apps con sandbox (como las de la App Store) guardan en su carpeta privada.",
              consecuencia: "Nada: solo son registros para diagnosticar errores. Tus datos no se tocan.")
            .en(.registros).sinPreseleccion().hijos().edad(dias: 7).accesoTotal().sinArchivosAbiertos().excepto("com.apple.*", "group.com.apple.*", "*.com.apple.*", "com.microsoft.OneDrive*", "UBF8T346G9.OneDrive*", "ListSync", "*.com.getdropbox.dropbox.sync", "G69SCX94XU.duck", "*.com.eltima.cloudmounter", "CH86M498V4.com.expandrive"),
        Regla("grupos-registros", "~/Library/Group Containers/*/Library/Logs",
              nombre: "Registros compartidos de apps",
              detalle: "Registros que algunas apps guardan en su carpeta compartida (Group Containers).",
              consecuencia: "Nada: solo son registros para diagnosticar errores. Tus datos no se tocan.")
            .en(.registros).sinPreseleccion().hijos().edad(dias: 7).accesoTotal().sinArchivosAbiertos().excepto("com.apple.*", "group.com.apple.*", "*.com.apple.*", "com.microsoft.OneDrive*", "UBF8T346G9.OneDrive*", "ListSync", "*.com.getdropbox.dropbox.sync", "G69SCX94XU.duck", "*.com.eltima.cloudmounter", "CH86M498V4.com.expandrive"),
    ]
}
