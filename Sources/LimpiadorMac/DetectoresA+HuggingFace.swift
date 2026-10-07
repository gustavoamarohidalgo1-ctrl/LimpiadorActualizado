import Darwin
import Foundation

/// Hugging Face por partes: nunca la carpeta entera (junto a los modelos están el token de tu cuenta y la configuración
/// de accelerate), solo lo que se sabe volver a crear o descargar. Lo mismo con los modelos que descargan las apps con
/// swift-transformers y con los conjuntos de TensorFlow Datasets.
extension Escaner {
    func detectoresA_HuggingFace(_ c: Contexto) -> [Elemento] {
        Self.huggingFaceElementos(home: Rutas.home, entorno: ProcessInfo.processInfo.environment, apps: c.apps,
                                  accesoTotal: c.accesoTotal, abiertos: { c.memoria.archivosAbiertos() }, ahora: Date())
    }

    /// Todo el grupo sobre una carpeta personal cualquiera. Lo que tienen abierto los programas (`abiertos`, que tarda)
    /// solo se pide si hay algo que ofrecer.
    static func huggingFaceElementos(home: URL, entorno: [String: String], apps: AppsInstaladas, accesoTotal: Bool,
                                     abiertos: () -> ArchivosAbiertos, ahora: Date) -> [Elemento] {
        var r: [Elemento] = []
        let raices = huggingFaceRaices(home: home, entorno: entorno)
        if !raices.isEmpty { r += huggingFaceHub(raices, home: home, abiertos: abiertos(), ahora: ahora) }
        r += huggingFaceModelosDeApps(home: home, contenedores: accesoTotal, apps: apps, abiertos: abiertos)
        r += huggingFaceTFDS(home: home, abiertos: abiertos)
        return r
    }

    // MARK: Hugging Face

    /// Una carpeta de Hugging Face (lo que la librería llama HF_HOME) y quién la usa.
    struct HuggingFaceRaiz {
        let url: URL
        let dueno: String
        let uso: EnUso
    }

    /// Un repo del hub («models--org--nombre») con el formato de siempre.
    struct HuggingFaceRepo {
        let url: URL
        /// Los archivos de blobs/ (también los «.incomplete»).
        let blobs: Set<String>
        /// Cada revisión (su commit) y los blobs a los que apuntan sus archivos.
        let snapshots: [String: Set<String>]
    }

    /// Carpetas en las que no se mira aunque HF_HOME apunte a ellas: lo que tienen dentro con nombres genéricos
    /// («modules», «datasets»…) puede no ser de Hugging Face.
    private static let huggingFaceCarpetasGenericas: Set<String> = [
        "Library", "Library/Caches", "Library/Application Support", "Documents", "Desktop", "Downloads", "Movies",
        "Music", "Pictures", "Public", ".cache", ".config", ".local", ".local/share",
    ]

    /// Los constructores de la librería datasets que preparan archivos que le das tú (CSV, JSON…), no descargas.
    private static let huggingFaceConstructoresLocales: Set<String> = [
        "csv", "json", "parquet", "text", "arrow", "pandas", "imagefolder", "audiofolder", "videofolder", "webdataset",
        "sql", "generator", "xml",
    ]

    /// ~/.cache/huggingface, la de HF_HOME (solo dentro de tu carpeta) y la que comparten las apps de Pinokio.
    /// Sin repetir: si una es la misma que otra, o está dentro de otra, cuenta solo la primera.
    static func huggingFaceRaices(home: URL, entorno: [String: String]) -> [HuggingFaceRaiz] {
        let h = huggingFaceSinPuntos(home.path)
        let usoHF = EnUso.proceso(nombre: "Hugging Face", patron: "huggingface")
        var candidatas = [HuggingFaceRaiz(url: URL(fileURLWithPath: h + "/.cache/huggingface"), dueno: "Hugging Face", uso: usoHF)]
        if var valor = entorno["HF_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !valor.isEmpty {
            if valor == "~" || valor.hasPrefix("~/") { valor = h + String(valor.dropFirst()) }
            let ruta = huggingFaceSinPuntos(valor)
            if valor.hasPrefix("/"), ruta.hasPrefix(h + "/"),
               !huggingFaceCarpetasGenericas.contains(String(ruta.dropFirst(h.count + 1))) {
                candidatas.append(HuggingFaceRaiz(url: URL(fileURLWithPath: ruta), dueno: "Hugging Face", uso: usoHF))
            }
        }
        candidatas.append(HuggingFaceRaiz(url: URL(fileURLWithPath: h + "/pinokio/cache/HF_HOME"), dueno: "Pinokio",
                                          uso: .app(nombre: "Pinokio", claves: ["computer.pinokio", "Pinokio"])))
        var r: [HuggingFaceRaiz] = []
        for candidata in candidatas where huggingFaceEsCarpetaReal(candidata.url.path) {
            let p = candidata.url.path
            if r.contains(where: { $0.url.path == p || $0.url.path.hasPrefix(p + "/") || p.hasPrefix($0.url.path + "/") }) {
                continue
            }
            r.append(candidata)
        }
        return r
    }

