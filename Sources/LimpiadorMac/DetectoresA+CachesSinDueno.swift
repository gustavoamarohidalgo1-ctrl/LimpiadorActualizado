import Foundation

/// Cachés que el análisis general se salta: las que las apps y servicios de Apple guardan en su contenedor
/// (~/Library/Containers/com.apple.…/Data/Library/Caches) y las carpetas de ~/.cache de las que no se ocupa nadie más.
/// Solo lo que lleva días sin cambios y que nada tiene abierto; nada se marca solo.
extension Escaner {
    func detectoresA_CachesSinDueno(_ c: Contexto) -> [Elemento] {
        Self.cachesSinDuenoElementos(c, home: Rutas.home, abiertos: c.memoria.archivosAbiertos(), ahora: Date())
    }

    /// Todo el grupo sobre una carpeta personal cualquiera (para probarlo). Si no se sabe qué tienen abierto los
    /// programas, no se ofrece nada.
    static func cachesSinDuenoElementos(_ c: Contexto, home: URL, abiertos: ArchivosAbiertos, ahora: Date) -> [Elemento] {
        guard abiertos.disponible else { return [] }
        let patrones = Catalogo.reglas.map(\.patron)
        var r: [Elemento] = []
        // Sin Acceso total al disco, macOS no deja mirar dentro de los contenedores.
        if c.accesoTotal { r += cachesSinDuenoDeApple(c, home: home, patrones: patrones, abiertos: abiertos, ahora: ahora) }
        r += cachesSinDuenoXDG(c, home: home, patrones: patrones, abiertos: abiertos, ahora: ahora)
        return r
    }

    // MARK: Apps y servicios de Apple

    /// Contenedores de Apple que aquí no se tocan (en minúsculas; también lo que empieza así): mapas sin conexión,
    /// contraseñas y llaveros, Mail, Mensajes y Libros (guardan cosas que importan junto a sus cachés) y los
    /// salvapantallas de otros desarrolladores (tienen sus propias reglas).
    private static let cachesSinDuenoAppleExcluidos = [
        "com.apple.geod", "com.apple.maps", "com.apple.clouddocs", "com.apple.fileprovider", "com.apple.passwords",
        "com.apple.keychain", "com.apple.security", "com.apple.mail", "com.apple.mobilesms", "com.apple.ibooks",
        "com.apple.bkagentservice", "com.apple.screensaver.engine.legacyscreensaver",
    ]

    /// Lo que nunca se ofrece dentro de la caché de un contenedor (en minúsculas): lo que macOS no deja tocar, documentos
    /// que se están importando (Inbox), guardados a medias (TemporaryItems), el estado de iCloud y de otros servicios
    /// del sistema (como en ~/Library/Caches) y las descargas en segundo plano.
    private static let cachesSinDuenoAppleHijosExcluidos: Set<String> = [
        "com.apple.e5rt.e5bundlecache", "inbox", "temporaryitems", "cloudkit", "familycircle", "passkit", "geoservices",
        "animoji", "com.apple.bird", "com.apple.nsurlsessiond",
    ]

