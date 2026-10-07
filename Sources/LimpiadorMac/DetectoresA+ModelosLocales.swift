import Foundation

/// Modelos locales de IA por partes: Ollama (y Msty, que trae su propio Ollama), LM Studio, GPT4All y los modelos que
/// otras apps guardan entre sus datos. En vez de ofrecer cada carpeta entera, separa lo que sobra seguro (descargas a
/// medias, trozos que ya no usa ningún modelo) de lo que conviene revisar (cada modelo por separado).
extension Escaner {
    func detectoresA_ModelosLocales(_ c: Contexto) -> [Elemento] {
        Self.modelosLocalesTodos(c, home: Rutas.home)
    }

    /// Lo mismo, con la carpeta personal como parámetro (para probarlo sobre una carpeta de prueba).
    static func modelosLocalesTodos(_ c: Contexto, home: URL) -> [Elemento] {
        modelosLocalesOllama(c, home: home) + modelosLocalesLMStudio(c, home: home)
            + modelosLocalesGPT4All(c, home: home) + modelosLocalesEnApps(c, home: home)
    }

    // MARK: - Ollama

    /// Un manifiesto de Ollama: su ruta dentro de manifests/ (registro, espacio, modelo y etiqueta) y los blobs que usa.
    struct ModelosLocalesManifiesto {
        let url: URL
        let partes: [String]
        let blobs: Set<String>
    }

    /// Ollama guarda cada modelo como un manifiesto (manifests/<registro>/<espacio>/<modelo>/<etiqueta>) que apunta a
    /// sus trozos en blobs/. Msty 1.x trae su propio Ollama y guarda los modelos igual.
    static func modelosLocalesOllama(_ c: Contexto, home: URL) -> [Elemento] {
        // Sin la lista de procesos no se sabe si Ollama está descargando algo: no se ofrece nada.
        guard !c.procesos.lineas.isEmpty else { return [] }
        var r: [Elemento] = []
        let raiz = modelosLocalesRaizOllama(home: home)
        if !c.procesos.lineas.contains(where: { $0.contains("ollama") }) {
            r += modelosLocalesOllamaElementos(raiz: raiz, home: home, app: "Ollama", entera: true,
                                               uso: .proceso(nombre: "Ollama", patron: "ollama"))
        }
        let msty = home.appendingPathComponent("Library/Application Support/Msty/models")
        if msty.standardizedFileURL.path != raiz.standardizedFileURL.path,
           modelosLocalesEsCarpetaReal(msty.appendingPathComponent("blobs")),
           modelosLocalesEsCarpetaReal(msty.appendingPathComponent("manifests")),
           c.apps.estaInstalado(carpeta: "Msty"), !c.procesos.lineas.contains(where: { $0.contains("msty") }) {
            r += modelosLocalesOllamaElementos(raiz: msty, home: home, app: "Msty", entera: false,
                                               uso: .app(nombre: "Msty", claves: ["Msty"]))
        }
        return r
    }

    /// La carpeta de modelos de Ollama: la de OLLAMA_MODELS si es una carpeta de tu carpeta personal; si no, la de siempre.
    static func modelosLocalesRaizOllama(home: URL) -> URL {
        if let propia = ProcessInfo.processInfo.environment["OLLAMA_MODELS"],
           let u = modelosLocalesDentro(propia, home: home), modelosLocalesEsCarpetaReal(u) {
            return u
        }
        return home.appendingPathComponent(".ollama/models")
    }