    /// Lo que se puede limpiar en cada carpeta de Hugging Face. Nada si no se sabe qué tienen abierto los programas,
    /// y nada de una carpeta en la que hay una descarga en marcha.
    static func huggingFaceHub(_ raices: [HuggingFaceRaiz], home: URL, abiertos: ArchivosAbiertos, ahora: Date) -> [Elemento] {
        guard abiertos.disponible else { return [] }
        var r: [Elemento] = []
        for raiz in raices where !huggingFaceDescargando(raiz.url, abiertos: abiertos, ahora: ahora) {
            r += huggingFaceElementosDeRaiz(raiz, home: home, abiertos: abiertos, ahora: ahora)
        }
        return r
    }

    /// ¿Hay una descarga en marcha? Un candado de hub/.locks tocado hace menos de 10 minutos, o un archivo
    /// «.incomplete» abierto. Si los candados no se pueden leer (o son demasiados), se da por hecho que sí.
    static func huggingFaceDescargando(_ raiz: URL, abiertos: ArchivosAbiertos, ahora: Date) -> Bool {
        let prefijos = Set([raiz.path, Seguridad.normalizada(raiz.path)]).map { $0 + "/" }
        let aMedias = abiertos.rutas.contains { r in
            prefijos.contains(where: { r.hasPrefix($0) }) && (r.hasSuffix(".incomplete") || r.contains(".incomplete/"))
        }
        if aMedias { return true }
        let candados = raiz.path + "/hub/.locks"
        guard let tipo = huggingFaceTipo(candados) else { return false }
        guard tipo == S_IFDIR else { return true }
        let limite = ahora.timeIntervalSince1970 - 600
        let leidos = huggingFaceRecorrer(candados, maximo: 20_000) { _, st in Double(st.st_mtimespec.tv_sec) < limite }
        return leidos == nil
    }

