import Foundation

struct EstadoAnalisis: Sendable {
    var fraccion: Double
    /// Índice dentro de `Escaner.fases`.
    var fase: Int
    var mensaje: String
    var detalle: String = ""
}

/// Hace el análisis profundo: indexa el disco una vez y cada categoría consulta ese índice.
struct Escaner {
    typealias Progreso = @Sendable (EstadoAnalisis) -> Void
    typealias Entrega = @Sendable ([Elemento]) -> Void

    /// Orden de análisis. «Archivos grandes» va al final para no repetir lo que ya ofrecieron otras categorías.
    static let orden: [Categoria] = [.emuladores, .desarrollo, .cachesApps, .temporales, .restos, .proyectos,
                                     .herramientas, .instaladores, .registros, .papelera, .duplicados, .grandes]
    static let fases: [String] = ["Apps abiertas", "Índice del disco", "Apps instaladas"] + orden.map(\.titulo)

    private let minimo: Int64 = 1_000_000
    /// Carpetas de la propia app: nunca se ofrecen.
    private static let propios: Set<String> = ["LimpiadorMac", "com.gustavo.LimpiadorMac", "com.gustavo.limpiadormac"]

    @discardableResult
    func ejecutar(progreso: Progreso, entrega: Entrega) -> Indice {
        progreso(EstadoAnalisis(fraccion: 0.01, fase: 0, mensaje: "Viendo qué apps están abiertas…"))
        let procesos = Procesos.capturar()
        let acceso = Seguridad.tieneAccesoTotal()

        let anterior = UserDefaults.standard.double(forKey: "bytesIndiceAnterior")
        let estimado = anterior > 0 ? anterior : Double(InfoDisco.actual().usado) * 0.45
        let indice = Indice.construir(accesoTotal: acceso) { p in
            let f = min(0.98, Double(p.bytes) / max(estimado, 1))
            var detalle = "\(Formato.numero(p.archivos)) archivos · \(Formato.bytes(p.bytes))"
            if !p.ruta.isEmpty { detalle += " · \(Formato.rutaCorta(p.ruta))" }
            progreso(EstadoAnalisis(fraccion: 0.03 + 0.6 * f, fase: 1, mensaje: "Indexando tu disco…", detalle: detalle))
        }
        UserDefaults.standard.set(Double(indice.bytesTotales), forKey: "bytesIndiceAnterior")

        progreso(EstadoAnalisis(fraccion: 0.64, fase: 2, mensaje: "Reconociendo tus apps y herramientas…",
                                detalle: "\(Formato.numero(indice.archivosTotales)) archivos indexados"))
        let apps = AppsInstaladas.cargar(appsExtra: indice.apps.filter { !$0.hasPrefix("/Users/Shared/") })
        let c = Contexto(indice: indice, apps: apps, procesos: procesos, accesoTotal: acceso)

        var ofrecidas: [String] = []
        for (i, categoria) in Self.orden.enumerated() {
            progreso(EstadoAnalisis(fraccion: 0.66 + 0.34 * Double(i) / Double(Self.orden.count), fase: 3 + i,
                                    mensaje: "Revisando \(categoria.titulo.lowercased())…",
                                    detalle: "\(Formato.numero(indice.archivosTotales)) archivos indexados"))
            var elementos = generar(categoria, c, ofrecidas: ofrecidas)
            for j in elementos.indices {
                medir(&elementos[j], c)
                Evaluador.evaluar(&elementos[j], c)
                elementos[j].recomendado = elementos[j].seleccionado
            }
            elementos = elementos.filter { $0.tamano >= minimo }.sorted { $0.tamano > $1.tamano }
            ofrecidas += elementos.flatMap { $0.rutas.map(\.path) }
            entrega(elementos)
        }
        progreso(EstadoAnalisis(fraccion: 1, fase: Self.fases.count, mensaje: "Análisis terminado",
                                detalle: "\(Formato.numero(indice.archivosTotales)) archivos revisados"))
        return indice
    }

    private func generar(_ categoria: Categoria, _ c: Contexto, ofrecidas: [String]) -> [Elemento] {
        let elementos: [Elemento]
        switch categoria {
        case .emuladores: elementos = emuladores(c)
        case .desarrollo: elementos = desarrollo(c)
        case .cachesApps: elementos = cachesApps(c)
        case .temporales: elementos = temporales(c)
        case .restos: elementos = restos(c)
        case .proyectos: elementos = proyectos(c)
        case .herramientas: elementos = herramientas(c)
        case .instaladores: elementos = instaladores(c)
        case .registros: elementos = registros(c)
        case .papelera: elementos = papelera()
        case .duplicados: elementos = duplicados(c)
        case .grandes: elementos = grandes(c, ofrecidas: ofrecidas)
        }
        // Las rutas protegidas nunca se ofrecen, aunque alguna regla las haya encontrado.
        return elementos.compactMap { el in
            guard el.accion == .borrar else { return el }
            var e = el
            e.rutas = el.rutas.filter(Seguridad.sePuedeBorrar)
            return e.rutas.isEmpty ? nil : e
        }
    }

    private func medir(_ el: inout Elemento, _ c: Contexto) {
        if let fijo = el.tamanoFijo {
            el.tamano = fijo
            el.tamanosRutas = el.rutas.map { _ in 0 }
        } else {
            el.tamanosRutas = el.rutas.map { c.indice.bytes(de: $0) }
            el.tamano = el.tamanosRutas.reduce(0, +)
        }
        if el.ultimoUso == nil { el.ultimoUso = c.indice.masReciente(de: el.rutas) }
    }

    // MARK: - Emuladores y simuladores