    /// Lo que sobra en una carpeta con la estructura de Ollama (blobs/ y manifests/): descargas a medias, trozos que
    /// ningún modelo usa y cada modelo descargado por separado. `entera`: si la lista de modelos no se puede leer,
    /// se ofrece la carpeta completa para revisar (solo la de Ollama).
    static func modelosLocalesOllamaElementos(raiz: URL, home: URL, app: String, entera: Bool, uso: EnUso,
                                              ahora: Date = Date()) -> [Elemento] {
        let carpetaBlobs = raiz.appendingPathComponent("blobs")
        guard modelosLocalesEsCarpetaReal(raiz), modelosLocalesEsCarpetaReal(carpetaBlobs),
              let nombres = try? FileManager.default.contentsOfDirectory(atPath: carpetaBlobs.path) else { return [] }
        let haceUnaHora = ahora.addingTimeInterval(-3600)
        var parciales: [URL] = []
        var quietos: [URL] = []          // trozos completos que llevan más de 1 h sin cambios
        var existentes = Set<String>()   // trozos completos que hay en blobs/
        for n in nombres.sorted() where !n.hasPrefix(".") {
            let u = carpetaBlobs.appendingPathComponent(n)
            guard let fecha = modelosLocalesFechaDeArchivo(u) else { continue }   // solo archivos normales
            if modelosLocalesEsNombreDeBlob(n) {
                existentes.insert(n)
                if fecha < haceUnaHora { quietos.append(u) }
            } else if n.contains("-partial") && fecha < haceUnaHora {
                parciales.append(u)
            }
        }

        var r: [Elemento] = []
        let esOllama = app == "Ollama"
        parciales = parciales.filter { modelosLocalesOfrecible($0, home: home) }
        if !parciales.isEmpty {
            r.append(Elemento(
                nombre: "Descargas a medias de \(app)",
                detalle: "Trozos de modelos que empezaste a descargar y no terminaron.",
                consecuencia: "Nada: son descargas que no terminaron; si vuelves a pedir el modelo, se descarga de nuevo.",
                rutas: parciales, categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("arrow.down.circle.dotted", "Descargas a medias", "Llevan más de una hora sin avanzar.")],
                enUso: uso, dueno: app))
        }

        // Si algún manifiesto no se puede leer, no se sabe qué trozos usa cada modelo: ni restos ni modelos sueltos.
        guard let manifiestos = modelosLocalesManifiestos(en: raiz.appendingPathComponent("manifests")) else {
            if entera && modelosLocalesOfrecible(raiz, home: home) {
                r.append(Elemento(
                    nombre: "Modelos de Ollama", detalle: "Modelos de IA descargados con Ollama.",
                    consecuencia: "Tendrás que volver a descargarlos con «ollama pull» (pueden ser varios GB).",
                    rutas: [raiz], categoria: .desarrollo, riesgo: .revisar,
                    motivos: [.aviso("exclamationmark.triangle.fill", "Lista ilegible",
                                     "No pude leer la lista de modelos, así que no sé qué partes sobran.")],
                    enUso: uso, dueno: app))
            }
            return r
        }