    /// Los elementos de una carpeta de Hugging Face: caché de Xet, descargas a medias, revisiones antiguas, código
    /// y archivos auxiliares, conjuntos de datos y cada repo entero. Nunca la carpeta, ni hub entera, ni el token.
    static func huggingFaceElementosDeRaiz(_ raiz: HuggingFaceRaiz, home: URL, abiertos: ArchivosAbiertos,
                                           ahora: Date) -> [Elemento] {
        let base = raiz.url.path
        let sufijo = raiz.dueno == "Hugging Face" ? "" : " (\(raiz.dueno))"
        var r: [Elemento] = []
        func ofrecibles(_ rutas: [URL]) -> [URL] {
            rutas.filter { huggingFaceOfrecible($0, home: home) && !abiertos.tieneAbierto($0.path) }
        }
        func agregar(_ nombre: String, _ detalle: String, _ consecuencia: String, _ rutas: [URL], _ riesgo: Riesgo,
                     _ seleccionado: Bool, _ motivo: Motivo, ultimoUso: Date? = nil) {
            r.append(Elemento(
                nombre: nombre + sufijo, detalle: detalle, consecuencia: consecuencia, rutas: rutas, ultimoUso: ultimoUso,
                categoria: .desarrollo, riesgo: riesgo, seleccionado: seleccionado, motivos: [motivo],
                enUso: raiz.uso, dueno: raiz.dueno))
        }

        // 1. Caché de Xet: fragmentos de las descargas.
        let xet = URL(fileURLWithPath: base + "/xet")
        if huggingFaceEsCarpetaReal(xet.path), !ofrecibles([xet]).isEmpty {
            agregar("Caché de descargas de Hugging Face (Xet)", "Fragmentos y temporales que usa Hugging Face para descargar más rápido.",
                    "Se vuelve a crear sola en la próxima descarga. Tus modelos ya descargados no se tocan.", [xet], .seguro, true,
                    .bien("arrow.triangle.2.circlepath", "Se regenera", "Es la caché de las descargas: tus modelos están aparte y no se tocan."))
        }

        // 2, 3 y 6. Cada repo del hub: sus descargas a medias, sus revisiones antiguas y el repo entero.
        let hub = base + "/hub"
        var aMedias: [URL] = []
        var sueltas: [URL] = []
        var conSueltas: [String] = []
        for n in ((try? FileManager.default.contentsOfDirectory(atPath: hub)) ?? []).sorted() {
            let repo = URL(fileURLWithPath: hub + "/" + n)
            guard ["models--", "datasets--", "spaces--"].contains(where: { n.hasPrefix($0) }),
                  huggingFaceEsCarpetaReal(repo.path) else { continue }
            aMedias += huggingFaceDescargasAMedias(repo, abiertos: abiertos, ahora: ahora)
            guard let info = huggingFaceLeerRepo(repo) else { continue }
            let (tipo, nombre) = huggingFaceNombreRepo(n)
            if let refs = huggingFaceRefs(repo) {
                let rutas = huggingFaceRevisionesSueltas(info, refs: refs)
                // Si alguna parte no se puede ofrecer (algún programa la tiene abierta), ese repo no entra.
                if !rutas.isEmpty && ofrecibles(rutas).count == rutas.count {
                    sueltas += rutas
                    conSueltas.append(nombre)
                }
            }
            guard !ofrecibles([repo]).isEmpty else { continue }
            agregar("\(tipo): \(nombre)", "Descargado con Hugging Face en \(Formato.rutaCorta(raiz.url)).",
                    "Si un programa lo vuelve a necesitar, lo descarga otra vez (puede tardar y ocupar varios GB).", [repo], .revisar, false,
                    .info("arrow.down.circle.fill", "Se vuelve a descargar",
                          "Son archivos descargados de Hugging Face: el programa que lo use los descarga de nuevo."),
                    ultimoUso: huggingFaceUltimoAcceso(info))
        }
        let medias = ofrecibles(aMedias)
        if !medias.isEmpty {
            agregar("Descargas a medias de Hugging Face",
                    medias.count == 1 ? "1 archivo que empezó a descargarse y lleva más de un día sin avanzar."
                                      : "\(Formato.numero(medias.count)) archivos que empezaron a descargarse y llevan más de un día sin avanzar.",
                    "Nada: son descargas interrumpidas; si vuelves a pedir ese modelo, se descarga de nuevo.", medias, .seguro, true,
                    .bien("arrow.down.circle.dotted", "Descarga interrumpida", "Ningún programa las tiene abiertas y llevan más de un día sin cambios."))
        }
        if !sueltas.isEmpty {
            agregar("Revisiones antiguas de modelos de Hugging Face",
                    "Versiones anteriores de \(conSueltas.count == 1 ? "un modelo" : "\(conSueltas.count) modelos") a las que ya no apunta ninguna rama.",
                    "Nada: tus modelos siguen en su versión actual. Si un programa pide esa revisión exacta, se vuelve a descargar. Es lo mismo que «hf cache prune».",
                    sueltas, .seguro, true,
                    .bien("clock.arrow.circlepath", "Versiones sin rama",
                          "Ninguna rama apunta ya a estas versiones de \(Formato.listaCorta(conSueltas)); la versión actual de cada uno se queda."))
        }

        // 4. Código de modelos y archivos auxiliares de las librerías.
        let modulos = URL(fileURLWithPath: base + "/modules")
        if huggingFaceEsCarpetaReal(modulos.path), !ofrecibles([modulos]).isEmpty {
            agregar("Código descargado de modelos de Hugging Face",
                    "Código propio de algunos modelos y conjuntos de datos, que las librerías guardan aquí para ejecutarlo.",
                    "Se vuelve a descargar al cargar el modelo.", [modulos], .seguro, true,
                    .bien("arrow.triangle.2.circlepath", "Se regenera", "Las librerías lo vuelven a copiar o descargar al cargar cada modelo."))
        }
        let auxiliares = URL(fileURLWithPath: base + "/assets")
        if huggingFaceEsCarpetaReal(auxiliares.path), !ofrecibles([auxiliares]).isEmpty {
            agregar("Archivos auxiliares de librerías de Hugging Face", "Archivos que otras librerías guardan en la carpeta de Hugging Face.",
                    "Las librerías los vuelven a crear o descargar cuando los necesitan.", [auxiliares], .seguro, false,
                    .bien("arrow.triangle.2.circlepath", "Se regenera", "Las librerías los vuelven a crear o descargar cuando los necesitan."))
        }

        // 5. Conjuntos de datos (librería datasets): las descargas originales y cada conjunto ya preparado.
        let datasets = base + "/datasets"
        let descargas = URL(fileURLWithPath: datasets + "/downloads")
        if huggingFaceEsCarpetaReal(descargas.path), !ofrecibles([descargas]).isEmpty {
            // Algunos conjuntos de audio o imágenes leen sus archivos desde aquí: por eso no es «seguro».
            agregar("Descargas originales de conjuntos de datos",
                    "Archivos que la librería datasets descargó para preparar tus conjuntos de datos.",
                    "Los conjuntos ya preparados siguen funcionando, salvo algunos de audio o imágenes que leen sus archivos desde aquí: habría que volver a prepararlos.",
                    [descargas], .revisar, false,
                    .info("arrow.down.circle.fill", "Se vuelve a descargar", "Si preparas un conjunto de nuevo, se descarga otra vez."))
        }
        for n in ((try? FileManager.default.contentsOfDirectory(atPath: datasets)) ?? []).sorted() {
            let d = URL(fileURLWithPath: datasets + "/" + n)
            guard n != "downloads", huggingFaceNombreSeguro(n), huggingFaceEsCarpetaReal(d.path),
                  huggingFaceConjuntoPreparado(d), !ofrecibles([d]).isEmpty else { continue }
            if huggingFaceConstructoresLocales.contains(n.lowercased()) {
                agregar("Conjunto de datos preparado: \(n)",
                        "Copia preparada (en formato Arrow) de archivos de datos que cargó la librería datasets: CSV, JSON, Parquet…",
                        "Se vuelve a preparar desde los archivos originales si un programa lo pide. Si ya no los tienes, perderás esta copia.",
                        [d], .cuidado, false,
                        .aviso("doc.on.doc.fill", "Puede ser la única copia",
                               "Se hizo a partir de archivos de datos que pueden ser tuyos: comprueba que sigues teniendo los originales."))
            } else {
                agregar("Conjunto de datos preparado: \(n)", "Conjunto de datos que la librería datasets descargó y preparó.",
                        "Se vuelve a descargar y preparar si un programa lo pide.", [d], .revisar, false,
                        .info("arrow.down.circle.fill", "Se vuelve a descargar", "Está preparado a partir de una descarga de Hugging Face."))
            }
        }
        return r
    }