    /// Un elemento por contenedor de Apple con lo que hay en su Data/Library/Caches sin cambios en 2 días, carpeta a
    /// carpeta (nunca Caches entera). Se salta el contenedor si su app está abierta o si el catálogo ya trata sus cachés.
    static func cachesSinDuenoDeApple(_ c: Contexto, home: URL, patrones: [String], abiertos: ArchivosAbiertos,
                                     ahora: Date) -> [Elemento] {
        let raiz = home.appendingPathComponent("Library/Containers")
        guard cachesSinDuenoEsCarpetaReal(raiz.path),
              let contenedores = try? FileManager.default.contentsOfDirectory(atPath: raiz.path) else { return [] }
        let limite = ahora.addingTimeInterval(-2 * 86_400)
        var r: [Elemento] = []
        for x in contenedores.sorted() where x.hasPrefix("com.apple.") {
            // Con la app abierta, sus cachés están en uso.
            guard !cachesSinDuenoAppleExcluido(x), !cachesSinDuenoContenedorCubierto(x, patrones: patrones),
                  c.procesos.appAbierta([x]) == nil else { continue }
            let contenedor = raiz.appendingPathComponent(x)
            let caches = contenedor.appendingPathComponent("Data/Library/Caches")
            // Todo el camino tiene que ser de carpetas de verdad: un enlace llevaría a otra parte.
            let camino = [contenedor.path, contenedor.path + "/Data", contenedor.path + "/Data/Library", caches.path]
            guard !Seguridad.esIntocable(contenedor.path), camino.allSatisfy({ cachesSinDuenoEsCarpetaReal($0) }),
                  let hijos = try? FileManager.default.contentsOfDirectory(atPath: caches.path) else { continue }
            var rutas: [URL] = []
            var ultimo: Date?
            for n in hijos.sorted() where !cachesSinDuenoAppleHijoExcluido(n) {
                let u = caches.appendingPathComponent(n)
                guard let tipo = cachesSinDuenoTipo(u.path), tipo == S_IFDIR || tipo == S_IFREG,
                      // Un archivo suelto de una base de datos no se separa del resto: se estropearía.
                      tipo == S_IFDIR || !cachesSinDuenoEsBaseDeDatos(n),
                      let fecha = cachesSinDuenoSinUso(u, carpeta: tipo == S_IFDIR, c, abiertos: abiertos, limite: limite),
                      cachesSinDuenoOfrecible(u, home: home) else { continue }
                rutas.append(u)
                ultimo = max(ultimo ?? fecha, fecha)
            }
            guard !rutas.isEmpty else { continue }
            let app = c.apps.nombreApp(para: x) ?? x
            r.append(Elemento(
                nombre: "Caché de \(app) (Apple)",
                detalle: "Cachés que \(app) guarda en su contenedor (\(Formato.listaCorta(rutas.map(\.lastPathComponent)))).",
                consecuencia: "\(app) las vuelve a crear cuando las necesita. Tus documentos y ajustes no se tocan.",
                rutas: rutas, ultimoUso: ultimo, categoria: .cachesApps, riesgo: .seguro, seleccionado: false,
                motivos: [.bien("arrow.triangle.2.circlepath", "Solo cachés",
                                "Solo se borran carpetas de caché sin cambios en los últimos 2 días.")],
                enUso: .app(nombre: app, claves: [x, app]), dueno: app))
        }
        return r
    }

    /// ¿Es un contenedor de Apple que aquí no se toca? Los de la lista y cualquiera de iCloud («cloud» en el nombre):
    /// el estado de la sincronización no se toca.
    static func cachesSinDuenoAppleExcluido(_ contenedor: String) -> Bool {
        let x = contenedor.lowercased()
        return x.contains("cloud") || cachesSinDuenoAppleExcluidos.contains { x.hasPrefix($0) }
    }

    /// ¿Se deja siempre este hijo de la caché de un contenedor? Los ocultos, los de la lista y los mapas sin conexión.
    static func cachesSinDuenoAppleHijoExcluido(_ nombre: String) -> Bool {
        let n = nombre.lowercased()
        return n.hasPrefix(".") || n.contains("offline") || cachesSinDuenoAppleHijosExcluidos.contains(n)
    }

    /// ¿Alguna regla del catálogo ya trata las cachés de este contenedor (safari-contenedor, apple-iwork-cache,
    /// apple-mail-cache…)? Una cuyo patrón empieza por «~/Library/Containers/», pasa por «/Data/Library/Caches» y cuyo
    /// contenedor (puede llevar *) coincide con este.
    static func cachesSinDuenoContenedorCubierto(_ contenedor: String, patrones: [String]) -> Bool {
        let x = contenedor.lowercased()
        let prefijo = "~/Library/Containers/"
        return patrones.contains { p in
            guard p.hasPrefix(prefijo), p.contains("/Data/Library/Caches"),
                  let nombre = p.dropFirst(prefijo.count).split(separator: "/").first else { return false }
            return fnmatch(nombre.lowercased(), x, 0) == 0
        }
    }

    // MARK: ~/.cache

    /// Carpetas de ~/.cache que ya analiza otra parte (cachés de desarrollo, Puppeteer, Hugging Face, los detectores
    /// de modelos y reglas del catálogo) o que pueden guardar algo que importa: lm-studio puede ser la carpeta de
    /// LM Studio con tus chats, y la caché de renv (R) la enlazan tus proyectos de R.
    private static let cachesSinDuenoYaAnalizadas: Set<String> = [
        "pip", "uv", "pre-commit", "node", "firebase", "codex-runtimes", "torch", "selenium", "puppeteer", "huggingface",
        "lm-studio", "gpt4all", "whisper", "prisma", "kagglehub", "chroma", "clip", "suno", "wandb", "darktable", "wine",
        "chrome-devtools-mcp", "r", "renv",
    ]

