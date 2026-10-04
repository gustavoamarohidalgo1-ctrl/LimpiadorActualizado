import Foundation

/// Basura del sistema (fuera de tu carpeta y de root): se borra con la contraseña de administrador
/// y no pasa por la Papelera. Ninguna se marca sola.
extension Catalogo {
    static let sistema: [Regla] = [
        Regla("sistema-informes-fallos", "/Library/Logs/DiagnosticReports",
              nombre: "Informes de fallos del sistema",
              detalle: "Informes que macOS guarda cuando un programa del sistema se cierra de golpe o se cuelga.",
              consecuencia: "Nada: solo sirven para diagnosticar errores antiguos; se crean nuevos cuando hace falta.")
            .admin().hijos().edad(dias: 7).sinPreseleccion(),
        Regla("sistema-registros", "/Library/Logs",
              nombre: "Registros viejos de apps del sistema",
              detalle: "Registros (logs) que instaladores, controladores y apps guardan para todo el Mac.",
              consecuencia: "Nada: solo se pierden registros de hace más de un mes.")
            .admin().archivos("log", "log.0", "log.1", "old", "gz", "bz2").edad(dias: 30).sinPreseleccion(),
        Regla("sistema-registros-comprimidos", "/private/var/log",
              nombre: "Registros comprimidos de macOS",
              detalle: "Registros antiguos del sistema que macOS ya archivó y comprimió.",
              consecuencia: "Nada: macOS no los vuelve a leer; los registros actuales no se tocan.")
            .admin().archivos("gz", "bz2").edad(dias: 7).sinPreseleccion(),
        Regla("sistema-volcados", "/cores",
              nombre: "Volcados de memoria",
              detalle: "Copias completas de la memoria de programas que fallaron (pueden ocupar varios GB cada una).",
              consecuencia: "Nada: solo sirven para que un programador depure un fallo concreto.")
            .admin().hijos().sinPreseleccion(),
        Regla("sistema-restos-actualizacion", "/macOS Install Data",
              nombre: "Restos de una actualización de macOS",
              detalle: "Archivos que deja una actualización de macOS que se interrumpió o terminó mal.",
              consecuencia: "Si hay una actualización a medias, tendrás que volver a descargarla desde Ajustes › General › Actualización de software.")
            .admin().edad(dias: 7).revisar(),
        Regla("sistema-microsoft-autoupdate", "/Library/Caches/com.microsoft.autoupdate.helper/Clones.noindex",
              nombre: "Copias de Microsoft AutoUpdate",
              detalle: "Copias completas de las apps de Office que Microsoft AutoUpdate prepara al actualizar.",
              consecuencia: "Nada: Office ya está actualizado; AutoUpdate las crea de nuevo en la próxima actualización.")
            .admin().sinPreseleccion().app("Microsoft AutoUpdate", "com.microsoft.autoupdate2"),
        Regla("sistema-simuladores", "/Library/Developer/CoreSimulator/Caches",
              nombre: "Cachés de los simuladores de iOS (sistema)",
              detalle: "Bibliotecas precompiladas que los simuladores generan para arrancar rápido.",
              consecuencia: "El próximo arranque de cada simulador tardará más mientras se regeneran.")
            .admin().sinPreseleccion().app("Simulator", "com.apple.iphonesimulator", "com.apple.dt.Xcode"),
        Regla("sistema-aerial", "/Library/Application Support/com.apple.idleassetsd/Customer",
              nombre: "Vídeos de fondos y salvapantallas Aerial",
              detalle: "Los vídeos de paisajes que macOS descargó para el fondo de pantalla y el salvapantallas.",
              consecuencia: "macOS los vuelve a descargar si eliges ese fondo o salvapantallas. Si uno está en uso, se verá en negro hasta que se descargue otra vez.")
            .admin().archivos("mov").revisar(),
        Regla("sistema-macports", "/opt/local/var/macports/distfiles",
              nombre: "Descargas de MacPorts",
              detalle: "El código fuente que MacPorts descargó para instalar programas.",
              consecuencia: "Nada: los programas ya están instalados. Es lo mismo que «port clean --dist».")
            .admin().sinPreseleccion().proceso("MacPorts", patron: "/opt/local/bin/port"),
    ]
}