    /// Lee un repo del hub. `nil` si no tiene el formato de siempre: blobs/, snapshots/ y refs/, ningún blob es un enlace
    /// (eso es el formato de almacén compartido) y cada enlace de snapshots/ apunta a un blob de este repo que existe.
    /// También si algo no se puede leer: entonces el repo no se ofrece de ninguna forma.
    static func huggingFaceLeerRepo(_ repo: URL) -> HuggingFaceRepo? {
        let base = huggingFaceSinPuntos(repo.path)
        let carpetaBlobs = base + "/blobs"
        let carpetaSnapshots = base + "/snapshots"
        guard huggingFaceEsCarpetaReal(carpetaBlobs), huggingFaceEsCarpetaReal(carpetaSnapshots),
              huggingFaceEsCarpetaReal(base + "/refs"),
              let nombres = try? FileManager.default.contentsOfDirectory(atPath: carpetaBlobs),
              let commits = try? FileManager.default.contentsOfDirectory(atPath: carpetaSnapshots) else { return nil }
        var blobs = Set<String>()
        for n in nombres {
            guard huggingFaceTipo(carpetaBlobs + "/" + n) == S_IFREG else { return nil }
            blobs.insert(n)
        }
        var snapshots: [String: Set<String>] = [:]
        var restantes = 50_000
        for commit in commits where commit != ".DS_Store" {
            let carpeta = carpetaSnapshots + "/" + commit
            guard huggingFaceEsCarpetaReal(carpeta) else { return nil }
            var usados = Set<String>()
            let vistas = huggingFaceRecorrer(carpeta, maximo: restantes) { ruta, st in
                let tipo = st.st_mode & S_IFMT
                guard tipo == S_IFLNK else { return tipo == S_IFDIR || tipo == S_IFREG }
                // Cada archivo de una revisión es un enlace a su blob: «../../blobs/<hash>».
                guard let destino = try? FileManager.default.destinationOfSymbolicLink(atPath: ruta) else { return false }
                let real = huggingFaceSinPuntos(destino, desde: Rutas.padre(ruta))
                guard Rutas.padre(real) == carpetaBlobs, blobs.contains(Rutas.nombre(real)) else { return false }
                usados.insert(Rutas.nombre(real))
                return true
            }
            guard let vistas else { return nil }
            restantes -= vistas
            snapshots[commit] = usados
        }
        return HuggingFaceRepo(url: URL(fileURLWithPath: base), blobs: blobs, snapshots: snapshots)
    }