        // Cuántos manifiestos usan cada trozo (también los que no se ofrecen, como los modelos creados a mano).
        var usos: [String: Int] = [:]
        for m in manifiestos {
            for b in m.blobs { usos[b, default: 0] += 1 }
        }
        let huerfanos = quietos.filter { usos[$0.lastPathComponent] == nil && modelosLocalesOfrecible($0, home: home) }
        if !huerfanos.isEmpty {
            r.append(Elemento(
                nombre: "Restos de modelos borrados de \(app)",
                detalle: "Trozos de modelos que ya borraste: ningún modelo los usa.",
                consecuencia: esOllama ? "Nada: ningún modelo los usa (Ollama los borraría al arrancar)."
                                       : "Nada: ningún modelo los usa.",
                rutas: huerfanos, categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("checkmark.circle.fill", "Sin usar", "Ninguno de los modelos de \(app) los usa.")],
                enUso: uso, dueno: app))
        }

        for m in manifiestos.sorted(by: { $0.url.path < $1.url.path }) {
            // Los de otros registros (modelos creados con «ollama create») pueden ser la única copia: nunca se ofrecen.
            guard let nombre = modelosLocalesNombreOllama(m.partes), modelosLocalesOfrecible(m.url, home: home) else { continue }
            // Con el manifiesto van solo los trozos que no comparte con otro modelo (lo mismo que hace «ollama rm»).
            let propios = m.blobs.filter { usos[$0] == 1 && existentes.contains($0) }.sorted()
                .map { carpetaBlobs.appendingPathComponent($0) }
                .filter { modelosLocalesOfrecible($0, home: home) }
            let consecuencia = esOllama
                ? "Si lo vuelves a necesitar, descárgalo con «ollama pull \(nombre)» (puede ocupar varios GB)."
                : "Si lo vuelves a necesitar, descárgalo otra vez desde \(app) (puede ocupar varios GB)."
            r.append(Elemento(
                nombre: "Modelo de \(app): \(nombre)",
                detalle: "Modelo de IA descargado con \(app). Solo se borran las partes que no comparte con otros modelos.",
                consecuencia: consecuencia,
                rutas: [m.url] + propios, categoria: .desarrollo, riesgo: .revisar,
                motivos: [.info("arrow.down.circle.fill", "Se vuelve a descargar", consecuencia)],
                enUso: uso, dueno: app))
        }
        return r
    }

    /// Todos los manifiestos (cada archivo bajo manifests/, sin ocultos), o `nil` si alguno no se puede leer o no tiene
    /// la forma esperada: entonces no se sabe qué trozos usa cada modelo.
    static func modelosLocalesManifiestos(en carpeta: URL) -> [ModelosLocalesManifiesto]? {
        var r: [ModelosLocalesManifiesto] = []
        var pendientes: [(url: URL, partes: [String])] = [(url: carpeta, partes: [])]
        var vistos = 0
        while let actual = pendientes.popLast() {
            guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: actual.url.path) else { return nil }
            for n in nombres {
                vistos += 1
                // Algo tan grande o tan profundo no es una carpeta normal de Ollama.
                guard vistos <= 20_000, actual.partes.count < 8 else { return nil }
                let u = actual.url.appendingPathComponent(n)
                var st = stat()
                guard lstat(u.path, &st) == 0 else { return nil }
                let tipo = st.st_mode & S_IFMT
                if n.hasPrefix(".") {
                    // .DS_Store y otros archivos ocultos no son manifiestos; una carpeta oculta, no se sabe qué es.
                    if tipo == S_IFREG { continue }
                    return nil
                }
                if tipo == S_IFDIR {
                    pendientes.append((url: u, partes: actual.partes + [n]))
                } else if tipo == S_IFREG, st.st_size <= 1_000_000, let blobs = modelosLocalesBlobsDe(manifiesto: u) {
                    r.append(ModelosLocalesManifiesto(url: u, partes: actual.partes + [n], blobs: blobs))
                } else {
                    return nil   // ilegible, demasiado grande, un enlace u otra cosa que no se entiende
                }
            }
        }
        return r
    }

    /// Los trozos («sha256-<hex>») que usa un manifiesto: el de su configuración y los de sus capas. `nil` si no se entiende.
    static func modelosLocalesBlobsDe(manifiesto u: URL) -> Set<String>? {
        guard let datos = try? Data(contentsOf: u),
              let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let capas = json["layers"] as? [[String: Any]],
              let config = json["config"] as? [String: Any],
              let digest = config["digest"] as? String, let blob = modelosLocalesBlob(deDigest: digest) else { return nil }
        var r: Set<String> = [blob]
        for capa in capas {
            guard let d = capa["digest"] as? String, let b = modelosLocalesBlob(deDigest: d) else { return nil }
            r.insert(b)
        }
        return r
    }

    /// «sha256:<64 hex>» → «sha256-<64 hex>», el nombre del trozo en blobs/. `nil` si no tiene esa forma.
    static func modelosLocalesBlob(deDigest d: String) -> String? {
        guard d.hasPrefix("sha256:") else { return nil }
        let hex = String(d.dropFirst(7))
        return modelosLocalesEsHex64(hex) ? "sha256-" + hex : nil
    }

    /// «sha256-» y 64 cifras hexadecimales en minúsculas: un trozo completo (sin «-partial»).
    static func modelosLocalesEsNombreDeBlob(_ n: String) -> Bool {
        n.hasPrefix("sha256-") && modelosLocalesEsHex64(String(n.dropFirst(7)))
    }

    private static func modelosLocalesEsHex64(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }

    /// El nombre con el que se pide el modelo («llama3:8b», «ana/modelo:latest», «hf.co/espacio/modelo:Q4_K_M»).
    /// `nil` si no está en registro/espacio/modelo/etiqueta o no es de registry.ollama.ai ni de hf.co.
    static func modelosLocalesNombreOllama(_ partes: [String]) -> String? {
        guard partes.count == 4 else { return nil }
        let espacio = partes[1], modelo = partes[2], etiqueta = partes[3]
        switch partes[0] {
        case "registry.ollama.ai": return espacio == "library" ? "\(modelo):\(etiqueta)" : "\(espacio)/\(modelo):\(etiqueta)"
        case "hf.co": return "hf.co/\(espacio)/\(modelo):\(etiqueta)"
        default: return nil
        }
    }

    // MARK: - LM Studio

    /// «llama.cpp-mac-arm64-apple-metal-advsimd-1.27.0» → motor «llama.cpp-mac-arm64-apple-metal-advsimd», versión «1.27.0».
    private static let modelosLocalesPatronMotor = try! NSRegularExpression(pattern: "^(.+)-(\\d+\\.\\d+\\.\\d+)$")

    /// LM Studio: versiones anteriores de sus motores y lo que quedó de una instalación anterior en su otra carpeta.
    static func modelosLocalesLMStudio(_ c: Contexto, home: URL) -> [Elemento] {
        let instalado = c.apps.bundleIDs.contains("ai.elementlabs.lmstudio") || c.apps.estaInstalado(carpeta: "LM Studio")
        // Solo con LM Studio cerrado y sin su comando «lms» en marcha (si no se sabe qué está en marcha, nada).
        guard instalado, !c.procesos.lineas.isEmpty,
              c.procesos.appAbierta(["ai.elementlabs.lmstudio", "LM Studio"]) == nil,
              !c.procesos.lineas.contains(where: { $0.contains("/bin/lms") }),
              let activo = modelosLocalesHogarLMStudio(home: home) else { return [] }
        let uso = EnUso.app(nombre: "LM Studio", claves: ["ai.elementlabs.lmstudio", "LM Studio"])
        var r: [Elemento] = []

        let motores = modelosLocalesMotoresSobrantes(en: activo.appendingPathComponent("extensions/backends"))
            .filter { modelosLocalesOfrecible($0, home: home) }
        if !motores.isEmpty {
            r.append(Elemento(
                nombre: "Versiones anteriores de los motores de LM Studio",
                detalle: "Motores que LM Studio ya actualizó: \(Formato.listaCorta(motores.map(\.lastPathComponent))).",
                consecuencia: "LM Studio usa la versión más nueva de cada motor; si eliges una anterior en sus ajustes, la vuelve a descargar.",
                rutas: motores, categoria: .desarrollo, riesgo: .revisar,
                motivos: [.info("clock.arrow.circlepath", "Versiones anteriores", "De cada motor se conserva la versión más nueva.")],
                enUso: uso, dueno: "LM Studio"))
        }

        let anteriores = modelosLocalesExtensionesAnteriores(activo: activo, home: home)
            .filter { modelosLocalesOfrecible($0, home: home) }
        if !anteriores.isEmpty {
            let donde = Formato.lista(anteriores.map { Formato.rutaCorta($0.deletingLastPathComponent()) })
            r.append(Elemento(
                nombre: "Componentes de una instalación anterior de LM Studio",
                detalle: "Motores y extensiones que dejó una versión anterior de LM Studio en \(donde).",
                consecuencia: "LM Studio ya usa otra carpeta (\(Formato.rutaCorta(activo))). Tus modelos y conversaciones no se tocan.",
                rutas: anteriores, categoria: .desarrollo, riesgo: .revisar,
                motivos: [.info("folder.badge.questionmark", "Carpeta anterior",
                                "LM Studio guarda ahora sus datos en \(Formato.rutaCorta(activo)).")],
                enUso: uso, dueno: "LM Studio"))
        }
        return r
    }

    /// La carpeta que usa LM Studio, buscada como la busca él: la que dice ~/.lmstudio-home-pointer o, sin ese archivo,
    /// ~/.cache/lm-studio si existe (versiones antiguas) y si no ~/.lmstudio. `nil` si el puntero no lleva a una carpeta
    /// que exista dentro de tu carpeta personal.
    static func modelosLocalesHogarLMStudio(home: URL) -> URL? {
        let puntero = home.appendingPathComponent(".lmstudio-home-pointer")
        if Rutas.existeSinSeguir(puntero.path) {
            guard let texto = try? String(contentsOf: puntero, encoding: .utf8),
                  let u = modelosLocalesDentro(texto.trimmingCharacters(in: .whitespacesAndNewlines), home: home),
                  modelosLocalesEsCarpetaReal(u) else { return nil }
            return u
        }
        let cache = home.appendingPathComponent(".cache/lm-studio")
        return Rutas.existe(cache) ? cache : home.appendingPathComponent(".lmstudio")
    }

    /// Versiones de motores que sobran en extensions/backends: de cada motor se conserva la versión más alta.
    /// Sin «vendor», carpetas ocultas, enlaces ni carpetas sin versión. Si no se puede leer, ninguna.
    static func modelosLocalesMotoresSobrantes(en backends: URL) -> [URL] {
        guard modelosLocalesEsCarpetaReal(backends),
              let nombres = try? FileManager.default.contentsOfDirectory(atPath: backends.path) else { return [] }
        var grupos: [String: [(url: URL, version: [Int])]] = [:]
        for n in nombres where !n.hasPrefix(".") && n != "vendor" {
            let u = backends.appendingPathComponent(n)
            guard modelosLocalesEsCarpetaReal(u),
                  let m = modelosLocalesPatronMotor.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)),
                  let rp = Range(m.range(at: 1), in: n), let rv = Range(m.range(at: 2), in: n) else { continue }
            let partes = n[rv].split(separator: ".")
            let version = partes.compactMap { Int($0) }
            guard version.count == partes.count else { continue }
            grupos[String(n[rp]), default: []].append((url: u, version: version))
        }
        var r: [URL] = []
        for lista in grupos.values where lista.count > 1 {
            let orden = lista.sorted { $0.version.lexicographicallyPrecedes($1.version) }
            r += orden.dropLast().map { $0.url }
        }
        return r.sorted { $0.path < $1.path }
    }

    /// La carpeta «extensions» de la otra carpeta de LM Studio (~/.lmstudio o ~/.cache/lm-studio) cuando ya no es la
    /// que usa. Nunca sus modelos, conversaciones, archivos ni ajustes. Nada si los ajustes de LM Studio no se entienden
    /// o guardan los modelos en esa otra carpeta.
    static func modelosLocalesExtensionesAnteriores(activo: URL, home: URL) -> [URL] {
        var descargas: String?
        let ajustes = activo.appendingPathComponent("settings.json")
        if Rutas.existeSinSeguir(ajustes.path) {
            guard let datos = try? Data(contentsOf: ajustes),
                  let json = try? JSONSerialization.jsonObject(with: datos) as? [String: Any] else { return [] }
            if let valor = json["downloadsFolder"], !(valor is NSNull) {
                guard var texto = valor as? String else { return [] }
                if texto.hasPrefix("~/") { texto = home.path + String(texto.dropFirst(1)) }
                guard texto.hasPrefix("/") else { return [] }
                descargas = Seguridad.normalizada(texto)
            }
        }
        let activoReal = Seguridad.normalizada(activo.path)
        var r: [URL] = []
        for otro in [home.appendingPathComponent(".lmstudio"), home.appendingPathComponent(".cache/lm-studio")] {
            let otroReal = Seguridad.normalizada(otro.path)
            let extensiones = otro.appendingPathComponent("extensions")
            // Que sea otra carpeta de verdad: ni un enlace a la que se usa, ni una dentro de la otra.
            guard modelosLocalesEsCarpetaReal(otro), modelosLocalesEsCarpetaReal(extensiones), otroReal != activoReal,
                  !activoReal.hasPrefix(otroReal + "/"), !otroReal.hasPrefix(activoReal + "/") else { continue }
            if let d = descargas, d == otroReal || d.hasPrefix(otroReal + "/") { continue }
            r.append(extensiones)
        }
        return r
    }

    // MARK: - GPT4All

    /// GPT4All: descargas a medias e índices de LocalDocs que ya se pasaron al formato nuevo.
    static func modelosLocalesGPT4All(_ c: Contexto, home: URL) -> [Elemento] {
        guard c.apps.estaInstalado(carpeta: "GPT4All"), c.procesos.appAbierta(["gpt4all", "GPT4All"]) == nil,
              let carpeta = modelosLocalesCarpetaGPT4All(home: home), modelosLocalesEsCarpetaReal(carpeta) else { return [] }
        let restos = modelosLocalesRestosGPT4All(en: carpeta)
        let uso = EnUso.app(nombre: "GPT4All", claves: ["gpt4all", "GPT4All"])
        var r: [Elemento] = []
        let incompletos = restos.incompletos.filter { modelosLocalesOfrecible($0, home: home) }
        if !incompletos.isEmpty {
            r.append(Elemento(
                nombre: "Descargas a medias de GPT4All",
                detalle: "Modelos que GPT4All empezó a descargar y no terminó.",
                consecuencia: "Nada: son descargas que no terminaron.",
                rutas: incompletos, categoria: .desarrollo, riesgo: .seguro, seleccionado: true,
                motivos: [.bien("arrow.down.circle.dotted", "Descargas a medias", "Llevan más de 2 días sin avanzar.")],
                enUso: uso, dueno: "GPT4All"))
        }
        let indices = restos.indices.filter { modelosLocalesOfrecible($0, home: home) }
        if !indices.isEmpty {
            r.append(Elemento(
                nombre: "Índices antiguos de LocalDocs",
                detalle: "Bases de datos de LocalDocs de versiones anteriores de GPT4All.",
                consecuencia: "GPT4All ya copió tus colecciones al índice nuevo; estos no se usan.",
                rutas: indices, categoria: .desarrollo, riesgo: .seguro,
                motivos: [.bien("cylinder.split.1x2.fill", "Hay un índice nuevo", "Ya existe localdocs_v3.db, el que usa GPT4All ahora.")],
                enUso: uso, dueno: "GPT4All"))
        }
        return r
    }

    /// La carpeta de modelos de GPT4All según sus ajustes (modelPath), o la de siempre si no la cambiaste.
    /// `nil` si los ajustes apuntan fuera de tu carpeta personal o no se entienden.
    static func modelosLocalesCarpetaGPT4All(home: URL) -> URL? {
        let plist = NSDictionary(contentsOf: home.appendingPathComponent("Library/Preferences/com.nomic.gpt4all.plist"))
        var valor = plist?["modelPath"] as? String
        if valor == nil, let ini = try? String(contentsOf: home.appendingPathComponent(".config/nomic.ai/GPT4All.ini"), encoding: .utf8) {
            for linea in ini.components(separatedBy: .newlines) {
                let l = linea.trimmingCharacters(in: .whitespaces)
                guard l.hasPrefix("modelPath=") else { continue }
                valor = String(l.dropFirst("modelPath=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                break
            }
        }
        guard let ruta = valor else { return home.appendingPathComponent("Library/Application Support/nomic.ai/GPT4All") }
        return modelosLocalesDentro(ruta, home: home)
    }

    /// Lo que sobra en la carpeta de GPT4All: descargas a medias («incomplete-…») con más de 2 días sin cambios e índices
    /// de LocalDocs anteriores (con sus -wal y -shm), solo si ya existe localdocs_v3.db. Nunca las conversaciones (.chat)
    /// ni el índice actual. Si la carpeta no se puede leer, nada.
    static func modelosLocalesRestosGPT4All(en carpeta: URL, ahora: Date = Date()) -> (incompletos: [URL], indices: [URL]) {
        guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path) else { return ([], []) }
        let haceDosDias = ahora.addingTimeInterval(-2 * 86400)
        var incompletos: [URL] = []
        for n in nombres.sorted() where n.hasPrefix("incomplete-") && !n.hasSuffix(".chat") {
            let u = carpeta.appendingPathComponent(n)
            if let fecha = modelosLocalesFechaDeArchivo(u), fecha < haceDosDias { incompletos.append(u) }
        }
        var indices: [URL] = []
        if modelosLocalesFechaDeArchivo(carpeta.appendingPathComponent("localdocs_v3.db")) != nil {
            for v in 0...2 {
                for sufijo in ["", "-wal", "-shm"] {
                    let u = carpeta.appendingPathComponent("localdocs_v\(v).db\(sufijo)")
                    if modelosLocalesFechaDeArchivo(u) != nil { indices.append(u) }
                }
            }
        }
        return (incompletos, indices)
    }

    // MARK: - Modelos dentro de apps

    /// Modelos de IA grandes que guardan apps sin regla propia (MacWhisper, Msty Studio, Private LLM…), uno por app.
    static func modelosLocalesEnApps(_ c: Contexto, home: URL) -> [Elemento] {
        let archivos = c.indice.grandes.filter { $0.bytes >= 200_000_000 }.map { (ruta: $0.ruta, bytes: $0.bytes) }
        var carpetas: [(ruta: String, bytes: Int64)] = []
        for (ruta, info) in c.indice.carpetas where info.bytes >= 100_000_000 {
            let n = ruta.lowercased()
            if n.hasSuffix(".mlmodelc") || n.hasSuffix(".mlpackage") { carpetas.append((ruta: ruta, bytes: info.bytes)) }
        }
        // Ni lo que ya ofrece el catálogo ni lo de las cachés internas de las apps (salen enteras en otra categoría).
        let grupos = modelosLocalesModelosEnApps(archivos: archivos, carpetas: carpetas, home: home, accesoTotal: c.accesoTotal,
                                                 cubiertas: modelosLocalesCubiertasPorCatalogo(home: home)
                                                     .union(c.indice.cachesInternas.map { $0.ruta }))
        var r: [Elemento] = []
        for carpeta in grupos.keys.sorted() {
            guard let rutas = grupos[carpeta], !rutas.isEmpty else { continue }
            var clave = carpeta
            // Apps de iPhone y iPad: su contenedor se llama con un UUID y de quién es lo dicen sus metadatos.
            if UUID(uuidString: carpeta) != nil {
                guard let id = Escaner.appDeContenedor(home.appendingPathComponent("Library/Containers/" + carpeta)),
                      c.apps.bundleIDs.contains(id.lowercased()), !modelosLocalesAppExcluida(id) else { continue }
                clave = id
            }
            // Si la app ya no está, sus modelos salen con el resto de lo que dejó («Restos de apps borradas»).
            guard c.apps.estaInstalado(carpeta: clave) else { continue }
            let app = c.apps.nombreApp(para: clave) ?? clave
            r.append(Elemento(
                nombre: "Modelos de IA de \(app)",
                detalle: "Modelos guardados por \(app): \(Formato.listaCorta(rutas.map(\.lastPathComponent))).",
                consecuencia: "\(app) tendrá que volver a descargarlos. Si importaste alguno tú, necesitarás el archivo original.",
                rutas: rutas, categoria: .desarrollo, riesgo: .revisar,
                motivos: [.info("questionmark.circle", "Revísalo antes",
                                "Normalmente \(app) los vuelve a descargar, pero si alguno lo añadiste tú, puede que solo esté aquí.")],
                enUso: .app(nombre: app, claves: [clave, app]), dueno: app))
        }
        return r
    }

    /// Los candidatos a «modelo dentro de una app», agrupados por la carpeta de su app. Solo modelos grandes que se
    /// pueden ofrecer; nunca lo de Apple, lo de apps que ya se tratan aparte, lo que ya se ofrece por otro lado
    /// (`cubiertas`, que solo se calcula si hay candidatos), lo que puede ser tuyo (LoRA, modelos entrenados,
    /// importados…) ni lo de programas de Windows dentro de una botella de Wine (drive_c).
    static func modelosLocalesModelosEnApps(archivos: [(ruta: String, bytes: Int64)], carpetas: [(ruta: String, bytes: Int64)],
                                            home: URL, accesoTotal: Bool,
                                            cubiertas: @autoclosure () -> Set<String>) -> [String: [URL]] {
        let extensiones: Set<String> = ["gguf", "ggml", "safetensors", "ckpt", "pt", "pth", "onnx", "tflite", "tdict", "mlx"]
        var candidatos = Set<String>()
        for a in archivos where a.bytes >= 200_000_000 {
            let nombre = (a.ruta as NSString).lastPathComponent
            let ext = (nombre as NSString).pathExtension.lowercased()
            let n = nombre.lowercased()
            let padre = ((a.ruta as NSString).deletingLastPathComponent as NSString).lastPathComponent
            let binDeModelo = ext == "bin"
                && (n.hasPrefix("ggml-") || n.hasPrefix("pytorch_model") || ["models", "Models", "weights"].contains(padre))
            if extensiones.contains(ext) || binDeModelo { candidatos.insert(a.ruta) }
        }
        for d in carpetas where d.bytes >= 100_000_000 {
            let n = d.ruta.lowercased()
            if n.hasSuffix(".mlmodelc") || n.hasSuffix(".mlpackage") { candidatos.insert(d.ruta) }
        }
        // Lo que está dentro de otro candidato (los pesos de un .mlmodelc) ya va con él.
        let sueltos = candidatos.filter { !Rutas.estaDentro($0, de: candidatos) }
        guard !sueltos.isEmpty else { return [:] }

        let delCatalogo = cubiertas()
        let base = home.standardizedFileURL.path + "/"
        let personales: Set<String> = ["lora", "loras", "custom", "trained", "finetune", "fine-tuned", "user", "imported"]
        var r: [String: [URL]] = [:]
        for ruta in sueltos.sorted() where ruta.hasPrefix(base) {
            let partes = ruta.dropFirst(base.count).split(separator: "/").map(String.init)
            guard let app = modelosLocalesCarpetaDeApp(partes, accesoTotal: accesoTotal), !modelosLocalesAppExcluida(app),
                  !partes.contains(where: { personales.contains($0.lowercased()) || $0 == "drive_c" }),
                  !delCatalogo.contains(ruta), !Rutas.estaDentro(ruta, de: delCatalogo) else { continue }
            let u = URL(fileURLWithPath: ruta)
            guard modelosLocalesOfrecible(u, home: home) else { continue }
            r[app, default: []].append(u)
        }
        return r
    }

    /// La carpeta de la app a la que pertenece una ruta de Library (en partes, desde la carpeta personal):
    /// «Application Support/<app>/…» y, con Acceso total, «Containers/<app>/Data/{Documents, Library/Application Support}/…»
    /// y «Group Containers/<app>/…». `nil` en cualquier otro sitio. La caché del contenedor ya sale entera en «Caché de
    /// <app>» y lo que las apps descargan con swift-transformers (Documents/huggingface), con Hugging Face.
    static func modelosLocalesCarpetaDeApp(_ partes: [String], accesoTotal: Bool) -> String? {
        guard partes.count >= 4, partes[0] == "Library" else { return nil }
        if partes[1] == "Application Support" { return partes[2] }
        guard accesoTotal else { return nil }
        if partes[1] == "Group Containers" { return partes[2] }
        guard partes[1] == "Containers", partes.count >= 6, partes[3] == "Data" else { return nil }
        if partes[4] == "Documents" { return partes[5] == "huggingface" ? nil : partes[2] }
        if partes.count >= 7, partes[4] == "Library", partes[5] == "Application Support" { return partes[2] }
        return nil
    }

    /// Lo de Apple, las apps cuyos modelos se tratan aparte (Ollama, LM Studio, GPT4All, Jan, AnythingLLM, Msty,
    /// Draw Things) y lo que no son modelos de una app (copias del iPhone, la máquina virtual de Claude).
    static func modelosLocalesAppExcluida(_ carpeta: String) -> Bool {
        let l = carpeta.lowercased()
        return l.contains("com.apple.") || ["mobilesync", "nomic.ai", "jan", "anythingllm-desktop", "lm studio", "msty",
                                            "claude", "com.liuliu.draw-things"].contains(l)
    }

    /// Lo que ya ofrecen las reglas del catálogo dentro de ~/Library (sus carpetas, tal como existen ahora).
    static func modelosLocalesCubiertasPorCatalogo(home: URL) -> Set<String> {
        var r = Set<String>()
        for regla in Catalogo.reglas where regla.patron.hasPrefix("~/Library/") {
            for u in Escaner.expandir(home.path + String(regla.patron.dropFirst(1))) { r.insert(u.path) }
        }
        return r
    }

    // MARK: - Utilidades

    /// Una ruta absoluta (o «~/…») que esté dentro de tu carpeta personal; `nil` si no.
    static func modelosLocalesDentro(_ ruta: String, home: URL) -> URL? {
        var p = ruta
        if p.hasPrefix("~/") { p = home.path + String(p.dropFirst(1)) }
        guard p.hasPrefix("/") else { return nil }
        let u = URL(fileURLWithPath: p).standardizedFileURL
        return u.path.hasPrefix(home.standardizedFileURL.path + "/") ? u : nil
    }

    /// Existe y es una carpeta de verdad (no un enlace).
    static func modelosLocalesEsCarpetaReal(_ u: URL) -> Bool {
        var st = stat()
        return lstat(u.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// La fecha de modificación de un archivo normal; `nil` si no existe o es una carpeta o un enlace.
    static func modelosLocalesFechaDeArchivo(_ u: URL) -> Date? {
        var st = stat()
        guard lstat(u.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
    }

    /// Se puede ofrecer: existe, no es un enlace, está dentro de tu carpeta personal (también siguiendo los enlaces
    /// del camino) y se puede mover a la Papelera.
    static func modelosLocalesOfrecible(_ u: URL, home: URL) -> Bool {
        var st = stat()
        guard lstat(u.path, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK,
              u.standardizedFileURL.path.hasPrefix(home.standardizedFileURL.path + "/"),
              Seguridad.normalizada(u.path).hasPrefix(Seguridad.normalizada(home.path) + "/") else { return false }
        return Escaner.sePuedeQuitar(u, admin: false)
    }
}