    /// Un elemento por cada carpeta de ~/.cache que no trata nadie más: sin cambios en las últimas 24 horas, sin nada
    /// abierto y sin nada que parezca tuyo (claves, sesiones, bases de datos, historial, documentos…).
    static func cachesSinDuenoXDG(_ c: Contexto, home: URL, patrones: [String], abiertos: ArchivosAbiertos,
                                  ahora: Date) -> [Elemento] {
        let cache = home.appendingPathComponent(".cache")
        guard cachesSinDuenoEsCarpetaReal(cache.path),
              let nombres = try? FileManager.default.contentsOfDirectory(atPath: cache.path) else { return [] }
        let limite = ahora.addingTimeInterval(-86_400)
        var r: [Elemento] = []
        for n in nombres.sorted() where !n.hasPrefix(".") && !cachesSinDuenoCacheCubierta(n, patrones: patrones) {
            let u = cache.appendingPathComponent(n)
            guard cachesSinDuenoEsCarpetaReal(u.path), !cachesSinDuenoNombreDelicado(n),
                  let fecha = cachesSinDuenoSinUso(u, carpeta: true, c, abiertos: abiertos, limite: limite),
                  cachesSinDuenoOfrecible(u, home: home), c.indice.sensibles(dentro: [u]).isEmpty,
                  !c.indice.contenido(de: [u]).esPersonal, cachesSinDuenoSinNadaDelicado(u) else { continue }
            r.append(Elemento(
                nombre: "~/.cache/\(n)",
                detalle: "Caché de \(n) en tu carpeta ~/.cache (sin cambios desde \(Formato.haceCuanto(fecha).lowercased())).",
                consecuencia: "Si algún programa la usa, la vuelve a crear; el primer uso puede ir más lento o volver a descargar cosas.",
                rutas: [u], ultimoUso: fecha, categoria: .herramientas, riesgo: .revisar, seleccionado: false,
                motivos: [.info("questionmark.folder.fill", "Dueño sin confirmar", "No sé con certeza qué programa la creó.")],
                enUso: .proceso(nombre: n, patron: "/.cache/" + n.lowercased()), dueno: n))
        }
        return r
    }

    /// ¿Ya se ocupa otra parte del análisis de esta carpeta de ~/.cache? La lista fija, o alguna regla del catálogo
    /// cuyo patrón empieza por «~/.cache/» y cuyo primer nombre (puede llevar *) coincide con este.
    static func cachesSinDuenoCacheCubierta(_ nombre: String, patrones: [String]) -> Bool {
        let n = nombre.lowercased()
        if cachesSinDuenoYaAnalizadas.contains(n) { return true }
        let prefijo = "~/.cache/"
        return patrones.contains { p in
            guard p.hasPrefix(prefijo), let primero = p.dropFirst(prefijo.count).split(separator: "/").first else { return false }
            return fnmatch(primero.lowercased(), n, 0) == 0
        }
    }

    /// Nombres (en minúsculas) que delatan algo que no se debe borrar sin mirar: claves y sesiones iniciadas, chats,
    /// código con su historial (git) y entornos de Python que algún programa puede estar usando.
    private static let cachesSinDuenoNombresDelicados: Set<String> = [
        "token", "tokens", "stored_tokens", "login data", ".env", ".netrc", "conversations", "chats", "threads",
        "memories", ".git", "pyvenv.cfg",
    ]
    private static let cachesSinDuenoPrefijosDelicados = ["credentials", "access_token", "refresh_token", "token.", "tokens."]
    private static let cachesSinDuenoSufijosDelicados = ["_token", "-token", ".token", ".pem", ".key", ".p12", ".pfx", ".jks",
                                                         ".keystore"]
    private static let cachesSinDuenoPalabrasDelicadas = ["secret", "password", "cookie", "session", "keychain", "history"]