    /// Los commits a los que apunta alguna rama o etiqueta (refs/main, refs/pr/1…). `nil` si alguna no se puede leer
    /// o no es un commit: entonces no se sabe qué revisiones sobran.
    static func huggingFaceRefs(_ repo: URL) -> Set<String>? {
        let carpeta = repo.path + "/refs"
        guard huggingFaceEsCarpetaReal(carpeta) else { return nil }
        var commits = Set<String>()
        let vistas = huggingFaceRecorrer(carpeta, maximo: 10_000) { ruta, st in
            let tipo = st.st_mode & S_IFMT
            if tipo == S_IFDIR || Rutas.nombre(ruta) == ".DS_Store" { return true }
            guard tipo == S_IFREG, let texto = try? String(contentsOfFile: ruta, encoding: .utf8) else { return false }
            let commit = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard huggingFaceEsCommit(commit) else { return false }
            commits.insert(commit)
            return true
        }
        guard vistas != nil else { return nil }
        return commits
    }

    /// Lo que borra «hf cache prune» en un repo: las revisiones a las que no apunta ninguna rama y los blobs que solo
    /// usan ellas. Nada si alguna revisión no tiene nombre de commit, o si ninguna rama apunta a una revisión descargada
    /// (eso sería el modelo entero, que se ofrece aparte).
    static func huggingFaceRevisionesSueltas(_ repo: HuggingFaceRepo, refs: Set<String>) -> [URL] {
        guard repo.snapshots.keys.allSatisfy({ huggingFaceEsCommit($0) }) else { return [] }
        let usadas = Set(repo.snapshots.keys).intersection(refs)
        guard !usadas.isEmpty else { return [] }
        var deUsadas = Set<String>()
        var deSueltas = Set<String>()
        var carpetas: [String] = []
        for (commit, blobs) in repo.snapshots {
            if usadas.contains(commit) {
                deUsadas.formUnion(blobs)
            } else {
                deSueltas.formUnion(blobs)
                carpetas.append(repo.url.path + "/snapshots/" + commit)
            }
        }
        let exclusivos = deSueltas.subtracting(deUsadas).sorted().map { repo.url.path + "/blobs/" + $0 }
        return (carpetas.sorted() + exclusivos).map { URL(fileURLWithPath: $0) }
    }