    private func emuladores(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let avdDir = Rutas.enHome(".android/avd")
        var usoImagenes: [String: [String]] = [:]

        for avd in Rutas.hijos(avdDir) where avd.pathExtension == "avd" {
            let base = avd.deletingPathExtension().lastPathComponent
            let config = (try? String(contentsOf: avd.appendingPathComponent("config.ini"), encoding: .utf8)) ?? ""
            var nombre = base.replacingOccurrences(of: "_", with: " ")
            var imagenes: [String] = []
            for linea in config.split(separator: "\n") {
                let kv = linea.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2 else { continue }
                if kv[0] == "avd.ini.displayname" { nombre = kv[1] }
                if kv[0].hasPrefix("image.sysdir") { imagenes.append(kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
            }
            for img in imagenes { usoImagenes[img, default: []].append(nombre) }
            let uso = EnUso.emulador(avd: base)
            let ini = avdDir.appendingPathComponent(base + ".ini")

            r.append(Elemento(
                nombre: "Emulador Android: \(nombre)",
                detalle: "El emulador completo: su sistema, las apps que instalaste y sus datos.",
                consecuencia: "Desaparece de Android Studio. Puedes crear otro en Device Manager, pero empezará vacío.",
                rutas: Rutas.existe(ini) ? [avd, ini] : [avd],
                categoria: .emuladores, riesgo: .revisar,
                motivos: [.info("lightbulb.fill", "Hay una alternativa",
                                "Si solo necesitas espacio, «Restablecer \(nombre)» libera casi lo mismo y conserva el emulador.")],
                enUso: uso, dueno: "Android Studio"))

            // Datos internos: lo mismo que borra «Wipe Data» en Android Studio.
            let prefijos = ["userdata-qemu.img", "cache.img", "encryptionkey.img"]
            var datos = Rutas.hijos(avd).filter { u in
                let n = u.lastPathComponent
                return prefijos.contains { n.hasPrefix($0) } && !n.hasSuffix(".lock")
            }
            let snaps = avd.appendingPathComponent("snapshots")
            if Rutas.existe(snaps) { datos.append(snaps) }
            if !datos.isEmpty {
                r.append(Elemento(
                    nombre: "Restablecer \(nombre)",
                    detalle: "Lo que hay dentro del emulador: apps instaladas, cuentas, fotos y archivos.",
                    consecuencia: "Es lo mismo que «Wipe Data» en Android Studio: el emulador sigue ahí y arranca como recién creado.",
                    rutas: datos, categoria: .emuladores, riesgo: .revisar,
                    motivos: [.bien("arrow.counterclockwise", "Conserva el emulador",
                                    "El emulador no se elimina: solo vuelve a su estado de fábrica. No hay que configurarlo otra vez.")],
                    enUso: uso, dueno: "Android Studio"))
            }
            if Rutas.existe(snaps) {
                r.append(Elemento(
                    nombre: "Snapshots de \(nombre)",
                    detalle: "Estados guardados para que el emulador arranque al instante.",
                    consecuencia: "La próxima vez el emulador arranca en frío (tarda un poco más). No pierdes nada.",
                    rutas: [snaps], categoria: .emuladores, riesgo: .seguro,
                    motivos: [.bien("bolt.fill", "Sin pérdida", "Solo se pierde el arranque rápido.")],
                    enUso: uso, dueno: "Android Studio"))
            }
        }

        // Imágenes del sistema: sdk/system-images/android-XX/<tipo>/<abi>
        let sdk = Rutas.enHome("Library/Android/sdk")
        for version in Rutas.hijos(sdk.appendingPathComponent("system-images")) where Rutas.esCarpeta(version) {
            for tipo in Rutas.hijos(version) where Rutas.esCarpeta(tipo) {
                for abi in Rutas.hijos(tipo) where Rutas.esCarpeta(abi) {
                    let rel = "system-images/\(version.lastPathComponent)/\(tipo.lastPathComponent)/\(abi.lastPathComponent)"
                    let usan = usoImagenes[rel] ?? []
                    let v = version.lastPathComponent.replacingOccurrences(of: "android-", with: "")
                    let nombre = "Imagen de Android \(v) (\(tipo.lastPathComponent.replacingOccurrences(of: "_", with: " ")))"
                    if usan.isEmpty {
                        r.append(Elemento(
                            nombre: nombre,
                            detalle: "Sistema Android que se descargó para crear emuladores.",
                            consecuencia: "Si algún día creas un emulador con esta versión, Android Studio la vuelve a descargar.",
                            rutas: [abi], categoria: .emuladores, riesgo: .seguro, seleccionado: true,
                            motivos: [.bien("checkmark.circle.fill", "Sin usar", "Ningún emulador la usa.")],
                            dueno: "Android Studio"))
                    } else {
                        r.append(Elemento(
                            nombre: nombre,
                            detalle: "Sistema Android sobre el que funcionan tus emuladores.",
                            consecuencia: "\(Formato.lista(usan)) dejaría de arrancar hasta que la vuelvas a descargar.",
                            rutas: [abi], categoria: .emuladores, riesgo: .cuidado,
                            motivos: [.peligro("iphone.gen3", usan.count == 1 ? "La usa \(usan[0])" : "La usan \(usan.count) emuladores",
                                               "La usa \(Formato.lista(usan)). Si la borras, ese emulador deja de funcionar.")],
                            dueno: "Android Studio"))
                    }
                }
            }
        }

        // Lo que usan de verdad tus proyectos, según sus archivos de Gradle.
        let usoSDK = UsoSDK.leer(c.indice.archivosGradle)
        let androidStudio = EnUso.app(nombre: "Android Studio", claves: ["com.google.android.studio"])

        // Plataformas (android-XX) con las que no compila ningún proyecto. La más nueva se conserva.
        let plataformas = Rutas.hijos(sdk.appendingPathComponent("platforms")).filter { Rutas.esCarpeta($0) }
            .compactMap { p in UsoSDK.numeroPlataforma(p.lastPathComponent).map { (url: p, api: $0) } }
        let apiMasNueva = plataformas.map(\.api).max()
        for p in plataformas where p.api != apiMasNueva && !usoSDK.plataformas.contains(p.api) {
            let seguro = usoSDK.archivos > 0 && !usoSDK.plataformaIncierta
            r.append(Elemento(
                nombre: "Plataforma Android \(p.api) (sin usar)",
                detalle: "Lo necesario para compilar apps con la API \(p.api) de Android.",
                consecuencia: "Si un proyecto vuelve a compilar con la API \(p.api), Android Studio la descarga otra vez.",
                rutas: [p.url], categoria: .emuladores, riesgo: seguro ? .seguro : .revisar, seleccionado: seguro,
                motivos: [seguro
                    ? .bien("checkmark.circle.fill", "Ningún proyecto la usa",
                            "Revisé \(usoSDK.archivos) archivos de Gradle de tus proyectos: ninguno compila con la API \(p.api).")
                    : .info("questionmark.circle", "No lo sé con certeza",
                            usoSDK.archivos == 0 ? "No encontré proyectos de Android para comprobar qué API usan."
                                              : "Algún proyecto elige la API con una variable (Flutter, React Native…) y no puedo saber cuál.")],
                enUso: androidStudio, dueno: "Android Studio"))
        }

        // Versiones antiguas de build-tools y NDK: se conserva la más nueva y las que pide algún proyecto.
        let herramientasSDK: [(carpeta: String, nombre: String, detalle: String, usadas: Set<String>, incierto: Bool)] = [
            ("build-tools", "Android build-tools", "Herramientas de compilación de Android.", usoSDK.buildTools, false),
            ("ndk", "Android NDK", "Kit para compilar código nativo (C/C++).", usoSDK.ndk, usoSDK.ndkIncierto),
        ]
        for h in herramientasSDK {
            let versiones = Rutas.hijos(sdk.appendingPathComponent(h.carpeta)).filter { Rutas.esCarpeta($0) }
                .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
            guard let masNueva = versiones.last?.lastPathComponent else { continue }
            for v in versiones.dropLast() where !h.usadas.contains(v.lastPathComponent) {
                r.append(Elemento(
                    nombre: "\(h.nombre) \(v.lastPathComponent) (versión antigua)",
                    detalle: h.detalle,
                    consecuencia: "Si algún proyecto pide esta versión exacta, Gradle la vuelve a descargar.",
                    rutas: [v], categoria: .emuladores, riesgo: h.incierto ? .revisar : .seguro, seleccionado: !h.incierto,
                    motivos: [h.incierto
                        ? .info("questionmark.circle", "No lo sé con certeza",
                                "Algún proyecto elige la versión del NDK con una variable y no puedo saber cuál usa.")
                        : .bien("clock.arrow.circlepath", "Ningún proyecto la pide",
                                "Ya tienes la versión \(masNueva) y ninguno de tus proyectos pide esta.")],
                    enUso: androidStudio, dueno: "Android Studio"))
            }
        }

        // Descargas que se quedaron a medias.
        let aMedias = [".temp", ".downloadIntermediates"].map { sdk.appendingPathComponent($0) }.filter { Rutas.existe($0) }
        if !aMedias.isEmpty {
            r.append(Elemento(
                nombre: "Descargas a medias del SDK de Android",
                detalle: "Restos de descargas e instalaciones del SDK Manager que no terminaron.",
                consecuencia: "Nada: el SDK Manager crea estas carpetas de nuevo cuando las necesita.",
                rutas: aMedias, categoria: .emuladores, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("arrow.down.circle.dotted", "Temporales", "Solo son restos de descargas.")],
                enUso: androidStudio, dueno: "Android Studio"))
        }
        for fuente in Rutas.hijos(sdk.appendingPathComponent("sources")) where Rutas.esCarpeta(fuente) {
            r.append(Elemento(
                nombre: "Código fuente de Android \(fuente.lastPathComponent.replacingOccurrences(of: "android-", with: ""))",
                detalle: "Código de Android para consultarlo desde el editor.",
                consecuencia: "Al abrir una clase de Android verás código descompilado en vez del original. Se puede volver a descargar.",
                rutas: [fuente], categoria: .emuladores, riesgo: .seguro,
                motivos: [.bien("book.closed.fill", "Solo consulta", "No se usa para compilar.")],
                dueno: "Android Studio"))
        }

        r += simuladoresIOS()
        return r
    }

    private func simuladoresIOS() -> [Elemento] {
        var r: [Elemento] = []
        let iso = ISO8601DateFormatter()
        var runtimesUsados = Set<String>()
        var listaCompleta = false

        let json = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"], limite: 60).salida
        if let datos = json.data(using: .utf8),
           let raiz = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
           let porRuntime = raiz["devices"] as? [String: [[String: Any]]] {
            listaCompleta = true
            for (runtime, dispositivos) in porRuntime {
                if dispositivos.contains(where: { ($0["isAvailable"] as? Bool) ?? true }) { runtimesUsados.insert(runtime) }
                let version = runtime.components(separatedBy: "SimRuntime.").last?.replacingOccurrences(of: "-", with: " ") ?? runtime
                for d in dispositivos {
                    guard let udid = d["udid"] as? String, let nombre = d["name"] as? String,
                          let dataPath = d["dataPath"] as? String else { continue }
                    let disponible = d["isAvailable"] as? Bool ?? true
                    let ultimo = ((d["lastBootedAt"] as? String) ?? (d["lastUsedAt"] as? String)).flatMap { iso.date(from: $0) }
                    if disponible {
                        r.append(Elemento(
                            nombre: "Simulador iOS: \(nombre) (\(version))",
                            detalle: "Apps y datos que instalaste en este simulador.",
                            consecuencia: "El simulador sigue en Xcode, pero vacío, como recién creado.",
                            rutas: [URL(fileURLWithPath: dataPath)], ultimoUso: ultimo,
                            categoria: .emuladores, riesgo: .revisar, accion: .vaciarSimulador(udid: udid),
                            motivos: [.bien("arrow.counterclockwise", "Conserva el simulador", "Solo se borra su contenido.")],
                            enUso: .simulador(udid: udid), dueno: "Xcode"))
                    } else {
                        r.append(Elemento(
                            nombre: "Simulador sin sistema: \(nombre)",
                            detalle: "Su versión de iOS ya no está instalada, así que no se puede usar.",
                            consecuencia: "Nada: este simulador ya no funcionaba.",
                            rutas: [URL(fileURLWithPath: dataPath).deletingLastPathComponent()], ultimoUso: ultimo,
                            categoria: .emuladores, riesgo: .seguro, seleccionado: true,
                            accion: .eliminarSimulador(udid: udid),
                            motivos: [.bien("xmark.circle.fill", "Inservible", "Su sistema iOS ya no existe en este Mac.")],
                            dueno: "Xcode"))
                    }
                }
            }
        }

        // Sistemas iOS descargados que ya no usa ningún simulador. Si no se pudo leer la lista de simuladores,
        // no se sabe cuáles se usan: no se ofrece ninguno.
        guard listaCompleta else { return r }
        let runtimes = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], limite: 60).salida
        if let datos = runtimes.data(using: .utf8),
           let lista = try? JSONSerialization.jsonObject(with: datos) as? [String: [String: Any]] {
            for (id, info) in lista {
                guard let identificador = info["runtimeIdentifier"] as? String,
                      (info["deletable"] as? Bool) == true,
                      !runtimesUsados.contains(identificador) else { continue }
                let version = info["version"] as? String ?? "?"
                let tamano = (info["sizeBytes"] as? NSNumber)?.int64Value ?? 0
                let ruta = info["path"] as? String ?? "/Library/Developer/CoreSimulator"
                let ultimo = (info["lastUsedAt"] as? String).flatMap { iso.date(from: $0) }
                r.append(Elemento(
                    nombre: "iOS \(version) para simuladores",
                    detalle: "Sistema iOS \(version) que Xcode descargó para los simuladores.",
                    consecuencia: "Si algún día necesitas probar en iOS \(version), Xcode lo vuelve a descargar desde Ajustes › Componentes (\(Formato.bytes(tamano))).",
                    rutas: [URL(fileURLWithPath: ruta)], tamanoFijo: tamano, ultimoUso: ultimo,
                    categoria: .emuladores, riesgo: .seguro, seleccionado: true, accion: .eliminarRuntime(id: id),
                    motivos: [.bien("checkmark.circle.fill", "Ningún simulador lo usa",
                                    "Ninguno de tus simuladores usa iOS \(version): todos están en otras versiones.")],
                    dueno: "Xcode"))
            }
        }
        return r
    }

    // MARK: - Cachés de desarrollo

    private struct CacheDev {
        let rel: String
        let nombre: String
        let detalle: String
        let consecuencia: String
        var riesgo: Riesgo = .seguro
        var preseleccion = true
        var uso: EnUso? = nil
        var dueno: String? = nil
    }

    private static let xcodeUso = EnUso.app(nombre: "Xcode", claves: ["com.apple.dt.Xcode"])

    private static let cachesDeDesarrollo: [CacheDev] = [
        CacheDev(rel: ".npm/_cacache", nombre: "Caché de npm", detalle: "Paquetes de npm descargados.",
                 consecuencia: "npm los vuelve a descargar la próxima vez que instales paquetes (necesita internet).", dueno: "npm"),
        CacheDev(rel: ".npm/_npx", nombre: "Paquetes temporales de npx", detalle: "Herramientas que npx descargó una vez para ejecutarlas.",
                 consecuencia: "Si vuelves a usar esa herramienta con npx, se descarga otra vez.", dueno: "npm"),
        CacheDev(rel: ".gradle/daemon", nombre: "Registros del daemon de Gradle", detalle: "Registros de procesos de Gradle que ya terminaron.",
                 consecuencia: "Nada: solo son registros.", uso: .gradle, dueno: "Gradle"),
        CacheDev(rel: ".gradle/.tmp", nombre: "Temporales de Gradle", detalle: "Archivos temporales de Gradle.",
                 consecuencia: "Nada: Gradle crea nuevos cuando los necesita.", uso: .gradle, dueno: "Gradle"),
        CacheDev(rel: "Library/Developer/Xcode/UserData/Previews", nombre: "Vistas previas de SwiftUI",
                 detalle: "Simuladores internos que Xcode usa para las vistas previas.",
                 consecuencia: "Xcode los vuelve a crear la próxima vez que abras una vista previa.", uso: xcodeUso, dueno: "Xcode"),
        CacheDev(rel: "Library/Developer/CoreSimulator/Caches", nombre: "Caché de simuladores", detalle: "Caché de los simuladores de iOS.",
                 consecuencia: "Los simuladores la regeneran al arrancar.", dueno: "Xcode"),
        CacheDev(rel: "Library/Caches/CocoaPods", nombre: "Caché de CocoaPods", detalle: "Pods descargados.",
                 consecuencia: "pod install los vuelve a descargar.", dueno: "CocoaPods"),
        CacheDev(rel: ".cocoapods/repos", nombre: "Repositorios de CocoaPods", detalle: "Índices de librerías de CocoaPods.",
                 consecuencia: "pod install los vuelve a descargar (puede tardar).", preseleccion: false, dueno: "CocoaPods"),
        CacheDev(rel: "Library/Caches/pip", nombre: "Caché de pip", detalle: "Paquetes de Python descargados.",
                 consecuencia: "pip los vuelve a descargar si hacen falta.", dueno: "Python"),
        CacheDev(rel: ".cache/pip", nombre: "Caché de pip", detalle: "Paquetes de Python descargados.",
                 consecuencia: "pip los vuelve a descargar si hacen falta.", dueno: "Python"),
        CacheDev(rel: ".cache/uv", nombre: "Caché de uv", detalle: "Paquetes de Python descargados por uv.",
                 consecuencia: "uv los vuelve a descargar si hacen falta.", dueno: "Python"),
        CacheDev(rel: "Library/Caches/pypoetry", nombre: "Caché de Poetry", detalle: "Paquetes de Python descargados por Poetry.",
                 consecuencia: "Poetry los vuelve a descargar si hacen falta.", dueno: "Python"),
        CacheDev(rel: "Library/Caches/Homebrew", nombre: "Caché de Homebrew", detalle: "Instaladores que descargó brew.",
                 consecuencia: "Nada: los programas ya están instalados.", dueno: "Homebrew"),
        CacheDev(rel: "Library/Caches/electron", nombre: "Caché de Electron", detalle: "Versiones de Electron descargadas al instalar paquetes.",
                 consecuencia: "Se vuelven a descargar al instalar un proyecto de Electron.", dueno: "Electron"),
        CacheDev(rel: "Library/Caches/electron-builder", nombre: "Caché de electron-builder",
                 detalle: "Herramientas descargadas para empaquetar apps de Electron.",
                 consecuencia: "Se vuelven a descargar al empaquetar.", dueno: "Electron"),
        CacheDev(rel: "Library/Caches/node-gyp", nombre: "Caché de node-gyp", detalle: "Cabeceras de Node para compilar módulos nativos.",
                 consecuencia: "Se vuelven a descargar si hacen falta.", dueno: "Node"),
        CacheDev(rel: "Library/Caches/org.swift.swiftpm", nombre: "Caché de Swift Package Manager", detalle: "Paquetes de Swift descargados.",
                 consecuencia: "Se vuelven a descargar al compilar.", dueno: "Xcode"),
        CacheDev(rel: "Library/Caches/Yarn", nombre: "Caché de Yarn", detalle: "Paquetes de Yarn descargados.",
                 consecuencia: "Yarn los vuelve a descargar.", dueno: "Yarn"),
        CacheDev(rel: ".yarn/berry/cache", nombre: "Caché de Yarn", detalle: "Paquetes de Yarn descargados.",
                 consecuencia: "Yarn los vuelve a descargar.", dueno: "Yarn"),
        CacheDev(rel: "Library/Caches/go-build", nombre: "Caché de Go", detalle: "Compilaciones de Go.",
                 consecuencia: "Go vuelve a compilar lo que necesite.", dueno: "Go"),
        CacheDev(rel: "go/pkg/mod", nombre: "Módulos de Go", detalle: "Dependencias de Go descargadas.",
                 consecuencia: "Se vuelven a descargar al compilar (necesita internet).", preseleccion: false, dueno: "Go"),
        CacheDev(rel: "Library/pnpm/store", nombre: "Almacén de pnpm", detalle: "Paquetes de pnpm descargados.",
                 consecuencia: "pnpm los vuelve a descargar.", dueno: "pnpm"),
        CacheDev(rel: ".bun/install/cache", nombre: "Caché de Bun", detalle: "Paquetes descargados por Bun.",
                 consecuencia: "Bun los vuelve a descargar.", dueno: "Bun"),
        CacheDev(rel: ".cargo/registry", nombre: "Registro de Cargo", detalle: "Librerías de Rust descargadas.",
                 consecuencia: "Cargo las vuelve a descargar al compilar.", preseleccion: false, dueno: "Rust"),
        CacheDev(rel: ".m2/repository", nombre: "Repositorio de Maven", detalle: "Dependencias Java descargadas.",
                 consecuencia: "Maven las vuelve a descargar al compilar.", preseleccion: false, dueno: "Maven"),
        CacheDev(rel: ".nuget/packages", nombre: "Paquetes de NuGet", detalle: "Dependencias de .NET descargadas.",
                 consecuencia: "Se vuelven a descargar al compilar.", preseleccion: false, dueno: ".NET"),
        CacheDev(rel: ".pub-cache", nombre: "Caché de Flutter (pub)", detalle: "Paquetes de Dart y Flutter descargados.",
                 consecuencia: "flutter pub get los vuelve a descargar.", riesgo: .revisar, preseleccion: false, dueno: "Flutter"),
        CacheDev(rel: ".cache/pre-commit", nombre: "Caché de pre-commit", detalle: "Entornos de los hooks de pre-commit.",
                 consecuencia: "Se vuelven a crear en el próximo commit.", dueno: "pre-commit"),
        CacheDev(rel: ".cache/node/corepack", nombre: "Caché de Corepack", detalle: "Versiones de gestores de paquetes de Node.",
                 consecuencia: "Se vuelven a descargar si hacen falta.", dueno: "Node"),
        CacheDev(rel: ".cache/firebase", nombre: "Caché de Firebase", detalle: "Emuladores y herramientas descargadas por Firebase CLI.",
                 consecuencia: "Firebase CLI los vuelve a descargar al usarlos.", preseleccion: false, dueno: "Firebase"),
        CacheDev(rel: ".cache/codex-runtimes", nombre: "Runtimes de Codex", detalle: "Entornos descargados por Codex.",
                 consecuencia: "Codex los vuelve a descargar si los necesita.", riesgo: .revisar, preseleccion: false,
                 uso: .proceso(nombre: "Codex", patron: "/.codex/"), dueno: "Codex"),
        CacheDev(rel: ".cache/torch", nombre: "Modelos de PyTorch", detalle: "Modelos descargados por PyTorch.",
                 consecuencia: "Se vuelven a descargar si un programa los necesita.", riesgo: .revisar, preseleccion: false, dueno: "PyTorch"),
        CacheDev(rel: ".ollama/models", nombre: "Modelos de Ollama", detalle: "Modelos de IA descargados con Ollama.",
                 consecuencia: "Tendrás que volver a descargarlos con «ollama pull» (pueden ser varios GB).", riesgo: .revisar,
                 preseleccion: false, uso: .proceso(nombre: "Ollama", patron: "ollama"), dueno: "Ollama"),
        CacheDev(rel: ".expo", nombre: "Datos de Expo", detalle: "Caché y sesión de Expo (React Native).",
                 consecuencia: "Tendrás que volver a iniciar sesión en Expo.", riesgo: .revisar, preseleccion: false, dueno: "Expo"),
        CacheDev(rel: ".android/cache", nombre: "Caché de Android", detalle: "Caché de las herramientas de Android.",
                 consecuencia: "Se regenera sola.", dueno: "Android Studio"),
        CacheDev(rel: ".android/build-cache", nombre: "Caché de compilación antigua de Android",
                 detalle: "Caché que usaban las versiones antiguas del plugin de Android para Gradle.",
                 consecuencia: "Nada: las versiones actuales ya no la usan.", uso: .gradle, dueno: "Android Studio"),
        CacheDev(rel: ".npm/_logs", nombre: "Registros de npm", detalle: "Registros de errores de npm.",
                 consecuencia: "Nada: solo son registros.", dueno: "npm"),
        CacheDev(rel: ".nvm/.cache", nombre: "Descargas de nvm", detalle: "Instaladores de Node que nvm descargó.",
                 consecuencia: "Nada: las versiones de Node ya están instaladas.", dueno: "nvm"),
        CacheDev(rel: "Library/Caches/deno", nombre: "Caché de Deno", detalle: "Módulos y compilaciones que guardó Deno.",
                 consecuencia: "Deno los vuelve a descargar si hacen falta.", dueno: "Deno"),
        CacheDev(rel: "Library/Caches/typescript", nombre: "Caché de TypeScript", detalle: "Tipos que descarga el editor para TypeScript.",
                 consecuencia: "El editor los vuelve a descargar.", dueno: "TypeScript"),
        CacheDev(rel: "Library/Caches/Cypress", nombre: "Caché de Cypress", detalle: "Versiones de Cypress descargadas.",
                 consecuencia: "Se vuelven a descargar al instalar un proyecto con Cypress.", dueno: "Cypress"),
        CacheDev(rel: ".cache/selenium", nombre: "Navegadores de Selenium", detalle: "Navegadores y drivers que descargó Selenium.",
                 consecuencia: "Selenium los vuelve a descargar.", dueno: "Selenium"),
        CacheDev(rel: "Library/Caches/org.carthage.CarthageKit", nombre: "Caché de Carthage", detalle: "Dependencias descargadas por Carthage.",
                 consecuencia: "Carthage las vuelve a descargar.", dueno: "Carthage"),
        CacheDev(rel: ".dartServer", nombre: "Caché del analizador de Dart",
                 detalle: "Índices que el editor genera para analizar código de Dart y Flutter.",
                 consecuencia: "El editor los regenera al abrir un proyecto (los primeros minutos irá más lento).",
                 uso: .proceso(nombre: "El analizador de Dart", patron: "analysis_server"), dueno: "Flutter"),
        CacheDev(rel: ".skiko", nombre: "Librerías de Skiko", detalle: "Librerías nativas que extrae Compose Multiplatform.",
                 consecuencia: "Se vuelven a extraer al ejecutar la app.", dueno: "Kotlin"),
        CacheDev(rel: ".gradle/native", nombre: "Librerías nativas de Gradle", detalle: "Librerías que Gradle extrae para funcionar.",
                 consecuencia: "Gradle las vuelve a extraer.", uso: .gradle, dueno: "Gradle"),
        CacheDev(rel: ".gradle/kotlin-profile", nombre: "Perfiles de Kotlin", detalle: "Informes de rendimiento de compilaciones de Kotlin.",
                 consecuencia: "Nada: son informes.", dueno: "Gradle"),
        CacheDev(rel: ".gradle/jdks", nombre: "JDK descargados por Gradle", detalle: "Versiones de Java que Gradle descargó para compilar.",
                 consecuencia: "Si un proyecto vuelve a pedir esa versión, Gradle la descarga otra vez.", riesgo: .revisar,
                 preseleccion: false, uso: .gradle, dueno: "Gradle"),
        CacheDev(rel: "Library/Caches/com.apple.dt.Xcode", nombre: "Caché de Xcode", detalle: "Archivos temporales de Xcode.",
                 consecuencia: "Xcode la regenera.", uso: xcodeUso, dueno: "Xcode"),
        CacheDev(rel: "Library/Developer/Xcode/DocumentationCache", nombre: "Caché de documentación de Xcode",
                 detalle: "Documentación descargada para verla dentro de Xcode.",
                 consecuencia: "Xcode la vuelve a descargar cuando abres la documentación.", uso: xcodeUso, dueno: "Xcode"),
        CacheDev(rel: "Library/Developer/XCPGDevices", nombre: "Simuladores de Playgrounds",
                 detalle: "Simuladores que Xcode crea para ejecutar Playgrounds.",
                 consecuencia: "Xcode los vuelve a crear al ejecutar un Playground.", uso: xcodeUso, dueno: "Xcode"),
        CacheDev(rel: "Library/Developer/Xcode/UserData/IB Support", nombre: "Caché de Interface Builder",
                 detalle: "Simuladores internos que usa Interface Builder para dibujar storyboards.",
                 consecuencia: "Xcode los vuelve a crear.", uso: xcodeUso, dueno: "Xcode"),
        CacheDev(rel: "Library/Developer/Xcode/iOS Device Logs", nombre: "Registros de dispositivos iOS",
                 detalle: "Registros que Xcode copió de iPhones y iPads conectados.",
                 consecuencia: "Nada: solo son registros.", dueno: "Xcode"),
    ]

    private func desarrollo(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        for d in Self.cachesDeDesarrollo {
            let url = Rutas.enHome(d.rel)
            guard Rutas.existe(url) else { continue }
            r.append(Elemento(
                nombre: d.nombre, detalle: d.detalle, consecuencia: d.consecuencia, rutas: [url],
                categoria: .desarrollo, riesgo: d.riesgo, seleccionado: d.preseleccion,
                motivos: d.riesgo == .seguro
                    ? [.bien("arrow.triangle.2.circlepath", "Se regenera", "Es una caché: se vuelve a crear o descargar cuando hace falta.")]
                    : [.info("arrow.down.circle.fill", "Se vuelve a descargar", d.consecuencia)],
                enUso: d.uso, dueno: d.dueno))
        }
        r += gradle(c)
        r += xcode()
        r += navegadoresDePrueba()
        r += versionesAnterioresDeIDEs()
        r += editores(c)
        r += homebrew()
        r += conda()

        let hf = Rutas.enHome(".cache/huggingface")
        if Rutas.existe(hf) {
            let modelos = Rutas.hijos(hf.appendingPathComponent("hub")).map(\.lastPathComponent)
                .filter { $0.hasPrefix("models--") }
                .map { String($0.dropFirst(8)).replacingOccurrences(of: "--", with: "/") }
            r.append(Elemento(
                nombre: "Modelos de IA (Hugging Face)",
                detalle: modelos.isEmpty ? "Modelos de inteligencia artificial descargados." : "Modelos descargados: \(Formato.listaCorta(modelos)).",
                consecuencia: "Si un programa vuelve a necesitar un modelo, lo descarga otra vez (pueden ser varios GB).",
                rutas: [hf], categoria: .desarrollo, riesgo: .revisar,
                motivos: [.info("arrow.down.circle.fill", "Descarga pesada", "Volver a descargarlos puede tardar bastante.")],
                dueno: "Hugging Face"))
        }
        return r
    }

    /// Gradle separado por partes, sabiendo qué versión usa cada proyecto.
    private func gradle(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        var usos: [String: [String]] = [:]   // versión → proyectos que la usan
        for w in c.indice.wrappersGradle {
            guard let texto = try? String(contentsOfFile: w, encoding: .utf8),
                  let linea = texto.split(separator: "\n").first(where: { $0.hasPrefix("distributionUrl") }),
                  let rango = linea.range(of: "gradle-") else { continue }
            let version = linea[rango.upperBound...].split(separator: "-").first.map(String.init) ?? ""
            let proyecto = Rutas.nombre(Rutas.padre(Rutas.padre(Rutas.padre(w))))
            if !version.isEmpty { usos[version, default: []].append(proyecto) }
        }

        for d in Rutas.hijos(Rutas.enHome(".gradle/wrapper/dists")) where Rutas.esCarpeta(d) {
            let v = d.lastPathComponent.replacingOccurrences(of: "gradle-", with: "")
                .replacingOccurrences(of: "-bin", with: "").replacingOccurrences(of: "-all", with: "")
            let proyectos = usos[v] ?? []
            r.append(Elemento(
                nombre: "Gradle \(v)",
                detalle: "El programa Gradle \(v), descargado por el wrapper de un proyecto.",
                consecuencia: proyectos.isEmpty
                    ? "Si algún proyecto lo vuelve a pedir, se descarga solo (unos 150 MB)."
                    : "La próxima vez que compiles \(Formato.lista(proyectos)), se vuelve a descargar.",
                rutas: [d], categoria: .desarrollo, riesgo: proyectos.isEmpty ? .seguro : .revisar,
                seleccionado: proyectos.isEmpty,
                motivos: [proyectos.isEmpty
                    ? .bien("checkmark.circle.fill", "Ningún proyecto lo usa", "Ninguno de tus proyectos usa Gradle \(v).")
                    : .info("hammer.fill", "Lo usa \(proyectos[0])", "Lo usa \(Formato.lista(proyectos)).")],
                enUso: .gradle, dueno: "Gradle"))
        }

        var compilacion: [URL] = []
        for h in Rutas.hijos(Rutas.enHome(".gradle/caches")) where Rutas.esCarpeta(h) {
            let n = h.lastPathComponent
            if n.first?.isNumber == true {
                let proyectos = usos[n] ?? []
                r.append(Elemento(
                    nombre: "Caché de Gradle \(n)",
                    detalle: "Archivos que Gradle \(n) guarda para compilar más rápido.",
                    consecuencia: proyectos.isEmpty
                        ? "Nada: ningún proyecto usa esta versión."
                        : "La próxima compilación de \(Formato.lista(proyectos)) será más lenta mientras se regenera.",
                    rutas: [h], categoria: .desarrollo, riesgo: .seguro, seleccionado: proyectos.isEmpty,
                    motivos: [proyectos.isEmpty
                        ? .bien("checkmark.circle.fill", "Versión sin usar", "Ninguno de tus proyectos usa Gradle \(n).")
                        : .info("hammer.fill", "Lo usa \(proyectos[0])", "Es la versión de \(Formato.lista(proyectos)).")],
                    enUso: .gradle, dueno: "Gradle"))
            } else if n == "modules-2" {
                r.append(Elemento(
                    nombre: "Dependencias descargadas por Gradle",
                    detalle: "Todas las librerías que descargaron tus proyectos de Android.",
                    consecuencia: "La próxima compilación las vuelve a descargar: puede tardar varios minutos y usar bastantes datos.",
                    rutas: [h], categoria: .desarrollo, riesgo: .seguro,
                    motivos: [.info("arrow.down.circle.fill", "Se vuelve a descargar", "No se pierde nada, pero descargarlo todo otra vez lleva tiempo.")],
                    enUso: .gradle, dueno: "Gradle"))
            } else {
                compilacion.append(h)
            }
        }
        if !compilacion.isEmpty {
            r.append(Elemento(
                nombre: "Cachés de compilación de Gradle",
                detalle: "Transformaciones y resultados intermedios (\(Formato.listaCorta(compilacion.map(\.lastPathComponent)))).",
                consecuencia: "Gradle los regenera en la próxima compilación.",
                rutas: compilacion, categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("arrow.triangle.2.circlepath", "Se regenera", "Gradle los vuelve a crear al compilar.")],
                enUso: .gradle, dueno: "Gradle"))
        }
        return r
    }

    private func xcode() -> [Elemento] {
        var r: [Elemento] = []
        var modulos: [URL] = []
        for h in Rutas.hijos(Rutas.enHome("Library/Developer/Xcode/DerivedData")) where Rutas.esCarpeta(h) {
            let n = h.lastPathComponent
            if n.hasSuffix(".noindex") { modulos.append(h); continue }
            let partes = n.split(separator: "-")
            let proyecto = partes.count > 1 ? partes.dropLast().joined(separator: "-") : n
            let espacio = NSDictionary(contentsOf: h.appendingPathComponent("info.plist"))?["WorkspacePath"] as? String
            let existe = espacio.map { Rutas.existe($0) } ?? true
            r.append(Elemento(
                nombre: "DerivedData de \(proyecto)",
                detalle: "Compilación intermedia de Xcode" + (espacio.map { " para \(Formato.rutaCorta($0))." } ?? "."),
                consecuencia: existe ? "Xcode la regenera la próxima vez que compiles (esa compilación será más lenta)."
                                     : "Nada: el proyecto ya no existe.",
                rutas: [h], categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                motivos: [existe ? .bien("arrow.triangle.2.circlepath", "Se regenera", "Xcode la vuelve a crear al compilar.")
                                 : .bien("questionmark.folder.fill", "Proyecto borrado", "El proyecto al que pertenecía ya no existe.")],
                enUso: Self.xcodeUso, dueno: "Xcode"))
        }
        if !modulos.isEmpty {
            r.append(Elemento(
                nombre: "Caché de módulos de Xcode", detalle: "Módulos precompilados que comparten tus proyectos.",
                consecuencia: "Xcode los regenera al compilar.", rutas: modulos, categoria: .desarrollo,
                riesgo: .seguro, seleccionado: true,
                motivos: [.bien("arrow.triangle.2.circlepath", "Se regenera", "Xcode los vuelve a crear.")],
                enUso: Self.xcodeUso, dueno: "Xcode"))
        }
        for fecha in Rutas.hijos(Rutas.enHome("Library/Developer/Xcode/Archives")) where Rutas.esCarpeta(fecha) {
            for a in Rutas.hijos(fecha) where a.pathExtension == "xcarchive" {
                r.append(Elemento(
                    nombre: "Archivo de Xcode: \(a.deletingPathExtension().lastPathComponent) (\(fecha.lastPathComponent))",
                    detalle: "Una versión de tu app que archivaste para publicarla.",
                    consecuencia: "Ya no podrás volver a exportar esa versión ni leer bien sus informes de fallos.",
                    rutas: [a], categoria: .desarrollo, riesgo: .revisar,
                    motivos: [.aviso("ladybug.fill", "Símbolos de fallos",
                                     "Contiene los símbolos (dSYM) de esa versión: sirven para entender los informes de fallos de la app publicada.")],
                    dueno: "Xcode"))
            }
        }
        for tipo in ["iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport", "visionOS DeviceSupport"] {
            let versiones = Rutas.hijos(Rutas.enHome("Library/Developer/Xcode/\(tipo)")).filter { Rutas.esCarpeta($0) }
                .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
            for (i, v) in versiones.enumerated() {
                let ultima = i == versiones.count - 1
                r.append(Elemento(
                    nombre: "Soporte de dispositivo: \(v.lastPathComponent)",
                    detalle: "Símbolos que Xcode copió de un dispositivo que conectaste.",
                    consecuencia: "Si conectas un dispositivo con esa versión, Xcode los vuelve a copiar (tarda unos minutos).",
                    rutas: [v], categoria: .desarrollo, riesgo: .seguro, seleccionado: !ultima,
                    motivos: [ultima ? .info("iphone", "Versión más reciente", "Es la versión más nueva que conectaste.")
                                     : .bien("clock.arrow.circlepath", "Versión antigua", "Ya conectaste versiones más nuevas.")],
                    dueno: "Xcode"))
            }
        }
        return r
    }

    /// Playwright y Puppeteer guardan un navegador por versión: las antiguas sobran.
    private func navegadoresDePrueba() -> [Elemento] {
        var r: [Elemento] = []
        func versiones(_ lista: [URL], herramienta: String, navegador: String) {
            let orden = lista.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
            for (i, v) in orden.enumerated() {
                let ultima = i == orden.count - 1
                r.append(Elemento(
                    nombre: "\(herramienta): \(navegador) \(v.lastPathComponent)",
                    detalle: "Navegador que \(herramienta) descargó para pruebas automáticas.",
                    consecuencia: ultima ? "\(herramienta) lo vuelve a descargar cuando lo necesite." : "Nada: ya tienes una versión más nueva.",
                    rutas: [v], categoria: .desarrollo, riesgo: .seguro, seleccionado: !ultima,
                    motivos: [ultima ? .info("globe", "Versión actual", "Es la versión más reciente descargada.")
                                     : .bien("clock.arrow.circlepath", "Versión antigua", "Hay una versión más nueva de \(navegador).")],
                    dueno: herramienta))
            }
        }
        var porNavegador: [String: [URL]] = [:]
        for h in Rutas.hijos(Rutas.enHome("Library/Caches/ms-playwright")) where Rutas.esCarpeta(h) {
            let n = h.lastPathComponent
            guard let guion = n.lastIndex(of: "-") else { continue }
            porNavegador[String(n[..<guion]), default: []].append(h)
        }
        for (nav, lista) in porNavegador { versiones(lista, herramienta: "Playwright", navegador: nav) }
        for nav in Rutas.hijos(Rutas.enHome(".cache/puppeteer")) where Rutas.esCarpeta(nav) {
            versiones(Rutas.hijos(nav).filter { Rutas.esCarpeta($0) }, herramienta: "Puppeteer", navegador: nav.lastPathComponent)
        }
        return r
    }

    private static let patronIDE = try! NSRegularExpression(pattern: "^([A-Za-z]+?)(\\d{4}\\.\\d+(?:\\.\\d+)?)$")

    private static func versionIDE(_ nombre: String) -> (producto: String, version: String)? {
        guard let m = patronIDE.firstMatch(in: nombre, range: NSRange(nombre.startIndex..., in: nombre)),
              let rp = Range(m.range(at: 1), in: nombre), let rv = Range(m.range(at: 2), in: nombre) else { return nil }
        return (String(nombre[rp]), String(nombre[rv]))
    }

    /// Android Studio e IDEs de JetBrains dejan una carpeta por versión. Las de versiones anteriores sobran.
    private func versionesAnterioresDeIDEs() -> [Elemento] {
        var r: [Elemento] = []
        let lugares: [(String, String, Riesgo, Bool)] = [
            ("Library/Caches/Google", "Caché", .seguro, true), ("Library/Caches/JetBrains", "Caché", .seguro, true),
            ("Library/Logs/Google", "Registros", .seguro, true), ("Library/Logs/JetBrains", "Registros", .seguro, true),
            ("Library/Application Support/Google", "Configuración", .revisar, false),
            ("Library/Application Support/JetBrains", "Configuración", .revisar, false),
        ]
        for (rel, tipo, riesgo, sel) in lugares {
            var porProducto: [String: [(URL, String)]] = [:]
            for h in Rutas.hijos(Rutas.enHome(rel)) where Rutas.esCarpeta(h) {
                guard let (producto, version) = Self.versionIDE(h.lastPathComponent) else { continue }
                porProducto[producto, default: []].append((h, version))
            }
            for (producto, versiones) in porProducto where versiones.count > 1 {
                let orden = versiones.sorted { $0.1.compare($1.1, options: .numeric) == .orderedAscending }
                let actual = orden.last!.1
                let nombre = producto == "AndroidStudio" ? "Android Studio" : producto
                for (url, v) in orden.dropLast() {
                    r.append(Elemento(
                        nombre: "\(tipo) de \(nombre) \(v) (versión anterior)",
                        detalle: "\(tipo) de una versión de \(nombre) que ya actualizaste a la \(actual).",
                        consecuencia: tipo == "Configuración"
                            ? "Al actualizar, la versión \(actual) ya copió tus ajustes: esta copia antigua no se usa."
                            : "Nada: la versión \(actual) usa su propia carpeta.",
                        rutas: [url], categoria: .desarrollo, riesgo: riesgo, seleccionado: sel,
                        motivos: [.bien("clock.arrow.circlepath", "Versión anterior", "Ya usas \(nombre) \(actual).")],
                        dueno: nombre))
                }
            }
        }
        return r
    }

    // MARK: VS Code y derivados

    /// (carpeta en Application Support, carpeta oculta, nombre, identificador de la app)
    private static let editoresVSCode: [(soporte: String, oculta: String, nombre: String, id: String)] = [
        ("Code", ".vscode", "Visual Studio Code", "com.microsoft.VSCode"),
        ("Code - Insiders", ".vscode-insiders", "VS Code Insiders", "com.microsoft.VSCodeInsiders"),
        ("Cursor", ".cursor", "Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Windsurf", ".windsurf", "Windsurf", "com.exafunction.windsurf"),
        ("VSCodium", ".vscode-oss", "VSCodium", "com.vscodium"),
    ]

    /// VS Code y sus derivados: extensiones que ya no están instaladas, cachés de versiones anteriores
    /// y datos de proyectos que ya no existen.
    private func editores(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        for ed in Self.editoresVSCode {
            let uso = EnUso.app(nombre: ed.nombre, claves: [ed.id, ed.nombre])

            // 1. Extensiones: extensions.json dice exactamente cuáles están instaladas.
            let carpetaExt = Rutas.enHome(ed.oculta + "/extensions")
            if let instaladas = Self.extensionesInstaladas(en: carpetaExt) {
                let viejas = Rutas.hijos(carpetaExt).filter {
                    Rutas.esCarpeta($0) && !$0.lastPathComponent.hasPrefix(".") && !instaladas.contains($0.lastPathComponent)
                }
                if !viejas.isEmpty {
                    r.append(Elemento(
                        nombre: "Extensiones viejas de \(ed.nombre)",
                        detalle: "Versiones anteriores o desinstaladas: \(Formato.listaCorta(viejas.map(\.lastPathComponent).sorted(), maximo: 4)).",
                        consecuencia: "Nada: \(ed.nombre) ya usa otras versiones de esas extensiones o ya no las tiene instaladas.",
                        rutas: viejas, categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                        motivos: [.bien("puzzlepiece.extension.fill", "No instaladas",
                                        "Según la lista de extensiones de \(ed.nombre) (extensions.json), estas carpetas ya no se usan.")],
                        enUso: uso, dueno: ed.nombre))
                }
            }

            let soporte = Rutas.enHome("Library/Application Support/\(ed.soporte)")
            guard Rutas.esCarpeta(soporte) else { continue }

            // 2. Código precompilado de versiones anteriores del editor: se conserva la que se usó por última vez.
            let versiones = Rutas.hijos(soporte.appendingPathComponent("CachedData"))
                .filter { Rutas.esCarpeta($0) && Self.esHashDeVersion($0.lastPathComponent) }
                .sorted { (c.indice.masReciente(de: [$0]) ?? .distantPast) < (c.indice.masReciente(de: [$1]) ?? .distantPast) }
            if versiones.count > 1 {
                let viejas = Array(versiones.dropLast())
                r.append(Elemento(
                    nombre: "Caché de versiones anteriores de \(ed.nombre)",
                    detalle: "Código precompilado de \(viejas.count) \(viejas.count == 1 ? "versión anterior" : "versiones anteriores") del editor.",
                    consecuencia: "Nada: la versión actual usa su propia caché.",
                    rutas: viejas, categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                    motivos: [.bien("clock.arrow.circlepath", "Versiones anteriores", "\(ed.nombre) se actualizó y ya no usa estas carpetas.")],
                    enUso: uso, dueno: ed.nombre))
            }

            // 3. Paquetes (.vsix) de extensiones que ya están instaladas.
            let vsix = soporte.appendingPathComponent("CachedExtensionVSIXs")
            if Rutas.esCarpeta(vsix) {
                r.append(Elemento(
                    nombre: "Instaladores de extensiones de \(ed.nombre)",
                    detalle: "Copias de los paquetes (.vsix) de extensiones que ya instalaste.",
                    consecuencia: "Nada: las extensiones ya están instaladas; si hace falta, se vuelven a descargar.",
                    rutas: [vsix], categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                    motivos: [.bien("shippingbox.fill", "Ya instaladas", "Son copias de algo que ya está instalado.")],
                    enUso: uso, dueno: ed.nombre))
            }

            // 4. Estado guardado de proyectos cuya carpeta ya no existe.
            var huerfanos: [URL] = []
            var proyectos: [String] = []
            for w in Rutas.hijos(soporte.appendingPathComponent("User/workspaceStorage")) where Rutas.esCarpeta(w) {
                guard let ruta = Self.proyectoDeEspacio(w), !ruta.hasPrefix("/Volumes/"), !Rutas.existe(ruta) else { continue }
                huerfanos.append(w)
                proyectos.append(ruta)
            }
            if !huerfanos.isEmpty {
                r.append(Elemento(
                    nombre: "Datos de proyectos que ya no existen (\(ed.nombre))",
                    detalle: "Estado guardado de \(huerfanos.count) \(huerfanos.count == 1 ? "proyecto" : "proyectos") cuya carpeta ya no está: \(Formato.listaCorta(proyectos.map { Formato.rutaCorta($0) }, maximo: 3)).",
                    consecuencia: "Si alguno solo cambió de sitio, al abrirlo empezará sin sus pestañas ni el estado de sus extensiones (por ejemplo, el historial de chat).",
                    rutas: huerfanos, categoria: .desarrollo, riesgo: .revisar,
                    motivos: [.info("folder.badge.questionmark", "Proyectos borrados o movidos",
                                    "La carpeta de cada uno de esos proyectos ya no existe en este Mac.")],
                    enUso: uso, dueno: ed.nombre))
            }
        }
        return r
    }

    /// Las carpetas de extensiones instaladas, o `nil` si no se pudo saber (entonces no se ofrece nada).
    static func extensionesInstaladas(en carpeta: URL) -> Set<String>? {
        guard let datos = try? Data(contentsOf: carpeta.appendingPathComponent("extensions.json")),
              let lista = try? JSONSerialization.jsonObject(with: datos) as? [[String: Any]] else { return nil }
        var r = Set<String>()
        for e in lista {
            if let rel = e["relativeLocation"] as? String, !rel.isEmpty {
                r.insert(rel)
            } else if let ubicacion = e["location"] as? [String: Any],
                      let ruta = (ubicacion["path"] as? String) ?? (ubicacion["fsPath"] as? String) {
                r.insert((ruta as NSString).lastPathComponent)
            }
        }
        // Si hay extensiones en la lista pero no pude leer ninguna ubicación, el formato cambió: mejor no tocar nada.
        if !lista.isEmpty && r.isEmpty { return nil }
        // Las que el propio editor ya marcó como obsoletas (pendientes de borrar).
        if let datos = try? Data(contentsOf: carpeta.appendingPathComponent(".obsolete")),
           let obsoletas = try? JSONSerialization.jsonObject(with: datos) as? [String: Any] {
            r.subtract(obsoletas.keys)
        }
        return r
    }

    /// La carpeta del proyecto al que pertenece un workspaceStorage, si es local; `nil` si es remoto o no se sabe.
    static func proyectoDeEspacio(_ carpeta: URL) -> String? {
        guard let datos = try? Data(contentsOf: carpeta.appendingPathComponent("workspace.json")),
              let d = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let uri = (d["folder"] as? String) ?? (d["workspace"] as? String),
              let url = URL(string: uri), url.isFileURL, !url.path.isEmpty else { return nil }
        return url.path
    }

    /// Las cachés de VS Code se llaman como el commit de cada versión («a1b2c3d4…»).
    private static func esHashDeVersion(_ nombre: String) -> Bool {
        nombre.count >= 7 && nombre.allSatisfy { $0.isHexDigit }
    }

    // MARK: Homebrew y conda

    /// Versiones antiguas de fórmulas de Homebrew: lo mismo que borra «brew cleanup».
    private func homebrew() -> [Elemento] {
        var r: [Elemento] = []
        for prefijo in ["/opt/homebrew", "/usr/local"] {
            let cellar = URL(fileURLWithPath: prefijo + "/Cellar")
            guard Rutas.esCarpeta(cellar) else { continue }
            var viejas: [URL] = []
            var nombres: [String] = []
            for formula in Rutas.hijos(cellar) where Rutas.esCarpeta(formula) {
                let versiones = Rutas.hijos(formula).filter { Rutas.esCarpeta($0) && !$0.lastPathComponent.hasPrefix(".") }
                guard versiones.count > 1, access(formula.path, W_OK) == 0 else { continue }
                let n = formula.lastPathComponent
                // La versión en uso es a la que apunta opt/<fórmula>. Si no se sabe, no se toca nada.
                guard let actual = Self.destinoDeEnlace(prefijo + "/opt/" + n) else { continue }
                let fijada = Self.destinoDeEnlace(prefijo + "/var/homebrew/pinned/" + n)
                for v in versiones where v.lastPathComponent != actual && v.lastPathComponent != fijada {
                    viejas.append(v)
                    nombres.append("\(n) \(v.lastPathComponent)")
                }
            }
            guard !viejas.isEmpty else { continue }
            r.append(Elemento(
                nombre: "Versiones antiguas de Homebrew",
                detalle: "\(viejas.count) \(viejas.count == 1 ? "versión" : "versiones") que ya actualizaste: \(Formato.listaCorta(nombres.sorted(), maximo: 4)).",
                consecuencia: "Nada: Homebrew ya usa las versiones nuevas. Es lo mismo que hace «brew cleanup».",
                rutas: viejas, categoria: .desarrollo, riesgo: .seguro,
                motivos: [.bien("mug.fill", "Ya actualizadas", "Cada fórmula apunta a su versión nueva; estas ya no se usan.")],
                enUso: .proceso(nombre: "Homebrew", patron: "/library/homebrew/brew.rb"), dueno: "Homebrew"))
        }
        return r
    }

    /// «/opt/homebrew/opt/node» → «20.1.0» (la última parte de a dónde apunta el enlace).
    private static func destinoDeEnlace(_ ruta: String) -> String? {
        guard let destino = try? FileManager.default.destinationOfSymbolicLink(atPath: ruta) else { return nil }
        return (destino as NSString).lastPathComponent
    }

    /// Paquetes comprimidos que conda ya descomprimió (lo que borra «conda clean --tarballs»).
    private func conda() -> [Elemento] {
        var r: [Elemento] = []
        for raiz in ["miniconda3", "anaconda3", "miniforge3", "mambaforge", ".conda"] {
            let comprimidos = Rutas.hijos(Rutas.enHome(raiz + "/pkgs"))
                .filter { $0.lastPathComponent.hasSuffix(".tar.bz2") || $0.pathExtension == "conda" }
            guard !comprimidos.isEmpty else { continue }
            r.append(Elemento(
                nombre: "Descargas de conda (\(raiz))",
                detalle: "\(comprimidos.count) paquetes comprimidos que conda ya descomprimió.",
                consecuencia: "Nada: los paquetes ya están instalados. Es lo mismo que «conda clean --tarballs».",
                rutas: comprimidos, categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("archivebox.fill", "Ya descomprimidos", "Conda solo los necesita para instalar, y ya lo hizo.")],
                enUso: .proceso(nombre: "conda", patron: "/bin/conda"), dueno: "conda"))
        }
        return r
    }

    // MARK: - Cachés de aplicaciones

    private func cachesApps(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let caches = Rutas.enHome("Library/Caches")
        let deDesarrollo = Set(Self.cachesDeDesarrollo.map { Rutas.enHome($0.rel).path } + [caches.appendingPathComponent("ms-playwright").path])
        let omitir: Set<String> = ["CloudKit", "FamilyCircle", "GeoServices", "PassKit", "Animoji", "Google", "JetBrains"]

        for h in Rutas.hijos(caches) where Rutas.esCarpeta(h) {
            let n = h.lastPathComponent
            if n.hasPrefix("com.apple.") || n.hasPrefix(".") || deDesarrollo.contains(h.path) || omitir.contains(n)
                || Self.propios.contains(n) { continue }
            // Las cachés de apps desinstaladas se ofrecen junto al resto de lo que dejó esa app.
            guard c.apps.estaInstalado(carpeta: n) else { continue }
            let app = c.apps.nombreApp(para: n) ?? nombreBonito(n)
            r.append(cacheDeApp(app: app, clave: n, rutas: [h]))
        }
        // Google y JetBrains: una carpeta por programa y versión (las versiones viejas van en «desarrollo»).
        for vendedor in ["Google", "JetBrains"] {
            let hijos = Rutas.hijos(caches.appendingPathComponent(vendedor)).filter { Rutas.esCarpeta($0) }
            let actuales = Self.versionesActuales(hijos)
            for h in hijos {
                let n = h.lastPathComponent
                if Self.versionIDE(n) != nil && !actuales.contains(h) { continue }
                let esStudio = n.hasPrefix("AndroidStudio")
                let app = esStudio ? "Android Studio" : (c.apps.nombreApp(para: n) ?? n)
                r.append(cacheDeApp(app: app, clave: esStudio ? "com.google.android.studio" : n, rutas: [h]))
            }
        }

        // Cachés internas (Electron/Chromium) dentro de Application Support.
        let appSupport = Rutas.enHome("Library/Application Support").path + "/"
        var porApp: [String: [URL]] = [:]
        for (ruta, tipo) in c.indice.cachesInternas where tipo == .cache {
            guard let carpeta = ruta.dropFirst(appSupport.count).split(separator: "/").first.map(String.init) else { continue }
            porApp[carpeta, default: []].append(URL(fileURLWithPath: ruta))
        }
        for (carpeta, rutas) in porApp {
            guard !carpeta.hasPrefix("com.apple."), !Self.propios.contains(carpeta),
                  c.apps.estaInstalado(carpeta: carpeta) else { continue }
            let app = c.apps.nombreApp(para: carpeta) ?? carpeta
            let tipos = Array(Set(rutas.map(\.lastPathComponent))).sorted()
            r.append(Elemento(
                nombre: "Caché interna de \(app)",
                detalle: "Cachés que \(app) guarda junto a sus datos (\(Formato.listaCorta(tipos))).",
                consecuencia: "\(app) las vuelve a crear. Tus datos, sesiones y ajustes no se tocan.",
                rutas: rutas, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("arrow.triangle.2.circlepath", "Solo cachés", "Solo se borran las carpetas de caché, no los datos de \(app).")],
                enUso: .app(nombre: app, claves: [carpeta, app]), dueno: app))
        }

        // Apps de la App Store guardan su caché dentro de su contenedor.
        if c.accesoTotal {
            for contenedor in Rutas.hijos(Rutas.enHome("Library/Containers")) {
                let id = contenedor.lastPathComponent
                let cache = contenedor.appendingPathComponent("Data/Library/Caches")
                guard !id.hasPrefix("com.apple."), Rutas.existe(cache), c.apps.estaInstalado(carpeta: id) else { continue }
                let app = c.apps.nombreApp(para: id) ?? nombreBonito(id)
                r.append(cacheDeApp(app: app, clave: id, rutas: [cache]))
            }
            // Adjuntos que abriste desde Mail: copias, los originales siguen en tus correos.
            let adjuntos = Rutas.enHome("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
            if Rutas.esCarpeta(adjuntos) {
                r.append(Elemento(
                    nombre: "Adjuntos abiertos desde Mail",
                    detalle: "Copias de los adjuntos que abriste o previsualizaste desde Mail.",
                    consecuencia: "Los originales siguen en tus correos. Si editaste algún adjunto y lo guardaste aquí, esa sería la única copia: revísalo antes.",
                    rutas: [adjuntos], categoria: .cachesApps, riesgo: .revisar,
                    motivos: [.info("paperclip", "Copias de adjuntos", "Mail las crea cada vez que abres un adjunto y no las borra.")],
                    enUso: .app(nombre: "Mail", claves: ["com.apple.mail"]), dueno: "Mail"))
            }
        }
        return r
    }

    // MARK: - Temporales del sistema (/var/folders)

    /// Temporales y cachés que macOS guarda para tu usuario fuera de la carpeta personal.
    /// Solo se ofrece lo que ningún programa tiene abierto (según `lsof`); si no se puede saber, nada.
    private func temporales(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let abiertos = ArchivosAbiertos.capturar()
        guard abiertos.disponible else { return [] }
        let ahora = Date()

        if let t = Sistema.temporal {
            let enUso = abiertos.hijosEnUso(de: t)
            var viejos: [URL] = []
            for h in Rutas.hijos(URL(fileURLWithPath: t)) {
                let n = h.lastPathComponent
                // TemporaryItems guarda documentos a medio guardar: nunca se toca.
                guard !n.hasPrefix("."), n != "TemporaryItems", !enUso.contains(n),
                      c.procesos.appAbierta([n]) == nil else { continue }
                // De una carpeta pequeña el índice no guarda la actividad de lo de dentro: no se puede saber si se usa.
                if Rutas.esCarpeta(h) && c.indice.info(h.path) == nil { continue }
                let ultimo = c.indice.masReciente(de: [h]) ?? Fechas.modificacion(h) ?? ahora
                guard ahora.timeIntervalSince(ultimo) > 3 * 86400 else { continue }
                viejos.append(h)
            }
            if !viejos.isEmpty {
                r.append(Elemento(
                    nombre: "Temporales viejos de apps",
                    detalle: "\(viejos.count) carpetas y archivos temporales que las apps dejaron en \(Formato.rutaCorta(t)).",
                    consecuencia: "Nada: ningún programa los tiene abiertos y macOS los borraría al reiniciar.",
                    rutas: viejos, categoria: .temporales, riesgo: .seguro, seleccionado: true,
                    motivos: [.bien("clock.arrow.circlepath", "Sin uso", "Llevan más de 3 días sin cambios y nada los tiene abiertos ahora mismo.")]))
            }
        }

        if let cachesSistema = Sistema.caches {
            let enUso = abiertos.hijosEnUso(de: cachesSistema)
            var compilador: [URL] = []
            var deApps: [(url: URL, nombre: String, clave: String, instalada: Bool)] = []
            for h in Rutas.hijos(URL(fileURLWithPath: cachesSistema)) where Rutas.esCarpeta(h) {
                let n = h.lastPathComponent
                guard !n.hasPrefix("."), !enUso.contains(n) else { continue }
                if n == "clang" || n.hasPrefix("org.llvm.clang") || n == "com.apple.DeveloperTools" || n.hasPrefix("com.apple.dt.") {
                    compilador.append(h)
                } else if !n.hasPrefix("com.apple."), n.contains(".") {
                    let instalada = c.apps.estaInstalado(carpeta: n)
                    deApps.append((h, c.apps.nombreApp(para: n) ?? nombreBonito(n), n, instalada))
                }
            }
            if !compilador.isEmpty {
                r.append(Elemento(
                    nombre: "Cachés del compilador (Xcode y Clang)",
                    detalle: "Módulos precompilados de Clang y archivos temporales de las herramientas de Xcode.",
                    consecuencia: "Se regeneran en la próxima compilación (que irá algo más lenta).",
                    rutas: compilador, categoria: .temporales, riesgo: .seguro, seleccionado: true,
                    motivos: [.bien("arrow.triangle.2.circlepath", "Se regenera", "El compilador los vuelve a crear cuando los necesita.")],
                    enUso: Self.xcodeUso, dueno: "Xcode"))
            }
            for a in deApps {
                r.append(Elemento(
                    nombre: a.instalada ? "Caché de sistema de \(a.nombre)" : "Caché de sistema de una app borrada (\(a.nombre))",
                    detalle: "Caché que macOS guarda para \(a.nombre) fuera de tu carpeta personal.",
                    consecuencia: a.instalada ? "\(a.nombre) la vuelve a crear cuando la necesita." : "Nada: la app ya no está instalada.",
                    rutas: [a.url], categoria: .temporales, riesgo: .seguro, seleccionado: true,
                    motivos: [a.instalada ? .bien("arrow.triangle.2.circlepath", "Se regenera", "Es una caché: \(a.nombre) la reconstruye sola.")
                                          : .bien("magnifyingglass", "App no instalada", "No encontré la app a la que pertenece.")],
                    enUso: .app(nombre: a.nombre, claves: [a.clave, a.nombre]), dueno: a.nombre))
            }
        }
        return r
    }

    private func cacheDeApp(app: String, clave: String, rutas: [URL]) -> Elemento {
        Elemento(
            nombre: "Caché de \(app)",
            detalle: "Archivos temporales de \(app).",
            consecuencia: "\(app) los vuelve a crear cuando los necesita (al principio puede ir un poco más lenta).",
            rutas: rutas, categoria: .cachesApps, riesgo: .seguro, seleccionado: true,
            motivos: [.bien("arrow.triangle.2.circlepath", "Se regenera", "Es una caché: \(app) la reconstruye sola.")],
            enUso: .app(nombre: app, claves: [clave, app]), dueno: app)
    }

    private static func versionesActuales(_ carpetas: [URL]) -> Set<URL> {
        var porProducto: [String: (URL, String)] = [:]
        for u in carpetas {
            guard let (p, v) = versionIDE(u.lastPathComponent) else { continue }
            if let actual = porProducto[p], actual.1.compare(v, options: .numeric) != .orderedAscending { continue }
            porProducto[p] = (u, v)
        }
        return Set(porProducto.values.map(\.0))
    }

    // MARK: - Restos de apps desinstaladas

    private struct Resto {
        let url: URL
        let nombre: String
        let lugar: String
    }

    private func restos(_ c: Contexto) -> [Elemento] {
        var candidatos: [Resto] = []
        var lugares: [(String, String)] = [
            ("Library/Application Support", "Datos"), ("Library/Caches", "Caché"), ("Library/Logs", "Registros"),
            ("Library/Saved Application State", "Estado de ventanas"), ("Library/HTTPStorages", "Datos web"),
            ("Library/WebKit", "Datos web"), ("Library/Application Scripts", "Scripts"),
        ]
        if c.accesoTotal {
            lugares += [("Library/Containers", "Contenedor"), ("Library/Group Containers", "Contenedor compartido")]
        }
        for (rel, lugar) in lugares {
            for h in Rutas.hijos(Rutas.enHome(rel)) {
                let n = h.lastPathComponent
                if n.hasPrefix(".") || Self.propios.contains(n) { continue }
                let clave = n.replacingOccurrences(of: ".savedState", with: "")
                if c.apps.estaInstalado(carpeta: clave) { continue }
                candidatos.append(Resto(url: h, nombre: clave, lugar: lugar))
            }
        }
        for p in Rutas.hijos(Rutas.enHome("Library/Preferences")) where p.pathExtension == "plist" {
            let id = p.deletingPathExtension().lastPathComponent
            guard id.split(separator: ".").count >= 3, !Self.propios.contains(id),
                  !c.apps.estaInstalado(carpeta: p.lastPathComponent) else { continue }
            candidatos.append(Resto(url: p, nombre: id, lugar: "Preferencias"))
        }
        var reubicados: [URL] = []
        for h in Rutas.hijos(URL(fileURLWithPath: "/Users/Shared")) {
            let n = h.lastPathComponent
            if n.hasPrefix(".") || n == "SC Info" { continue }
            if n.hasPrefix("Previously Relocated Items") || n == "Relocated Items" { reubicados.append(h); continue }
            if c.apps.estaInstalado(carpeta: n) { continue }
            candidatos.append(Resto(url: h, nombre: n, lugar: "Carpeta compartida"))
        }
        // Agentes de inicio: los que abren un programa que ya no existe, o uno que está dentro de otro resto.
        var agentes = Set<String>()
        let rutasRestos = candidatos.map { $0.url.path }
        for p in Rutas.hijos(Rutas.enHome("Library/LaunchAgents")) where p.pathExtension == "plist" {
            guard let d = NSDictionary(contentsOf: p) else { continue }
            let programa = (d["Program"] as? String) ?? (d["ProgramArguments"] as? [String])?.first
            guard let programa, programa.hasPrefix("/") else { continue }
            let huerfano = !Rutas.existe(programa)
            let dentroDeResto = rutasRestos.contains { programa.hasPrefix($0 + "/") }
            guard huerfano || dentroDeResto else { continue }
            let etiqueta = (d["Label"] as? String) ?? p.deletingPathExtension().lastPathComponent
            candidatos.append(Resto(url: p, nombre: etiqueta, lugar: "Agente de inicio"))
            agentes.insert(p.path)
        }

        var r: [Elemento] = []
        var sueltas: [URL] = []
        for grupo in agrupar(candidatos) {
            if grupo.count == 1 && grupo[0].lugar == "Preferencias" { sueltas.append(grupo[0].url); continue }
            let nombre = nombreDeGrupo(grupo, c)
            let rutas = grupo.map(\.url)
            let lugaresGrupo = Array(Set(grupo.map { $0.lugar.lowercased() })).sorted()
            var motivos: [Motivo] = [
                .bien("magnifyingglass", "No está instalada",
                      "No encontré \(nombre) en Aplicaciones, ni en Homebrew, ni entre los programas abiertos."),
            ]
            if grupo.contains(where: { agentes.contains($0.url.path) }) {
                motivos.append(.bien("power", "Agente de inicio",
                                     "Incluye un agente que se ejecuta cada vez que enciendes el Mac. También lo desactivo al limpiar."))
            }
            if grupo.contains(where: { $0.lugar == "Carpeta compartida" && Rutas.hijos($0.url).contains { $0.pathExtension == "app" } }) {
                motivos.append(.info("app.dashed", "App escondida",
                                     "Dentro hay una app instalada fuera de Aplicaciones (los juegos suelen hacerlo). Si ya no la usas, sobra junto con sus datos."))
            }
            if let actividad = c.indice.masReciente(de: rutas) {
                let dias = Date().timeIntervalSince(actividad) / 86400
                if dias < 7 {
                    motivos.append(.aviso("clock.fill", "Actividad reciente",
                                          "Tuvo actividad \(Formato.haceCuanto(actividad).lowercased()): puede que algún programa todavía lo use."))
                } else if dias > 60 {
                    motivos.append(.bien("moon.zzz.fill", "Sin uso", "Nadie lo ha tocado desde \(Formato.haceCuanto(actividad).lowercased())."))
                }
            }
            r.append(Elemento(
                nombre: nombre,
                detalle: grupo.count == 1
                    ? "\(grupo[0].lugar) de un programa que ya no está instalado."
                    : "Lo que dejó \(nombre) en \(grupo.count) lugares: \(Formato.lista(lugaresGrupo)).",
                consecuencia: "No afecta a ninguna app instalada. Si algún día reinstalas \(nombre), empezará sin tu configuración anterior.",
                rutas: rutas, categoria: .restos, riesgo: .revisar, motivos: motivos,
                enUso: .app(nombre: nombre, claves: grupo.map(\.nombre) + [nombre]), dueno: nombre))
        }
        if !sueltas.isEmpty {
            r.append(Elemento(
                nombre: "Preferencias de \(sueltas.count) apps desinstaladas",
                detalle: Formato.listaCorta(sueltas.map { $0.deletingPathExtension().lastPathComponent }, maximo: 5),
                consecuencia: "Nada: son ajustes de apps que ya no tienes.",
                rutas: sueltas, categoria: .restos, riesgo: .revisar,
                motivos: [.bien("magnifyingglass", "Apps no instaladas", "Ninguna de estas apps está instalada.")]))
        }
        for h in reubicados {
            r.append(Elemento(
                nombre: h.lastPathComponent,
                detalle: "Archivos que macOS apartó durante una actualización del sistema.",
                consecuencia: "Normalmente no hacen falta, pero revisa su contenido antes.",
                rutas: [h], categoria: .restos, riesgo: .revisar,
                motivos: [.info("arrow.up.bin.fill", "Actualización de macOS", "macOS los movió aquí porque no encajaban tras actualizar.")]))
        }
        return r
    }

    /// Agrupa los restos que pertenecen a la misma app («Riot Client», «Riot Games», «com.riotgames…»).
    private func agrupar(_ restos: [Resto]) -> [[Resto]] {
        let genericos: Set<String> = ["google", "microsoft", "apple", "github", "adobe", "jetbrains", "mozilla",
                                      "electron", "openai", "amazon", "facebook", "meta"]
        // «group.com.x.y» y «EQUIPO.x» se agrupan por lo que hay detrás del prefijo, no por «com» ni por el Team ID.
        let identificadores = restos.map { AppsInstaladas.sinPrefijoDeGrupo($0.nombre) }
        var planas = Set<String>()
        for id in identificadores where id.split(separator: ".").count < 3 { planas.insert(clavePlana(id)) }
        let claves: [String] = identificadores.map { id in
            let partes = id.lowercased().split(separator: ".").map(String.init)
            guard partes.count >= 3 else { return clavePlana(id) }
            if let ultima = partes.last.map(AppsInstaladas.normalizar), planas.contains(ultima) { return ultima }
            let fabricante = AppsInstaladas.normalizar(partes[1])
            return genericos.contains(fabricante) ? fabricante + AppsInstaladas.normalizar(partes[2]) : fabricante
        }
        let unicas = Set(claves).sorted { $0.count < $1.count }
        var raiz: [String: String] = [:]
        for k in unicas {
            if let corta = unicas.first(where: { $0.count >= 4 && $0 != k && k.hasPrefix($0) }) {
                raiz[k] = raiz[corta] ?? corta
            } else {
                raiz[k] = k
            }
        }
        var grupos: [String: [Resto]] = [:]
        for (i, r) in restos.enumerated() { grupos[raiz[claves[i]] ?? claves[i], default: []].append(r) }
        return Array(grupos.values)
    }

    private func clavePlana(_ nombre: String) -> String {
        let palabras = nombre.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if let primera = palabras.first, primera.count >= 4 { return AppsInstaladas.normalizar(String(primera)) }
        return AppsInstaladas.normalizar(nombre)
    }

    private func nombreDeGrupo(_ grupo: [Resto], _ c: Contexto) -> String {
        func id(_ r: Resto) -> String { AppsInstaladas.sinPrefijoDeGrupo(r.nombre) }
        let planos = grupo.filter { id($0).split(separator: ".").count < 3 && $0.lugar != "Agente de inicio" }
        if let mayor = planos.max(by: { c.indice.bytes(de: $0.url) < c.indice.bytes(de: $1.url) }) { return id(mayor) }
        let partes = id(grupo[0]).split(separator: ".")
        if partes.count >= 3 { return String(partes[1]).capitalized }
        return id(grupo[0])
    }

    // MARK: - Proyectos

    private func proyectos(_ c: Contexto) -> [Elemento] {
        var porProyecto: [String: [Artefacto]] = [:]
        for a in c.indice.artefactos { porProyecto[raizDeProyecto(a.ruta, c), default: []].append(a) }

        var r: [Elemento] = []
        for (raiz, artefactos) in porProyecto {
            let nombre = Rutas.nombre(raiz)
            var regenerables = artefactos.filter { $0.tipo != .venv }
            let venvs = artefactos.filter { $0.tipo == .venv }
            // Lo que está guardado en git no es compilación (por ejemplo, un build/ con recursos hechos a mano).
            var versionadas: [String] = []
            if c.indice.repos.contains(raiz), !regenerables.isEmpty {
                let conArchivos = carpetasVersionadas(raiz, regenerables.map(\.ruta))
                versionadas = regenerables.filter { conArchivos.contains($0.ruta) }.map { String($0.ruta.dropFirst(raiz.count + 1)) }
                regenerables.removeAll { conArchivos.contains($0.ruta) }
            }

            var actividad = c.indice.masRecientePropio(de: raiz)
            if c.indice.repos.contains(raiz), let commit = ultimoCommit(raiz) {
                actividad = max(actividad ?? commit, commit)
            }
            let dias = actividad.map { Date().timeIntervalSince($0) / 86400 } ?? 999

            if !regenerables.isEmpty {
                let urls = regenerables.map { URL(fileURLWithPath: $0.ruta) }
                var motivos: [Motivo] = [.bien("arrow.triangle.2.circlepath", "Se regenera",
                                               "Tu código no se toca: solo se borran carpetas que se vuelven a generar.")]
                if let actividad {
                    motivos.append(dias > 30
                        ? .bien("moon.zzz.fill", "Proyecto inactivo", "No cambias el código desde \(Formato.haceCuanto(actividad).lowercased()).")
                        : .info("pencil", "Proyecto activo", "Cambiaste el código \(Formato.haceCuanto(actividad).lowercased())."))
                }
                if let compilado = c.indice.masReciente(de: urls), Date().timeIntervalSince(compilado) < 3600 {
                    motivos.append(.aviso("hammer.fill", "Compilado hace poco",
                                          "Se compiló hace menos de una hora: quizá lo tengas abierto en el editor."))
                }
                if !versionadas.isEmpty {
                    motivos.append(.info("lock.doc.fill", "Dejé fuera lo versionado",
                                         "No incluyo \(Formato.lista(versionadas)): tiene archivos guardados en git, así que no es solo compilación."))
                }
                let relativas = regenerables.map { String($0.ruta.dropFirst(raiz.count + 1)) }.sorted()
                r.append(Elemento(
                    nombre: nombre,
                    detalle: "\(tipoDeProyecto(raiz)) · \(Formato.listaCorta(relativas, maximo: 4))",
                    consecuencia: consecuenciaProyecto(regenerables),
                    rutas: urls, ultimoUso: actividad, categoria: .proyectos, riesgo: .seguro,
                    seleccionado: dias > 30, motivos: motivos, dueno: nombre))
            }
            for v in venvs {
                r.append(Elemento(
                    nombre: "\(nombre) › \(Rutas.nombre(v.ruta))",
                    detalle: "Entorno virtual de Python con los paquetes del proyecto.",
                    consecuencia: "Tendrás que volver a crearlo e instalar los paquetes (pip install -r requirements.txt).",
                    rutas: [URL(fileURLWithPath: v.ruta)], ultimoUso: actividad, categoria: .proyectos, riesgo: .revisar,
                    motivos: [.info("shippingbox.fill", "Se puede recrear", "Se reconstruye, pero tendrás que reinstalar los paquetes.")],
                    dueno: nombre))
            }
        }
        return r
    }

    /// La carpeta del proyecto: el repositorio git que contiene el artefacto o, si no hay, la raíz de Gradle.
    private func raizDeProyecto(_ artefacto: String, _ c: Contexto) -> String {
        let home = Rutas.home.path
        var actual = Rutas.padre(artefacto)
        var candidata = actual
        while actual.count > home.count, Rutas.padre(actual) != home {
            if c.indice.repos.contains(actual) { return actual }
            if Rutas.existe(actual + "/settings.gradle") || Rutas.existe(actual + "/settings.gradle.kts") { candidata = actual }
            actual = Rutas.padre(actual)
        }
        return candidata
    }

    /// Cuáles de estas carpetas tienen archivos guardados en el repositorio (`git ls-files`).
    private func carpetasVersionadas(_ repo: String, _ carpetas: [String]) -> Set<String> {
        let relativas = carpetas.map { String($0.dropFirst(repo.count + 1)) }
        let salida = Shell.ejecutar("/usr/bin/git", ["-C", repo, "ls-files", "-z", "--"] + relativas, limite: 15).salida
        var r = Set<String>()
        for archivo in salida.split(separator: "\0") {
            for (i, rel) in relativas.enumerated() where archivo.hasPrefix(rel + "/") { r.insert(carpetas[i]) }
        }
        return r
    }

    private func ultimoCommit(_ repo: String) -> Date? {
        let s = Shell.ejecutar("/usr/bin/git", ["-C", repo, "log", "-1", "--format=%ct"], limite: 5).salida
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(s).map { Date(timeIntervalSince1970: $0) }
    }

    private func tipoDeProyecto(_ raiz: String) -> String {
        func hay(_ a: String) -> Bool { Rutas.existe(raiz + "/" + a) }
        if hay("pubspec.yaml") { return "Flutter" }
        if hay("settings.gradle") || hay("settings.gradle.kts") || hay("build.gradle") || hay("build.gradle.kts") { return "Android" }
        if hay("app.json") && hay("package.json") { return "React Native / Expo" }
        if hay("Podfile") || hay("Package.swift") { return "iOS / Swift" }
        if hay("package.json") { return "Node.js" }
        if hay("Cargo.toml") { return "Rust" }
        if hay("pyproject.toml") || hay("requirements.txt") { return "Python" }
        return "Proyecto"
    }

    private func consecuenciaProyecto(_ a: [Artefacto]) -> String {
        var partes: [String] = []
        if a.contains(where: { $0.tipo == .node }) { partes.append("tendrás que ejecutar «npm install» antes de volver a usarlo") }
        if a.contains(where: { [.compilacion, .gradle, .cxx, .kotlin].contains($0.tipo) }) {
            partes.append("la próxima compilación tardará más porque se hace desde cero")
        }
        if a.contains(where: { $0.tipo == .pods }) { partes.append("tendrás que ejecutar «pod install»") }
        if partes.isEmpty { partes.append("se vuelve a generar la próxima vez que lo compiles") }
        return "Tu código no se toca; " + Formato.lista(partes) + "."
    }

    // MARK: - Carpetas ocultas de herramientas

    private static let ocultasConocidas: Set<String> = [
        ".Trash", ".ssh", ".gnupg", ".config", ".local", ".cache", ".npm", ".gradle", ".android", ".m2",
        ".cargo", ".rustup", ".nvm", ".vscode", ".zsh_sessions", ".docker", ".kube", ".aws", ".azure",
        ".oh-my-zsh", ".claude", ".git", ".cups", ".bun", ".pyenv", ".rbenv", ".sdkman", ".swiftpm",
        ".expo", ".cocoapods", ".yarn", ".pub-cache", ".nuget", ".ollama", ".CFUserTextEncoding", ".DS_Store",
        // Se analizan aparte (cachés de desarrollo, VS Code y derivados).
        ".dartServer", ".skiko", ".vscode-insiders", ".vscode-oss", ".cursor", ".windsurf", ".conda",
    ]

    private enum ClaseSubcarpeta { case temporal, registros, reinstalable, personal }

    private func clasificarSubcarpeta(_ nombre: String) -> ClaseSubcarpeta? {
        let n = nombre.lowercased()
        if ["cache", "caches", ".cache", "tmp", ".tmp", "temp", "crashpad", "crash-reports", "crashes"].contains(n) { return .temporal }
        // «logs», «log-2024», «server.log»… pero no «login» ni «logic».
        if n == "logs" || n == "log" || n.hasPrefix("logs") || n.hasPrefix("log-") || n.hasPrefix("log_")
            || n.hasSuffix(".log") { return .registros }
        if ["sessions", "history", "conversations", "chats", "threads", "memories", "memory", "projects",
            "workspaces", "archived_sessions"].contains(n) || n.contains("history") || n.hasSuffix(".sqlite") || n.hasSuffix(".db") {
            return .personal
        }
        if ["node_modules", "packages", "runtimes", "versions", "bin", "lib", "plugins", "extensions", "downloads",
            "models", "vendor", "tools", "sdk", "toolchains"].contains(n) {
            return .reinstalable
        }
        return nil
    }

    private func herramientas(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        for h in Rutas.hijos(Rutas.home) {
            let n = h.lastPathComponent
            guard n.hasPrefix("."), Rutas.esCarpeta(h), !Self.ocultasConocidas.contains(n) else { continue }
            let herramienta = String(n.dropFirst())
            if Rutas.existe(h.appendingPathComponent("pyvenv.cfg")) {
                r.append(Elemento(
                    nombre: n,
                    detalle: "Entorno virtual de Python con paquetes instalados.",
                    consecuencia: "Los programas que lo usen dejarán de funcionar hasta que lo vuelvas a crear e instales sus paquetes.",
                    rutas: [h], categoria: .herramientas, riesgo: .revisar,
                    motivos: [.info("shippingbox.fill", "Se puede recrear", "Es un entorno de Python: se reconstruye con python -m venv y pip install.")],
                    dueno: "Python"))
                continue
            }
            let comando = c.apps.comandoPara(carpetaOculta: n)
            let traeSuPrograma = Rutas.esCarpeta(h.appendingPathComponent("bin"))
            let instalado = comando != nil || traeSuPrograma || c.apps.estaInstalado(carpeta: herramienta)
            let ultimo = c.indice.masReciente(de: [h])
            let dias = ultimo.map { Date().timeIntervalSince($0) / 86400 } ?? 9999
            let uso = EnUso.proceso(nombre: herramienta, patron: "/\(n.lowercased())/")

            var motivos: [Motivo] = []
            let riesgo: Riesgo
            if instalado {
                let como = comando.map { " (comando «\($0)»)" } ?? (traeSuPrograma ? " (trae su propio programa)" : "")
                motivos.append(.aviso("wrench.and.screwdriver.fill", "Herramienta instalada",
                    "Es la carpeta de una herramienta que sigue instalada\(como). Si la borras, perderás su configuración e historial."))
                riesgo = .cuidado
            } else if dias < 30 {
                motivos.append(.aviso("clock.fill", "Uso reciente",
                    "Se usó \(Formato.haceCuanto(ultimo).lowercased()): probablemente la herramienta sigue en uso aunque no encontré su comando."))
                riesgo = .cuidado
            } else {
                motivos.append(.bien("questionmark.folder.fill", "Posible resto",
                    "Lleva \(Formato.haceCuanto(ultimo).lowercased().replacingOccurrences(of: "hace ", with: "")) sin usarse y no encontré el programa que la creó."))
                riesgo = .revisar
            }
            r.append(Elemento(
                nombre: n,
                detalle: instalado ? "Configuración, historial y datos de \(herramienta)." : "Carpeta que dejó alguna herramienta.",
                consecuencia: instalado ? "Perderás la configuración, sesiones e historial de \(herramienta)."
                                        : "Si la herramienta se vuelve a usar, empezará de cero.",
                rutas: [h], categoria: .herramientas, riesgo: riesgo, motivos: motivos, enUso: uso, dueno: herramienta))

            // Por dentro: separar lo temporal de lo personal.
            guard (c.indice.info(h.path)?.bytes ?? 0) >= 50_000_000 else { continue }
            var subs: [(URL, Int64)] = c.indice.hijosOrdenados(de: h.path).map { (URL(fileURLWithPath: $0.ruta), $0.bytes) }
            subs += c.indice.grandes.filter { $0.carpeta == h.path }.map { ($0.url, $0.bytes) }
            for (sub, bytes) in subs where bytes >= 20_000_000 {
                guard let clase = clasificarSubcarpeta(sub.lastPathComponent) else { continue }
                let s = sub.lastPathComponent
                switch clase {
                case .temporal, .registros:
                    let esRegistro = clase == .registros
                    r.append(Elemento(
                        nombre: "\(n) › \(s)",
                        detalle: esRegistro ? "Registros de \(herramienta)." : "Archivos temporales de \(herramienta).",
                        consecuencia: esRegistro ? "Nada: solo se pierden registros antiguos." : "\(herramienta) los vuelve a crear.",
                        rutas: [sub], categoria: .herramientas, riesgo: .seguro, seleccionado: true,
                        motivos: [.bien("arrow.triangle.2.circlepath", esRegistro ? "Solo registros" : "Temporal",
                                        "No contiene tu configuración ni tu historial.")],
                        enUso: uso, dueno: herramienta))
                case .reinstalable:
                    r.append(Elemento(
                        nombre: "\(n) › \(s)",
                        detalle: "Componentes descargados por \(herramienta).",
                        consecuencia: "\(herramienta) puede dejar de funcionar hasta que los vuelvas a instalar o descargar.",
                        rutas: [sub], categoria: .herramientas, riesgo: .revisar,
                        motivos: [.info("arrow.down.circle.fill", "Se reinstala", "Se pueden volver a descargar.")],
                        enUso: uso, dueno: herramienta))
                case .personal:
                    r.append(Elemento(
                        nombre: "\(n) › \(s)",
                        detalle: "Historial o datos guardados de \(herramienta).",
                        consecuencia: "Perderás el historial (sesiones, conversaciones o proyectos) de \(herramienta).",
                        rutas: [sub], categoria: .herramientas, riesgo: .cuidado,
                        motivos: [.aviso("clock.arrow.circlepath", "Tu historial", "Son sesiones, conversaciones o datos que creaste con \(herramienta).")],
                        enUso: uso, dueno: herramienta))
                }
            }
        }
        return r
    }

    // MARK: - Instaladores

    private func instaladores(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        let montadas = imagenesMontadas()
        // «AvisoYape-1.7.apk» es más nueva que «AvisoYape-1.2.apk»: se agrupan por nombre sin versión.
        var masNueva: [String: (ruta: String, version: String)] = [:]
        for a in c.indice.instaladores {
            guard let (base, version) = Self.nombreYVersion(a.url) else { continue }
            let clave = a.carpeta + "|" + base
            if let actual = masNueva[clave], actual.version.compare(version, options: .numeric) != .orderedAscending { continue }
            masNueva[clave] = (a.ruta, version)
        }
        for a in c.indice.instaladores {
            let url = a.url
            let ext = url.pathExtension.lowercased()
            let fecha = Fechas.ultimoUsoArchivo(url) ?? a.fecha
            let dias = Date().timeIntervalSince(fecha) / 86400
            var motivos: [Motivo] = []
            var riesgo = Riesgo.revisar
            var seleccionado = false
            let detalle: String
            if ext == "apk" || ext == "xapk" || ext == "ipa" {
                detalle = ext == "ipa" ? "Instalador de una app de iPhone." : "Instalador de una app de Android."
                motivos.append(.info("iphone", "App para el teléfono", "Sirve para instalar la app en un teléfono, emulador o simulador."))
            } else if ext == "ipsw" {
                detalle = "Firmware de iPhone o iPad (sirve para restaurar el dispositivo)."
                motivos.append(.info("iphone.gen3", "Firmware", "El Finder lo vuelve a descargar si alguna vez restauras el dispositivo."))
            } else {
                detalle = "Instalador."
                // Se compara el nombre completo del programa («Google Earth Pro»), nunca solo la primera palabra.
                let base = Self.nombreBase(url.deletingPathExtension().lastPathComponent)
                let versionArchivo = Self.nombreYVersion(url)?.1
                if let app = c.apps.appParaInstalador(base) {
                    if let va = versionArchivo, let vi = app.version, va.compare(vi, options: .numeric) == .orderedDescending {
                        motivos.append(.aviso("arrow.up.circle.fill", "Más nuevo que el instalado",
                                              "Este instalador es la versión \(va) y tienes instalada la \(vi): quizá todavía no lo instalaste."))
                    } else {
                        let version = app.version.map { " \($0)" } ?? ""
                        motivos.append(.bien("checkmark.circle.fill", "Ya está instalada",
                                             "Ya tienes \(app.nombre)\(version) instalada: este instalador ya no hace falta."))
                        riesgo = .seguro
                        seleccionado = dias > 3
                    }
                } else {
                    let quien = base.isEmpty ? "el programa" : "«\(base)»"
                    motivos.append(.info("questionmark.app.fill", "No lo veo instalado",
                                         "No encontré \(quien) entre tus apps. Si todavía no lo instalaste, guárdalo."))
                }
            }
            if let (base, _) = Self.nombreYVersion(url), let nueva = masNueva[a.carpeta + "|" + base], nueva.ruta != a.ruta {
                motivos.append(.bien("arrow.up.circle.fill", "Hay una versión más nueva",
                                     "Al lado tienes \(Rutas.nombre(nueva.ruta)), que es más reciente."))
            }
            var montada: String? = nil
            if let m = montadas[a.ruta] {
                montada = m.dispositivo
                motivos.append(.info("externaldrive.fill", "Montado", "Está abierto como disco «\(m.volumen)». Lo expulsaré antes de borrarlo."))
            }
            r.append(Elemento(
                nombre: url.lastPathComponent,
                detalle: "\(detalle) En \(Formato.rutaCorta(url.deletingLastPathComponent())).",
                consecuencia: "Si necesitas volver a instalarlo, tendrás que descargarlo otra vez.",
                rutas: [url], ultimoUso: fecha, categoria: .instaladores, riesgo: riesgo, seleccionado: seleccionado,
                motivos: motivos, imagenMontada: montada))
        }
        // Copias sueltas de apps que ya están en Aplicaciones. Solo sobran si son la misma versión.
        for ruta in c.indice.apps {
            let url = URL(fileURLWithPath: ruta)
            guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                  let id = (info["CFBundleIdentifier"] as? String)?.lowercased(),
                  c.apps.idsEnAplicaciones.contains(id) else { continue }
            let nombre = url.deletingPathExtension().lastPathComponent
            let version = info["CFBundleShortVersionString"] as? String
            let instalada = c.apps.versionEnAplicaciones[id]
            let mismaVersion = version != nil && version == instalada
            r.append(Elemento(
                nombre: "Copia de \(nombre)",
                detalle: "Una copia de \(nombre)\(version.map { " \($0)" } ?? "") en \(Formato.rutaCorta(url.deletingLastPathComponent())).",
                consecuencia: mismaVersion ? "Nada: seguirás usando la que está en Aplicaciones."
                                           : "Perderás esta versión; seguirás teniendo la \(instalada ?? "otra") en Aplicaciones.",
                rutas: [url], categoria: .instaladores, riesgo: mismaVersion ? .seguro : .revisar, seleccionado: mismaVersion,
                motivos: [mismaVersion
                    ? .bien("checkmark.circle.fill", "Ya está en Aplicaciones", "Tienes la misma versión (\(version ?? "")) en Aplicaciones: esta copia sobra.")
                    : .info("square.on.square", "Otra versión",
                            "Esta copia es la \(version ?? "?") y en Aplicaciones tienes la \(instalada ?? "?"). Si la guardas a propósito (una beta, una versión anterior), no la borres.")],
                enUso: .app(nombre: nombre, claves: [id]), dueno: nombre))
        }

        // Firmware de iPhone y iPad que el Finder descargó para actualizar o restaurar.
        var firmware: [URL] = []
        for carpeta in ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"] {
            firmware += Rutas.hijos(Rutas.enHome("Library/iTunes/" + carpeta)).filter { $0.pathExtension.lowercased() == "ipsw" }
        }
        if !firmware.isEmpty {
            r.append(Elemento(
                nombre: "Firmware de iPhone y iPad descargado",
                detalle: "\(firmware.count) \(firmware.count == 1 ? "archivo" : "archivos") de sistema que el Finder descargó para actualizar o restaurar un dispositivo.",
                consecuencia: "Nada: el Finder lo vuelve a descargar si alguna vez restauras el dispositivo.",
                rutas: firmware, categoria: .instaladores, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("iphone.gen3", "Ya se usó", "El dispositivo ya se actualizó; el Finder no los necesita guardados.")],
                dueno: "Finder"))
        }

        // Instaladores de macOS en Aplicaciones (más de 12 GB cada uno).
        let sistemaActual = ProcessInfo.processInfo.operatingSystemVersion
        for app in Rutas.hijos(URL(fileURLWithPath: "/Applications"))
        where app.lastPathComponent.hasPrefix("Install macOS ") && app.pathExtension == "app" {
            let nombre = app.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Install ", with: "")
            r.append(Elemento(
                nombre: "Instalador de \(nombre)",
                detalle: "El instalador completo de \(nombre). Tu Mac tiene macOS \(sistemaActual.majorVersion).\(sistemaActual.minorVersion).",
                consecuencia: "Si lo necesitas para crear un USB de instalación, tendrás que volver a descargarlo de la App Store.",
                rutas: [app], categoria: .instaladores, riesgo: .revisar,
                motivos: [.info("arrow.down.app.fill", "Se puede volver a descargar",
                                "Solo hace falta para instalar macOS en otro Mac o crear un USB de arranque.")],
                dueno: "macOS"))
        }
        return r
    }

    /// «AvisoYape-1.7.apk» → («avisoyape», «1.7»)
    private static func nombreYVersion(_ url: URL) -> (String, String)? {
        let n = url.deletingPathExtension().lastPathComponent
        guard let r = n.range(of: #"[-_ ]v?(\d+(\.\d+)+)"#, options: .regularExpression) else { return nil }
        let version = n[r].trimmingCharacters(in: CharacterSet(charactersIn: "-_ v"))
        let base = AppsInstaladas.normalizar(String(n[..<r.lowerBound])) + "." + url.pathExtension.lowercased()
        return (base, version)
    }

    /// El nombre completo del programa, sin versión ni arquitectura:
    /// «Google Earth Pro 7.3.6 (arm64)» → «googleearthpro», «Cline_0.0.36_universal» → «cline»,
    /// «zoomusInstallerFull» → «zoomus».
    static func nombreBase(_ archivo: String) -> String {
        let ruido: Set<String> = ["universal", "arm", "arm64", "aarch64", "x64", "x86", "amd64", "intel", "mac", "macos",
                                  "osx", "darwin", "setup", "installer", "install", "instalador", "latest", "stable",
                                  "beta", "release", "build", "apple", "silicon", "dmg", "pkg", "full", "signed",
                                  "for", "de", "para"]
        let sufijos = ["installerfull", "installer", "install", "setup", "universal", "full"]
        var palabras: [String] = []
        for (i, trozo) in archivo.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).enumerated() {
            var t = trozo.lowercased()
            // La versión empieza en el primer número suelto («7», «v2», «2024»): ahí termina el nombre.
            let esNumero = t.allSatisfy { $0.isNumber }
            let esVersion = esNumero || (t.count > 1 && t.hasPrefix("v") && t.dropFirst().allSatisfy { $0.isNumber })
            if esVersion {
                if i > 0 { break }
                continue
            }
            if ruido.contains(t) { continue }
            for s in sufijos where t.count > s.count + 2 && t.hasSuffix(s) { t = String(t.dropLast(s.count)) }
            palabras.append(t)
        }
        return AppsInstaladas.normalizar(palabras.joined())
    }

    private func imagenesMontadas() -> [String: (dispositivo: String, volumen: String)] {
        let salida = Shell.ejecutar("/usr/bin/hdiutil", ["info", "-plist"], limite: 15).salida
        guard let datos = salida.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: datos, format: nil) as? [String: Any],
              let imagenes = plist["images"] as? [[String: Any]] else { return [:] }
        var r: [String: (String, String)] = [:]
        for img in imagenes {
            guard let ruta = img["image-path"] as? String,
                  let entidades = img["system-entities"] as? [[String: Any]] else { continue }
            let disco = entidades.compactMap { $0["dev-entry"] as? String }.min(by: { $0.count < $1.count })
            let punto = entidades.compactMap { $0["mount-point"] as? String }.first
            if let disco { r[ruta] = (disco, punto.map { Rutas.nombre($0) } ?? disco) }
        }
        return r
    }

    // MARK: - Registros

    private func registros(_ c: Contexto) -> [Elemento] {
        var r: [Elemento] = []
        for h in Rutas.hijos(Rutas.enHome("Library/Logs")) {
            let n = h.lastPathComponent
            if n.hasPrefix(".") || Self.propios.contains(n) || !c.apps.estaInstalado(carpeta: n) { continue }
            let app: String? = n == "DiagnosticReports" ? nil : (c.apps.nombreApp(para: n) ?? nombreBonito(n))
            r.append(Elemento(
                nombre: app.map { "Registros de \($0)" } ?? "Reportes de fallos",
                detalle: app.map { "Archivos de registro de \($0)." } ?? "Informes que macOS guarda cuando una app se cierra de golpe.",
                consecuencia: "Nada importante: solo se pierden registros y errores antiguos.",
                rutas: [h], categoria: .registros, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("doc.text.magnifyingglass", "Solo registros", "Sirven para diagnosticar errores; se crean nuevos cuando hace falta.")],
                enUso: app.map { .app(nombre: $0, claves: [n, $0]) }, dueno: app))
        }
        // Registros que las apps guardan dentro de sus datos (…/Application Support/App/logs).
        let appSupport = Rutas.enHome("Library/Application Support").path + "/"
        var porApp: [String: [URL]] = [:]
        for (ruta, tipo) in c.indice.cachesInternas where tipo == .registros {
            guard let carpeta = ruta.dropFirst(appSupport.count).split(separator: "/").first.map(String.init) else { continue }
            porApp[carpeta, default: []].append(URL(fileURLWithPath: ruta))
        }
        for (carpeta, rutas) in porApp {
            guard !carpeta.hasPrefix("com.apple."), !Self.propios.contains(carpeta), c.apps.estaInstalado(carpeta: carpeta) else { continue }
            let app = c.apps.nombreApp(para: carpeta) ?? carpeta
            r.append(Elemento(
                nombre: "Registros internos de \(app)",
                detalle: "Registros y reportes de fallos que \(app) guarda junto a sus datos.",
                consecuencia: "Nada importante: solo se pierden registros antiguos.",
                rutas: rutas, categoria: .registros, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("doc.text.magnifyingglass", "Solo registros", "No contienen tus datos.")],
                enUso: .app(nombre: app, claves: [carpeta, app]), dueno: app))
        }
        return r
    }

    // MARK: - Papelera

    private func papelera() -> [Elemento] {
        let trash = Rutas.enHome(".Trash")
        guard let contenido = try? FileManager.default.contentsOfDirectory(atPath: trash.path),
              case let visibles = contenido.filter({ $0 != ".DS_Store" }), !visibles.isEmpty else { return [] }
        // El índice no entra en la Papelera: se mide aparte.
        return [Elemento(
            nombre: "Contenido de la Papelera (\(visibles.count) \(visibles.count == 1 ? "elemento" : "elementos"))",
            detalle: "Lo que ya enviaste a la Papelera.",
            consecuencia: "Se borra para siempre: ya no podrás recuperarlo. Lo que mandes a la Papelera en esta misma limpieza no se toca.",
            rutas: [trash], tamanoFijo: Limpiador.tamanoPapelera(), categoria: .papelera, riesgo: .revisar,
            accion: .vaciarPapelera,
            motivos: [.info("trash.fill", "Ya descartado", "Son cosas que tú mismo enviaste a la Papelera.")])]
    }

    // MARK: - Duplicados

    private func duplicados(_ c: Contexto) -> [Elemento] {
        let descargas = Rutas.enHome("Downloads").path + "/"
        var porTamano: [Int64: [ArchivoIndexado]] = [:]
        for a in c.indice.duplicables { porTamano[a.tamano, default: []].append(a) }

        var r: [Elemento] = []
        for (_, grupo) in porTamano where grupo.count > 1 {
            // Dos nombres para el mismo archivo (enlaces) no son duplicados.
            var vistos = Set<String>()
            let unicos = grupo.filter { vistos.insert("\($0.dispositivo):\($0.inodo)").inserted }
            guard unicos.count > 1 else { continue }

            var porParcial: [String: [ArchivoIndexado]] = [:]
            for a in unicos { if let h = Huella.parcial(a.url, tamano: a.tamano) { porParcial[h, default: []].append(a) } }
            for (_, candidatos) in porParcial where candidatos.count > 1 {
                var porHash: [String: [ArchivoIndexado]] = [:]
                for a in candidatos { if let h = Huella.sha256(a.url) { porHash[h, default: []].append(a) } }
                for (_, iguales) in porHash where iguales.count > 1 {
                    // Los clones de APFS comparten el espacio: borrar uno no libera nada.
                    var porContenido: [Int64: String] = [:]
                    let reales = iguales.filter { a in
                        let v = try? a.url.resourceValues(forKeys: [.fileContentIdentifierKey])
                        guard let id = (v?.allValues[.fileContentIdentifierKey] as? NSNumber)?.int64Value else { return true }
                        if let otro = porContenido[id] {
                            c.memoria.clones[a.ruta] = otro
                            c.memoria.clones[otro] = a.ruta
                            return false
                        }
                        porContenido[id] = a.ruta
                        return true
                    }
                    guard reales.count > 1 else { continue }
                    let ordenadas = reales.sorted {
                        let (a, b) = (puntaje($0), puntaje($1))
                        return a != b ? a > b : $0.modificado < $1.modificado
                    }
                    let original = ordenadas[0]
                    for copia in ordenadas.dropFirst() {
                        var motivos: [Motivo] = [
                            .bien("doc.on.doc.fill", "Hay otra copia",
                                  "Se conserva la copia de \(Formato.rutaCorta(original.carpeta)), idéntica byte a byte."),
                        ]
                        if reales.count > 2 {
                            motivos.append(.info("square.stack.fill", "\(reales.count) copias", "Hay \(reales.count) copias idénticas de este archivo."))
                        }
                        if copia.ruta.contains("/Music/Music/") || copia.ruta.contains("/iTunes/") {
                            motivos.append(.aviso("music.note", "Biblioteca de Música",
                                                  "Está dentro de la biblioteca de la app Música: si lo borras aquí, la canción quedará rota en la app. Mejor bórrala desde Música."))
                        }
                        r.append(Elemento(
                            nombre: copia.nombre,
                            detalle: "Copia idéntica de \(Formato.rutaCorta(original.ruta)).",
                            consecuencia: "Se borra solo esta copia; la de \(Formato.rutaCorta(original.carpeta)) se conserva.",
                            rutas: [copia.url], ultimoUso: copia.fecha, categoria: .duplicados, riesgo: .revisar,
                            seleccionado: copia.ruta.hasPrefix(descargas) && !original.ruta.hasPrefix(descargas),
                            motivos: motivos, conservar: original.ruta))
                    }
                }
            }
        }
        return r
    }

    /// Qué copia conviene conservar: la que está ordenada (Música, Documentos…) y no parece una copia.
    private func puntaje(_ a: ArchivoIndexado) -> Int {
        let home = Rutas.home.path
        var s = 0
        for (carpeta, valor) in [("/Music/", 3), ("/Pictures/", 3), ("/Movies/", 3), ("/Documents/", 2), ("/Desktop/", 1), ("/Downloads/", -3)]
        where a.ruta.hasPrefix(home + carpeta) { s += valor }
        let n = a.nombre.lowercased()
        if n.contains(" copy") || n.contains(" copia") || n.range(of: #"\(\d+\)"#, options: .regularExpression) != nil { s -= 2 }
        return s
    }

    // MARK: - Archivos grandes

    private func grandes(_ c: Contexto, ofrecidas: [String]) -> [Elemento] {
        let descargas = Rutas.enHome("Downloads").path + "/"
        let instaladores: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "apk", "xapk", "ipa", "ipsw"]
        let comprimidos: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst"]
        func cubierta(_ ruta: String) -> Bool { ofrecidas.contains { ruta == $0 || ruta.hasPrefix($0 + "/") } }

        var r: [Elemento] = []
        var vistos = Set<String>()
        let candidatos = c.indice.grandes + c.indice.comprimidos.filter { $0.bytes >= 20_000_000 }
        for a in candidatos where vistos.insert(a.ruta).inserted {
            let ext = a.url.pathExtension.lowercased()
            if instaladores.contains(ext) { continue }
            let extraido = comprimidos.contains(ext) ? carpetaExtraida(a.url) : nil
            switch a.zona {
            case .personal, .compartida:
                let limite: Int64 = a.ruta.hasPrefix(descargas) ? 50_000_000 : 100_000_000
                guard a.bytes >= limite || extraido != nil else { continue }
            case .library, .oculta, .sistema:
                guard a.bytes >= 500_000_000, !cubierta(a.ruta), !a.ruta.contains("/com.apple.") else { continue }
            }

            let tipo = describirTipo(ext)
            var motivos: [Motivo] = []
            var riesgo = Riesgo.cuidado
            var detalle = "\(tipo) en \(Formato.rutaCorta(a.carpeta))."
            var consecuencia = "Se borra el archivo. Si te arrepientes, puedes recuperarlo de la Papelera antes de vaciarla."
            var dueno: String? = nil

            if a.zona == .library || a.zona == .oculta {
                dueno = duenoDeRuta(a.ruta, c)
                let quien = dueno ?? "una app"
                detalle = "Archivo interno de \(quien) (\(tipo.lowercased()))."
                consecuencia = "\(quien) puede fallar o tener que volver a descargarlo."
                motivos.append(.aviso("app.badge.fill", "Datos de \(quien)",
                                      "Es parte de los datos de \(quien). Revisa desde la propia app si puedes liberarlo."))
            }
            if a.ruta.contains("/Music/Music/") || a.ruta.contains("/iTunes/") {
                motivos.append(.aviso("music.note", "Biblioteca de Música",
                                      "Está dentro de la biblioteca de la app Música: si lo borras aquí, la canción quedará rota en la app. Mejor bórrala desde Música."))
            }
            if let extraido {
                motivos.append(.bien("archivebox.fill", "Ya descomprimido", "Ya existe la carpeta «\(extraido)» con su contenido."))
                riesgo = .revisar
                consecuencia = "La carpeta «\(extraido)» se queda; solo se borra el archivo comprimido."
            }
            r.append(Elemento(
                nombre: a.nombre, detalle: detalle, consecuencia: consecuencia, rutas: [a.url],
                ultimoUso: Fechas.ultimoUsoArchivo(a.url) ?? a.fecha, categoria: .grandes, riesgo: riesgo,
                motivos: motivos, dueno: dueno))
        }

        // Copias de seguridad de iPhone/iPad (solo se ven con Acceso total al disco).
        for b in Rutas.hijos(Rutas.enHome("Library/Application Support/MobileSync/Backup")) where Rutas.esCarpeta(b) {
            let info = NSDictionary(contentsOf: b.appendingPathComponent("Info.plist"))
            let nombre = info?["Device Name"] as? String ?? "iPhone/iPad"
            r.append(Elemento(
                nombre: "Copia de seguridad de \(nombre)",
                detalle: "Copia local completa de un dispositivo.",
                consecuencia: "Si pierdes o cambias el dispositivo, no podrás restaurarlo desde esta copia.",
                rutas: [b], ultimoUso: info?["Last Backup Date"] as? Date, categoria: .grandes, riesgo: .cuidado,
                motivos: [.aviso("iphone", "Copia de seguridad", "Bórrala solo si ya tienes otra copia (por ejemplo, en iCloud).")]))
        }
        return r
    }

    /// Si al lado de «fotos.zip» existe la carpeta «fotos», ya se descomprimió.
    private func carpetaExtraida(_ url: URL) -> String? {
        var base = url.deletingPathExtension()
        if base.pathExtension.lowercased() == "tar" { base = base.deletingPathExtension() }
        return Rutas.esCarpeta(base) ? base.lastPathComponent : nil
    }

    private func describirTipo(_ ext: String) -> String {
        switch ext {
        case "mp4", "mov", "m4v", "avi", "mkv", "webm", "mts": return "Vídeo"
        case "mp3", "m4a", "wav", "aiff", "flac", "aac": return "Audio"
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst": return "Archivo comprimido"
        case "vmdk", "vdi", "qcow2", "img", "raw", "utm", "hdd": return "Disco virtual"
        case "gguf", "safetensors", "onnx", "mlmodel", "pt", "pth", "ckpt": return "Modelo de IA"
        case "sqlite", "db", "realm": return "Base de datos"
        case "pdf", "psd", "ai", "key", "pages", "numbers", "docx", "xlsx", "pptx": return "Documento"
        case "jpg", "jpeg", "heic", "png", "tiff", "dng": return "Imagen"
        default: return "Archivo"
        }
    }

    private func duenoDeRuta(_ ruta: String, _ c: Contexto) -> String? {
        let home = Rutas.home.path
        for base in ["/Library/Application Support/", "/Library/Containers/", "/Library/Caches/", "/Library/Group Containers/"] {
            let prefijo = home + base
            if ruta.hasPrefix(prefijo), let carpeta = ruta.dropFirst(prefijo.count).split(separator: "/").first {
                return c.apps.nombreApp(para: String(carpeta)) ?? String(carpeta)
            }
        }
        if ruta.hasPrefix(home + "/."), let carpeta = ruta.dropFirst(home.count + 2).split(separator: "/").first {
            return String(carpeta)
        }
        return nil
    }

    // MARK: - Utilidades

    /// "com.google.Chrome" -> "Chrome (com.google.Chrome)"
    private func nombreBonito(_ n: String) -> String {
        let partes = n.split(separator: ".")
        if partes.count >= 3, let ultima = partes.last { return "\(ultima) (\(n))" }
        return n
    }
}