    /// ¿Delata este nombre algo que no se debe borrar sin mirar? Claves, credenciales, sesiones, bases de datos (pueden
    /// ser historial o datos de una app), historial, chats, repositorios y entornos de Python. «tokenizer.json» y
    /// «special_tokens_map.json» (de los modelos de IA) no cuentan.
    static func cachesSinDuenoNombreDelicado(_ nombre: String) -> Bool {
        let n = nombre.lowercased()
        if cachesSinDuenoNombresDelicados.contains(n) || cachesSinDuenoEsBaseDeDatos(n) { return true }
        if n.hasPrefix("auth") && n.hasSuffix(".json") { return true }
        if cachesSinDuenoPrefijosDelicados.contains(where: { n.hasPrefix($0) }) { return true }
        if cachesSinDuenoSufijosDelicados.contains(where: { n.hasSuffix($0) }) { return true }
        return cachesSinDuenoPalabrasDelicadas.contains { n.contains($0) }
    }

    /// ¿Es parte de una base de datos (el archivo o su diario: -wal, -shm, -journal)?
    static func cachesSinDuenoEsBaseDeDatos(_ nombre: String) -> Bool {
        let n = nombre.lowercased()
        return [".db", ".sqlite", ".sqlite3", ".sqlitedb", ".realm", "-wal", "-shm", "-journal"].contains { n.hasSuffix($0) }
    }

    /// Recorre la carpeta sin seguir enlaces (como mucho `maximo` entradas). `false` si algún nombre delata algo que no
    /// se debe borrar sin mirar, si hay más entradas de la cuenta o si alguna parte no se puede leer: entonces no se
    /// sabe qué hay dentro.
    static func cachesSinDuenoSinNadaDelicado(_ carpeta: URL, maximo: Int = 50_000) -> Bool {
        var pendientes = [carpeta.path]
        var vistas = 0
        while let actual = pendientes.popLast() {
            guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: actual) else { return false }
            for n in nombres {
                vistas += 1
                let ruta = actual + "/" + n
                guard vistas <= maximo, !cachesSinDuenoNombreDelicado(n), let tipo = cachesSinDuenoTipo(ruta) else { return false }
                if tipo == S_IFDIR { pendientes.append(ruta) }
            }
        }
        return true
    }

    // MARK: Utilidades del grupo

    /// La regla de actividad: una carpeta tiene que estar en el índice (de una pequeña no se sabe la actividad de dentro)
    /// y llevar sin cambios desde antes de `limite`; un archivo suelto, por su fecha de modificación. Y que ningún
    /// programa tenga abierto nada de dentro. Devuelve la última actividad, o `nil` si no vale.
    static func cachesSinDuenoSinUso(_ u: URL, carpeta: Bool, _ c: Contexto, abiertos: ArchivosAbiertos,
                                     limite: Date) -> Date? {
        if carpeta && c.indice.info(u.path) == nil { return nil }
        let ultima = carpeta ? c.indice.masReciente(de: [u]) : Fechas.modificacion(u)
        guard let fecha = ultima, fecha < limite, !abiertos.tieneAbierto(u.path) else { return nil }
        return fecha
    }

    /// Lo único que se ofrece: existe, no es un enlace, está dentro de `home` (también siguiendo los enlaces del camino),
    /// no es intocable ni contiene nada intocable y se puede mover a la Papelera.
    static func cachesSinDuenoOfrecible(_ u: URL, home: URL) -> Bool {
        guard let tipo = cachesSinDuenoTipo(u.path), tipo != S_IFLNK, u.path.hasPrefix(home.path + "/"),
              Seguridad.normalizada(u.path).hasPrefix(Seguridad.normalizada(home.path) + "/") else { return false }
        return !Seguridad.esIntocable(u.path) && Escaner.sePuedeQuitar(u, admin: false)
    }

    /// El tipo de una ruta (S_IFDIR, S_IFREG, S_IFLNK…) sin seguir enlaces; `nil` si no existe o no se puede leer.
    private static func cachesSinDuenoTipo(_ ruta: String) -> mode_t? {
        var st = stat()
        guard lstat(ruta, &st) == 0 else { return nil }
        return st.st_mode & S_IFMT
    }

    /// Una carpeta de verdad: no un enlace a una carpeta.
    private static func cachesSinDuenoEsCarpetaReal(_ ruta: String) -> Bool {
        cachesSinDuenoTipo(ruta) == S_IFDIR
    }
}