    /// Descargas a medias de un repo (blobs/*.incomplete) que llevan más de un día sin cambios y que nadie tiene
    /// abiertas. Nada si blobs/ tiene enlaces (almacén compartido) o no se puede leer.
    static func huggingFaceDescargasAMedias(_ repo: URL, abiertos: ArchivosAbiertos, ahora: Date) -> [URL] {
        let carpeta = repo.path + "/blobs"
        guard huggingFaceEsCarpetaReal(carpeta),
              let nombres = try? FileManager.default.contentsOfDirectory(atPath: carpeta) else { return [] }
        var r: [URL] = []
        for n in nombres.sorted() {
            let ruta = carpeta + "/" + n
            var st = stat()
            guard lstat(ruta, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK else { return [] }
            guard n.hasSuffix(".incomplete"), (st.st_mode & S_IFMT) == S_IFREG,
                  ahora.timeIntervalSince1970 - Double(st.st_mtimespec.tv_sec) > 86_400,
                  !abiertos.tieneAbierto(ruta) else { continue }
            r.append(URL(fileURLWithPath: ruta))
        }
        return r
    }

    /// «models--org--nombre» → («Modelo de IA», «org/nombre»).
    static func huggingFaceNombreRepo(_ carpeta: String) -> (tipo: String, nombre: String) {
        let tipos: [(prefijo: String, tipo: String)] = [("models--", "Modelo de IA"), ("datasets--", "Conjunto de datos"),
                                                         ("spaces--", "Space")]
        for t in tipos where carpeta.hasPrefix(t.prefijo) {
            return (t.tipo, String(carpeta.dropFirst(t.prefijo.count)).replacingOccurrences(of: "--", with: "/"))
        }
        return ("Repositorio", carpeta)
    }

    /// El último acceso a alguno de sus blobs: la última vez que un programa cargó el modelo.
    static func huggingFaceUltimoAcceso(_ repo: HuggingFaceRepo) -> Date? {
        var mayor = 0
        for b in repo.blobs {
            var st = stat()
            if lstat(repo.url.path + "/blobs/" + b, &st) == 0 { mayor = max(mayor, Int(st.st_atimespec.tv_sec)) }
        }
        return mayor > 0 ? Date(timeIntervalSince1970: TimeInterval(mayor)) : nil
    }

    /// ¿Es un conjunto que la librería datasets ya preparó? Tiene su dataset_info.json en <config>/<versión>[/<hash>].
    static func huggingFaceConjuntoPreparado(_ carpeta: URL) -> Bool {
        let p = carpeta.path
        return (Escaner.expandir(p + "/*/*/dataset_info.json") + Escaner.expandir(p + "/*/*/*/dataset_info.json"))
            .contains { !$0.path.contains(".incomplete") }
    }

    // MARK: swift-transformers

    /// Modelos que las apps descargan con swift-transformers en Documentos/huggingface (y, con Acceso total al disco,
    /// dentro de su contenedor). Solo los que llevan la marca de esa descarga y en los que todo vino de ella.
    static func huggingFaceModelosDeApps(home: URL, contenedores: Bool, apps: AppsInstaladas,
                                         abiertos: () -> ArchivosAbiertos) -> [Elemento] {
        // Cada carpeta «huggingface» y el identificador de la app de su contenedor (nil: la de Documentos, de quien sea).
        var bases: [(carpeta: String, id: String?)] = [(home.path + "/Documents/huggingface", nil)]
        if contenedores {
            let prefijo = home.path + "/Library/Containers/"
            for u in Escaner.expandir(prefijo + "*/Data/Documents/huggingface") {
                guard u.path.hasPrefix(prefijo),
                      let carpeta = u.path.dropFirst(prefijo.count).split(separator: "/").first.map(String.init) else { continue }
                var id = carpeta
                // Apps de iPhone y iPad: el contenedor se llama con un UUID y la app se sabe por sus metadatos.
                if UUID(uuidString: carpeta) != nil {
                    guard let real = Escaner.appDeContenedor(URL(fileURLWithPath: prefijo + carpeta)) else { continue }
                    id = real
                }
                // Si la app ya no está, su contenedor entero sale en «Restos de apps borradas».
                guard apps.estaInstalado(carpeta: id) else { continue }
                bases.append((carpeta: u.path, id: id))
            }
        }
        var r: [Elemento] = []
        var lectura: ArchivosAbiertos?
        for b in bases {
            for repo in huggingFaceReposDeApp(b.carpeta) where huggingFaceSoloDescargado(repo.url) {
                if lectura == nil { lectura = abiertos() }
                // Si no se sabe qué tienen abierto los programas, no se ofrece: la app puede estar usando el modelo.
                guard let a = lectura, a.disponible, huggingFaceOfrecible(repo.url, home: home),
                      !a.tieneAbierto(repo.url.path) else { continue }
                let app = b.id.map { apps.nombreApp(para: $0) ?? $0 }
                r.append(Elemento(
                    nombre: "\(repo.tipo == "datasets" ? "Conjunto de datos descargado por una app" : "Modelo descargado por una app"): \(repo.nombre)",
                    detalle: app.map { "Lo descargó \($0) desde Hugging Face y lo guarda en su contenedor." }
                        ?? "Lo descargó una app desde Hugging Face en \(Formato.rutaCorta(b.carpeta)).",
                    consecuencia: "La app que lo usa lo vuelve a descargar la próxima vez que lo necesite.",
                    rutas: [repo.url], categoria: .desarrollo, riesgo: .revisar, seleccionado: false,
                    motivos: [.info("arrow.down.circle.fill", "Se vuelve a descargar",
                                    "Todo lo que hay en la carpeta vino de una descarga de Hugging Face: no hay archivos tuyos.")],
                    enUso: b.id.map { EnUso.app(nombre: app ?? $0, claves: [$0]) }, dueno: "Hugging Face"))
            }
        }
        return r
    }

    /// Los repos de una carpeta «huggingface» de swift-transformers: «models/org/repo» (o «models/repo», sin
    /// organización) y lo mismo en «datasets». Solo los que llevan la marca de la descarga: .cache/huggingface/download.
    static func huggingFaceReposDeApp(_ carpeta: String) -> [(url: URL, tipo: String, nombre: String)] {
        var r: [(url: URL, tipo: String, nombre: String)] = []
        func marcado(_ ruta: String) -> Bool { huggingFaceEsCarpetaReal(ruta + "/.cache/huggingface/download") }
        for tipo in ["models", "datasets"] {
            let base = carpeta + "/" + tipo
            for primero in huggingFaceSubcarpetas(base) {
                let ruta = base + "/" + primero
                if marcado(ruta) {
                    r.append((url: URL(fileURLWithPath: ruta), tipo: tipo, nombre: primero))
                    continue
                }
                for segundo in huggingFaceSubcarpetas(ruta) where marcado(ruta + "/" + segundo) {
                    r.append((url: URL(fileURLWithPath: ruta + "/" + segundo), tipo: tipo, nombre: primero + "/" + segundo))
                }
            }
        }
        return r
    }

    /// ¿Todo lo que hay en el repo vino de la descarga? Cada archivo tiene su «.metadata» en .cache/huggingface/download.
    /// Si hay algo más (un archivo tuyo, un enlace) o algo no se puede leer, no se ofrece.
    static func huggingFaceSoloDescargado(_ repo: URL) -> Bool {
        let base = repo.path
        let metadatos = base + "/.cache/huggingface/download/"
        var archivos = 0
        let vistas = huggingFaceRecorrer(base, maximo: 20_000) { ruta, st in
            let rel = String(ruta.dropFirst(base.count + 1))
            let tipo = st.st_mode & S_IFMT
            if rel == ".cache" || rel.hasPrefix(".cache/") || tipo == S_IFDIR || Rutas.nombre(rel) == ".DS_Store" { return true }
            guard tipo == S_IFREG, Rutas.existeSinSeguir(metadatos + rel + ".metadata") else { return false }
            archivos += 1
            return true
        }
        return vistas != nil && archivos > 0
    }

    // MARK: TensorFlow Datasets

    /// ~/tensorflow_datasets: las descargas de conjuntos que ya están preparados y cada conjunto preparado.
    static func huggingFaceTFDS(home: URL, abiertos: () -> ArchivosAbiertos) -> [Elemento] {
        let raiz = URL(fileURLWithPath: home.path + "/tensorflow_datasets")
        guard huggingFaceEsCarpetaReal(raiz.path) else { return [] }

        // (a) Cada descarga X junto a su X.INFO, si todos los conjuntos que la usaron ya están preparados. Nunca
        //     downloads/manual (lo pusiste tú), ni extracted (lo ofrece otra regla), ni lo que se está descargando (.tmp).
        let descargas = raiz.path + "/downloads"
        var pares: [[URL]] = []
        for n in ((try? FileManager.default.contentsOfDirectory(atPath: descargas)) ?? []).sorted() {
            guard !n.hasPrefix("."), n != "manual", n != "extracted", !n.hasSuffix(".INFO"), !n.contains(".tmp") else { continue }
            let x = descargas + "/" + n
            let info = x + ".INFO"
            guard let tipo = huggingFaceTipo(x), tipo == S_IFREG || tipo == S_IFDIR, huggingFaceTipo(info) == S_IFREG,
                  let nombres = huggingFaceConjuntosDeDescarga(URL(fileURLWithPath: info)),
                  nombres.allSatisfy({ huggingFaceTFDSPreparado(raiz, $0) }) else { continue }
            pares.append([URL(fileURLWithPath: x), URL(fileURLWithPath: info)])
        }

        // (b) Cada conjunto ya preparado.
        var conjuntos: [URL] = []
        for n in ((try? FileManager.default.contentsOfDirectory(atPath: raiz.path)) ?? []).sorted() where n != "downloads" {
            let d = URL(fileURLWithPath: raiz.path + "/" + n)
            if huggingFaceEsCarpetaReal(d.path) && huggingFaceTFDSPreparado(raiz, n) { conjuntos.append(d) }
        }
        guard !pares.isEmpty || !conjuntos.isEmpty else { return [] }

        // Lo que algún programa tiene abierto no se ofrece (si no se puede saber, lo cubre el aviso de Python en marcha).
        let a = abiertos()
        func libre(_ u: URL) -> Bool { huggingFaceOfrecible(u, home: home) && !(a.disponible && a.tieneAbierto(u.path)) }
        let uso = EnUso.proceso(nombre: "Python", patron: "python")
        var r: [Elemento] = []
        let listas = pares.filter { $0.allSatisfy(libre) }
        if !listas.isEmpty {
            r.append(Elemento(
                nombre: "Descargas de TensorFlow Datasets ya preparadas",
                detalle: listas.count == 1 ? "1 descarga de un conjunto de datos que ya está preparado."
                                           : "\(Formato.numero(listas.count)) descargas de conjuntos de datos que ya están preparados.",
                consecuencia: "Los conjuntos ya preparados siguen funcionando; si preparas uno de nuevo, se vuelve a descargar.",
                rutas: listas.flatMap { $0 }, categoria: .desarrollo, riesgo: .seguro, seleccionado: false,
                motivos: [.bien("checkmark.circle.fill", "Ya preparados",
                                "Cada conjunto que usó estas descargas ya está preparado (tiene su dataset_info.json).")],
                enUso: uso, dueno: "TensorFlow Datasets"))
        }
        for d in conjuntos where libre(d) {
            r.append(Elemento(
                nombre: "Conjunto de TensorFlow Datasets: \(d.lastPathComponent)",
                detalle: "Conjunto de datos que TensorFlow Datasets descargó y preparó.",
                consecuencia: "Se vuelve a descargar y preparar si un programa lo pide; si la fuente original ya no existe, no se podrá recuperar.",
                rutas: [d], categoria: .desarrollo, riesgo: .revisar, seleccionado: false,
                motivos: [.info("arrow.down.circle.fill", "Se vuelve a preparar",
                                "TensorFlow Datasets lo descarga y lo prepara de nuevo si un programa lo pide.")],
                enUso: uso, dueno: "TensorFlow Datasets"))
        }
        return r
    }

    /// Los conjuntos que usaron una descarga, según su archivo .INFO. `nil` si no se puede leer o entender.
    static func huggingFaceConjuntosDeDescarga(_ info: URL) -> [String]? {
        guard let datos = try? Data(contentsOf: info),
              let d = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let nombres = d["dataset_names"] as? [String], !nombres.isEmpty,
              nombres.allSatisfy({ huggingFaceNombreSeguro($0) }) else { return nil }
        return nombres
    }

    /// ¿Está preparado este conjunto de TensorFlow Datasets? Tiene su dataset_info.json en <versión> o en
    /// <config>/<versión> (sin contar las preparaciones a medias).
    static func huggingFaceTFDSPreparado(_ raiz: URL, _ nombre: String) -> Bool {
        guard huggingFaceNombreSeguro(nombre) else { return false }
        let p = raiz.path + "/" + nombre
        return (Escaner.expandir(p + "/*/dataset_info.json") + Escaner.expandir(p + "/*/*/dataset_info.json"))
            .contains { !$0.path.contains(".incomplete") }
    }

    // MARK: Utilidades del grupo

    /// Lo único que se ofrece: existe, no es un enlace, está dentro de `home` y se puede mover a la Papelera.
    static func huggingFaceOfrecible(_ u: URL, home: URL) -> Bool {
        guard let tipo = huggingFaceTipo(u.path), tipo != S_IFLNK else { return false }
        return huggingFaceSinPuntos(u.path).hasPrefix(huggingFaceSinPuntos(home.path) + "/")
            && Escaner.sePuedeQuitar(u, admin: false)
    }

    /// Une `ruta` a `carpeta` (si es relativa) y quita «.» y «..» sin consultar el disco.
    static func huggingFaceSinPuntos(_ ruta: String, desde carpeta: String = "/") -> String {
        var partes: [Substring] = []
        for parte in ((ruta.hasPrefix("/") ? "" : carpeta + "/") + ruta).split(separator: "/") {
            if parte == "." { continue }
            if parte == ".." {
                _ = partes.popLast()
                continue
            }
            partes.append(parte)
        }
        return "/" + partes.joined(separator: "/")
    }

    /// Un commit (lo que guardan refs/ y como se llaman las carpetas de snapshots/): solo dígitos hexadecimales.
    static func huggingFaceEsCommit(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy({ $0.isHexDigit })
    }

    /// Un nombre que se puede meter en una ruta con comodines: no oculto, sin «/» y sin «*», «?» ni «[».
    static func huggingFaceNombreSeguro(_ n: String) -> Bool {
        !n.isEmpty && !n.hasPrefix(".") && !n.contains("/") && !n.contains("*") && !n.contains("?") && !n.contains("[")
    }

    /// El tipo de una ruta (S_IFDIR, S_IFREG, S_IFLNK…) sin seguir enlaces; `nil` si no existe o no se puede leer.
    private static func huggingFaceTipo(_ ruta: String) -> mode_t? {
        var st = stat()
        guard lstat(ruta, &st) == 0 else { return nil }
        return st.st_mode & S_IFMT
    }

    /// Una carpeta de verdad: no un enlace a una carpeta.
    private static func huggingFaceEsCarpetaReal(_ ruta: String) -> Bool {
        huggingFaceTipo(ruta) == S_IFDIR
    }

    /// Las subcarpetas de verdad (no ocultas) de una carpeta, por orden.
    private static func huggingFaceSubcarpetas(_ carpeta: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: carpeta)) ?? [])
            .filter { !$0.hasPrefix(".") && huggingFaceEsCarpetaReal(carpeta + "/" + $0) }
            .sorted()
    }

    /// Recorre una carpeta sin seguir enlaces y pasa cada entrada (con su `lstat`) a `visitar`, que devuelve `false`
    /// para parar. Devuelve cuántas entradas vio, o `nil` si algo no se pudo leer, si había más de `maximo` o si
    /// `visitar` paró antes.
    private static func huggingFaceRecorrer(_ carpeta: String, maximo: Int, _ visitar: (String, stat) -> Bool) -> Int? {
        var pendientes = [carpeta]
        var vistas = 0
        while let actual = pendientes.popLast() {
            guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: actual) else { return nil }
            for n in nombres {
                vistas += 1
                let ruta = actual + "/" + n
                var st = stat()
                guard vistas <= maximo, lstat(ruta, &st) == 0, visitar(ruta, st) else { return nil }
                if (st.st_mode & S_IFMT) == S_IFDIR { pendientes.append(ruta) }
            }
        }
        return vistas
    }
}
