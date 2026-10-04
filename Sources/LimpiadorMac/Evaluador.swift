import Foundation

/// Todo lo que el análisis sabe del Mac en este momento.
struct Contexto {
    let indice: Indice
    let apps: AppsInstaladas
    let procesos: Procesos
    let accesoTotal: Bool
    let memoria = Memoria()
}

/// Lo que una categoría descubre y otra necesita saber.
final class Memoria: @unchecked Sendable {
    /// Archivos que son clones de APFS: comparten espacio con otra copia.
    var clones: [String: String] = [:]
}

/// Revisa cada elemento con reglas generales (contenido, claves, código, uso actual…)
/// y decide su riesgo final. Nunca baja un riesgo: solo lo sube y explica por qué.
enum Evaluador {
    /// Categorías donde encontrar archivos personales es mala señal.
    private static let revisarContenido: Set<Categoria> = [.restos, .herramientas, .cachesApps, .registros, .temporales]
    private static let palabrasRespaldo = ["respaldo", "backup", "copia de seguridad", "copias de seguridad", "evidencia", "evidence"]
    private static let revisarCodigo: Set<Categoria> = [.restos, .herramientas, .cachesApps, .registros, .grandes]

    static func evaluar(_ el: inout Elemento, _ c: Contexto) {
        let riesgoInicial = el.riesgo
        var nuevos: [Motivo] = []
        var riesgo = el.riesgo
        let rutas = el.accion == .borrar || el.accion == .vaciarPapelera ? el.rutas : el.rutas.filter { c.indice.estaIndexada($0.path) }
        el.contenido = c.indice.contenido(de: rutas)

        // 1. Llaves de firma, certificados y contraseñas.
        let sensibles = c.indice.sensibles(dentro: rutas)
        // En Library (o en las carpetas de sistema), una clave es la sesión o las credenciales de la propia app;
        // fuera, son tuyas.
        let deApps = sensibles.filter { ($0.zona == .library || $0.zona == .sistema) && $0.tipo != .firebase }
        let tuyas = sensibles.filter { $0.zona != .library && $0.zona != .sistema }
        let keystores = tuyas.filter { $0.tipo == .keystore }
        let secretos = tuyas.filter { $0.tipo == .certificado || $0.tipo == .llaveSSH || $0.tipo == .secreto }
        let firebase = sensibles.filter { $0.tipo == .firebase }
        if !keystores.isEmpty {
            nuevos.append(.peligro("key.fill", "Keystore",
                "Contiene \(Formato.listaCorta(keystores.map(\.nombre))): la llave con la que firmas apps de Android. Si es la de Play Store y la pierdes, no podrás publicar más actualizaciones de esa app."))
            riesgo = .cuidado
        }
        if !secretos.isEmpty {
            nuevos.append(.peligro("lock.fill", "Claves",
                "Contiene claves o contraseñas: \(Formato.listaCorta(secretos.map(\.nombre))). Guárdalas en otro sitio antes de borrar."))
            riesgo = .cuidado
        }
        if !deApps.isEmpty {
            nuevos.append(.aviso("person.badge.key.fill", "Sesión guardada",
                "Guarda credenciales de la app (\(Formato.listaCorta(deApps.map(\.nombre)))): normalmente tu sesión iniciada. Si la app ya no está, no sirven de nada; si la vuelves a instalar, tendrás que iniciar sesión otra vez."))
            riesgo = max(riesgo, .revisar)
        }
        if !firebase.isEmpty {
            nuevos.append(.aviso("flame.fill", "Firebase",
                "Contiene la configuración de Firebase (\(Formato.listaCorta(firebase.map(\.nombre)))). Se puede volver a descargar desde la consola de Firebase."))
            riesgo = max(riesgo, .revisar)
        }

        // 2. Código fuente con historial (repositorios git).
        if revisarCodigo.contains(el.categoria) {
            let repos = c.indice.repos(dentro: rutas)
            if !repos.isEmpty {
                let nombres = repos.map { Rutas.nombre($0) }
                nuevos.append(.peligro("chevron.left.forwardslash.chevron.right", "Código",
                    "Contiene \(repos.count == 1 ? "un proyecto" : "\(repos.count) proyectos") con código e historial (git): \(Formato.listaCorta(nombres))."))
                riesgo = .cuidado
            }
        }

        // 3. Archivos personales donde no deberían estar.
        if revisarContenido.contains(el.categoria) && el.contenido.esPersonal {
            let grave = el.categoria == .restos || el.categoria == .herramientas
            let texto = "Contiene \(el.contenido.resumenPersonal). Comprueba que no sean tuyos antes de borrarlo."
            nuevos.append(grave ? .peligro("doc.richtext.fill", "Archivos tuyos", texto) : .aviso("doc.richtext.fill", "Archivos tuyos", texto))
            riesgo = max(riesgo, grave ? .cuidado : .revisar)
        }
        if (el.categoria == .restos || el.categoria == .herramientas) && el.contenido.bases > 0 {
            nuevos.append(.info("cylinder.split.1x2.fill", "Datos guardados",
                "Tiene \(el.contenido.bases == 1 ? "una base de datos" : "\(el.contenido.bases) bases de datos"): normalmente historial, sesiones o ajustes de la app."))
        }

        // 4. Apps compiladas para publicar.
        let releases = c.indice.releases(dentro: rutas)
        if !releases.isEmpty && el.categoria != .instaladores {
            nuevos.append(.aviso("shippingbox.and.arrow.backward.fill", "App para publicar",
                "Contiene \(Formato.listaCorta(releases.map { Rutas.nombre($0) })): una app compilada para publicar. Si aún no la subiste a la tienda, guárdala antes (o vuelve a compilarla)."))
            riesgo = max(riesgo, .revisar)
        }

        // 5. Carpetas de respaldo: lo que hay dentro puede ser la única copia de algo.
        let respaldo = rutas.first { u in
            let p = u.path.lowercased()
            return palabrasRespaldo.contains { p.contains("/\($0)") || p.contains("_\($0)") || p.contains("-\($0)") || p.contains(" \($0)") }
        }
        if let respaldo, el.categoria != .emuladores {
            nuevos.append(.aviso("externaldrive.badge.timemachine", "Respaldo",
                "Está dentro de una carpeta de respaldo (\(Formato.rutaCorta(respaldo.deletingLastPathComponent()))): puede ser la única copia de algo que guardaste a propósito."))
            riesgo = max(riesgo, .revisar)
        }

        // 6. Actividad muy reciente.
        if let fecha = el.ultimoUso, [.restos, .herramientas, .grandes, .duplicados].contains(el.categoria) {
            let minutos = Date().timeIntervalSince(fecha) / 60
            if minutos < 60 {
                nuevos.append(.aviso("clock.badge.exclamationmark.fill", "En uso",
                    "Se modificó hace \(max(1, Int(minutos))) minutos: algo lo está usando ahora mismo."))
                riesgo = max(riesgo, .revisar)
            }
        }

        // 7. Algo lo está usando en este momento.
        if let uso = el.enUso, c.procesos.estaEnUso(uso) {
            el.abiertoAhora = true
            switch uso {
            case .emulador, .simulador:
                nuevos.append(.peligro("play.circle.fill", "Encendido",
                    "\(uso.descripcion) está encendido. Apágalo antes de limpiar; si sigue encendido, no lo tocaré."))
            case .gradle:
                nuevos.append(.aviso("macwindow.badge.plus", "Gradle trabajando",
                    "Gradle está funcionando (Android Studio abierto o compilando). Ciérralo antes de limpiar; si sigue activo, me saltaré este elemento."))
            case .proceso(let nombre, _):
                nuevos.append(.aviso("macwindow.badge.plus", "\(nombre) en uso",
                    "\(nombre) se está ejecutando ahora. Ciérralo antes de limpiar; si sigue en marcha, me saltaré este elemento."))
            case .app:
                let quien = abiertaAhora(uso, c) ?? uso.descripcion
                nuevos.append(.aviso("macwindow.badge.plus", "\(quien) abierta",
                    "\(quien) está abierta. Ciérrala antes de limpiar; si sigue abierta, me saltaré este elemento para no causarle problemas."))
            }
        }

        // 8. Clones de APFS: comparten espacio con otra copia, así que borrarlos libera poco o nada.
        if let otra = rutas.lazy.compactMap({ c.memoria.clones[$0.path] }).first {
            nuevos.append(.aviso("square.on.square.dashed", "No libera espacio",
                "Es un clon de \(Formato.rutaCorta(otra)): los dos comparten el mismo espacio en disco, así que borrar solo este no libera casi nada."))
        }

        // 9. En la nube: borrar aquí lo borra en todos tus dispositivos.
        if rutas.contains(where: { $0.path.contains("/Library/Mobile Documents/") || $0.path.contains("/Library/CloudStorage/") }) {
            nuevos.append(.peligro("icloud.fill", "En la nube",
                "Está en iCloud Drive o en una carpeta sincronizada: si lo borras aquí, se borra en todos tus dispositivos."))
            riesgo = .cuidado
        }

        el.motivos.append(contentsOf: nuevos)
        el.motivos.sort { $0.nivel > $1.nivel }
        el.riesgo = max(el.riesgo, riesgo)
        if el.riesgo > riesgoInicial || nuevos.contains(where: { $0.nivel >= .aviso }) {
            el.seleccionado = false
        }
    }

    private static func abiertaAhora(_ uso: EnUso, _ c: Contexto) -> String? {
        if case .app(_, let claves) = uso { return c.procesos.appAbierta(claves).map { $0 } }
        return nil
    }

    /// Evaluación rápida de cualquier carpeta (para el explorador): qué hay dentro que convenga conservar.
    static func avisosRapidos(de url: URL, indice: Indice) -> [String] {
        var r: [String] = []
        let s = indice.sensibles(dentro: [url])
        if s.contains(where: { $0.tipo == .keystore }) { r.append("un keystore de Android") }
        if s.contains(where: { $0.tipo != .keystore && $0.tipo != .firebase }) { r.append("claves o contraseñas") }
        let repos = indice.repos(dentro: [url])
        if s.contains(where: { $0.tipo == .firebase }) { r.append("configuración de Firebase") }
        if !repos.isEmpty { r.append(repos.count == 1 ? "un proyecto con código (git)" : "\(repos.count) proyectos con código (git)") }
        let c = indice.contenido(de: [url])
        if c.esPersonal { r.append(c.resumenPersonal) }
        if !indice.releases(dentro: [url]).isEmpty { r.append("apps compiladas para publicar") }
        return r
    }
}
