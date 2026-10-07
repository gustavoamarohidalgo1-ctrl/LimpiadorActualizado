import Foundation

/// Versiones viejas que se quedan al actualizar herramientas de desarrollo: IDEs instalados con JetBrains Toolbox 1.x,
/// agentes de IA de terminal (Claude Code, Cursor Agent, GitHub Copilot CLI y el Claude Code de la app Claude), JDKs
/// repetidos en ~/Library/Java y copias de Xcode en ~/Applications. Nada de esto se regenera solo: nunca se marca por
/// defecto, y si no se sabe cuál es la versión activa o algo no se puede leer, esa parte no ofrece nada.
/// Las cachés, registros y ajustes de cada versión de los IDEs no son de aquí: los ofrece `versionesAnterioresDeIDEs()`.
extension Escaner {
    func detectoresA_VersionesIDEsYAgentes(_ c: Contexto) -> [Elemento] {
        Self.versionesIDEsYAgentesElementos(c, home: Rutas.home)
    }

    /// Todo el grupo sobre una carpeta personal cualquiera.
    static func versionesIDEsYAgentesElementos(_ c: Contexto, home: URL) -> [Elemento] {
        // Lo que tienen abierto los programas (lsof): solo se pide si hay algo que ofrecer, y una vez por análisis.
        let abierto: (String) -> Bool = { c.memoria.archivosAbiertos().tieneAbierto($0) }
        return versionesIDEsYAgentesToolbox(c, home: home, abierto: abierto)
            + versionesIDEsYAgentesAgentes(c, home: home, abierto: abierto)
            + versionesIDEsYAgentesJDKs(c, home: home, abierto: abierto)
            + versionesIDEsYAgentesXcode(c, home: home, abierto: abierto)
    }

    // MARK: - JetBrains Toolbox 1.x

    /// IDEs instalados con JetBrains Toolbox 1.x: guarda una copia completa de cada build en
    /// «Toolbox/apps/<producto>/ch-N/<build>» (y sus plugins en «<build>.plugins») por si quieres volver atrás.
    static func versionesIDEsYAgentesToolbox(_ c: Contexto, home: URL, abierto: (String) -> Bool) -> [Elemento] {
        // Si JetBrains ya no está instalado, «Restos de apps borradas» ofrece la carpeta entera.
        guard c.apps.estaInstalado(carpeta: "JetBrains") else { return [] }
        let casa = home.standardizedFileURL
        let fecha: (URL) -> Date? = { c.indice.masReciente(de: [$0]) ?? Fechas.modificacion($0) }
        var r: [Elemento] = []
        for ch in Escaner.expandir(casa.path + "/Library/Application Support/JetBrains/Toolbox/apps/*/ch-*") {
            guard versionesIDEsYAgentesEsCarpetaReal(ch.path),
                  let canal = versionesIDEsYAgentesToolboxCanal(ch, home: casa, procesos: c.procesos.lineas,
                                                                abierto: abierto, fecha: fecha) else { continue }
            let producto = ch.deletingLastPathComponent().lastPathComponent
            let otroCanal = ch.lastPathComponent == "ch-0" ? "" : ", \(ch.lastPathComponent)"
            r.append(Elemento(
                nombre: "Versiones anteriores de \(producto) (Toolbox\(otroCanal))",
                detalle: "Copias completas que dejó JetBrains Toolbox: \(Formato.listaCorta(canal.builds)).",
                consecuencia: "Nada: Toolbox usa la versión \(canal.activa). Si quieres volver a una de estas, Toolbox la descarga otra vez.",
                rutas: canal.rutas, categoria: .desarrollo, riesgo: .seguro, seleccionado: false,
                motivos: [.bien("clock.arrow.circlepath", "Versión anterior", "Ya usas la \(canal.activa).")],
                enUso: .app(nombre: "JetBrains Toolbox", claves: ["com.jetbrains.toolbox", "JetBrains Toolbox"]),
                dueno: "JetBrains Toolbox"))
        }
        return r
    }

    /// Lo que sobra en un canal de Toolbox («…/apps/IDEA-U/ch-0»): las builds viejas, en orden, y la ruta de cada una
    /// junto con su carpeta «.plugins». Se conservan siempre la de número más alto y la activa: la del enlace «current»,
    /// si lo hay, y la última del historial (`.history.json`); si ninguno de los dos la dice, la que se modificó por
    /// última vez. `nil` si no sobra nada, si no se puede saber cuál es la activa o si alguna build es un enlace.
    static func versionesIDEsYAgentesToolboxCanal(_ ch: URL, home: URL, procesos: [String], abierto: (String) -> Bool,
                                                   fecha: (URL) -> Date?) -> (activa: String, builds: [String], rutas: [URL])? {
        guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: ch.path) else { return nil }
        var builds: [String] = []
        for n in nombres.sorted() where n.first?.isNumber == true && !n.hasSuffix(".plugins") {
            let ruta = ch.appendingPathComponent(n).path
            if versionesIDEsYAgentesEsEnlace(ruta) { return nil }
            if versionesIDEsYAgentesEsCarpetaReal(ruta) { builds.append(n) }
        }
        guard builds.count > 1 else { return nil }

        var conservar = versionesIDEsYAgentesLasMasAltas(builds)
        let enlace = versionesIDEsYAgentesActiva(enlace: ch.appendingPathComponent("current"), carpeta: ch)
        let historial = versionesIDEsYAgentesUltimaDelHistorial(ch.appendingPathComponent(".history.json"))
        let porEnlace: String? = enlace.flatMap { builds.contains($0) ? $0 : nil }
        let porHistorial: String? = historial.flatMap { builds.contains($0) ? $0 : nil }
        var activa = porEnlace ?? porHistorial
        if let porEnlace { conservar.insert(porEnlace) }
        if let porHistorial { conservar.insert(porHistorial) }
        if activa == nil {
            // Sin enlace ni historial: la que se usó por última vez (con empate, todas). Sin fechas no se sabe.
            var fechas: [String: Date] = [:]
            for b in builds {
                guard let f = fecha(ch.appendingPathComponent(b)) else { return nil }
                fechas[b] = f
            }
            let ultima = fechas.values.max()
            let recientes = builds.filter { fechas[$0] == ultima }
            conservar.formUnion(recientes)
            activa = recientes.max { versionesIDEsYAgentesOrden($0, $1) }
        }
        guard let usada = activa else { return nil }

        var sobrantes: [String] = []
        var rutas: [URL] = []
        for b in builds.sorted(by: { versionesIDEsYAgentesOrden($0, $1) }) where !conservar.contains(b) {
            let u = ch.appendingPathComponent(b)
            // Si el IDE de esa build está abierto, su ruta sale en la lista de procesos.
            let patron = u.path.lowercased() + "/"
            guard !procesos.contains(where: { $0.contains(patron) }),
                  versionesIDEsYAgentesOfrecible(u, home: home, abierto: abierto) else { continue }
            sobrantes.append(b)
            rutas.append(u)
            let plugins = ch.appendingPathComponent(b + ".plugins")
            if versionesIDEsYAgentesEsCarpetaReal(plugins.path),
               versionesIDEsYAgentesOfrecible(plugins, home: home, abierto: abierto) {
                rutas.append(plugins)
            }
        }
        guard !sobrantes.isEmpty else { return nil }
        return (activa: usada, builds: sobrantes, rutas: rutas)
    }

    /// La build que Toolbox instaló o activó por última vez, según su historial.
    static func versionesIDEsYAgentesUltimaDelHistorial(_ archivo: URL) -> String? {
        guard let datos = try? Data(contentsOf: archivo),
              let raiz = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let historial = raiz["history"] as? [[String: Any]], let ultima = historial.last,
              let item = ultima["item"] as? [String: Any],
              let build = item["build"] as? String, !build.isEmpty else { return nil }
        return build
    }

    // MARK: - Agentes de IA de terminal

    /// Claude Code, Cursor Agent y GitHub Copilot CLI se actualizan solos y guardan cada versión en su carpeta de
    /// versiones; la app Claude hace lo mismo con el Claude Code que trae. De cada carpeta se conservan siempre la versión
    /// activa y la más alta (que puede ser la siguiente, ya descargada y todavía sin estrenar).
    ///
    /// En Claude Code, Cursor Agent y Copilot no hay `enUso`: la versión activa suele estar siempre en marcha y un patrón
    /// general («claude», «copilot») impediría limpiar nunca. La protección va por versión: no se ofrece la que sale en
    /// la lista de procesos ni la que algún programa tiene abierta.
    static func versionesIDEsYAgentesAgentes(_ c: Contexto, home: URL, abierto: (String) -> Bool) -> [Elemento] {
        let casa = home.standardizedFileURL
        let procesos = c.procesos.lineas
        let bin = casa.appendingPathComponent(".local/bin")
        var r: [Elemento] = []

        // a) Claude Code: «~/.local/bin/claude» es un enlace a la versión activa. Las que tienen su «.lock» en
        //    ~/.local/state/claude/locks las está usando alguna sesión: también se quedan.
        let claude = casa.appendingPathComponent(".local/share/claude/versions")
        let bloqueadas = versionesIDEsYAgentesBloqueadas(en: casa.appendingPathComponent(".local/state/claude/locks"))
        if let a = versionesIDEsYAgentesPorEnlace(claude, enlace: bin.appendingPathComponent("claude"), ademas: bloqueadas,
                                                   home: casa, procesos: procesos, abierto: abierto) {
            r.append(versionesIDEsYAgentesElementoAgente("Claude Code", activas: [a.activa], rutas: a.rutas, enUso: nil,
                                                        dueno: "Claude Code"))
        }

        // b) Cursor Agent: el enlace es «cursor-agent» o, si no está, «agent».
        var enlaceCursor = bin.appendingPathComponent("cursor-agent")
        if !Rutas.existeSinSeguir(enlaceCursor.path) { enlaceCursor = bin.appendingPathComponent("agent") }
        let cursor = casa.appendingPathComponent(".local/share/cursor-agent/versions")
        if let a = versionesIDEsYAgentesPorEnlace(cursor, enlace: enlaceCursor, home: casa, procesos: procesos,
                                                   abierto: abierto) {
            r.append(versionesIDEsYAgentesElementoAgente("Cursor Agent", activas: [a.activa], rutas: a.rutas, enUso: nil,
                                                        dueno: "Cursor Agent"))
        }

        // c) GitHub Copilot CLI: una carpeta por plataforma. Usa la versión más alta (y la del enlace, si lo hay).
        var activasCopilot: [String] = []
        var rutasCopilot: [URL] = []
        let pkg = casa.appendingPathComponent(".copilot/pkg")
        for n in ((try? FileManager.default.contentsOfDirectory(atPath: pkg.path)) ?? []).sorted() {
            let plataforma = pkg.appendingPathComponent(n)
            guard versionesIDEsYAgentesEsCarpetaReal(plataforma.path) else { continue }
            let versiones = versionesIDEsYAgentesVersiones(en: plataforma)
            let nombres = versiones.map { $0.lastPathComponent }
            guard let masAlta = nombres.max(by: { versionesIDEsYAgentesOrden($0, $1) }) else { continue }
            var conservar = Set<String>()
            var activa = masAlta
            if let delEnlace = versionesIDEsYAgentesActiva(enlace: bin.appendingPathComponent("copilot"), carpeta: plataforma) {
                conservar.insert(delEnlace)
                if nombres.contains(delEnlace) { activa = delEnlace }
            }
            let sobran = versionesIDEsYAgentesSobrantes(versiones, conservar: conservar, home: casa, procesos: procesos,
                                                        abierto: abierto)
            guard !sobran.isEmpty else { continue }
            activasCopilot.append(activa)
            rutasCopilot += sobran
        }
        if !rutasCopilot.isEmpty {
            r.append(versionesIDEsYAgentesElementoAgente("GitHub Copilot CLI", activas: activasCopilot, rutas: rutasCopilot,
                                                        enUso: nil, dueno: "GitHub Copilot CLI"))
        }

        // d) El Claude Code de la app Claude, en «claude-code» y «claude-code-vm» (cada carpeta por su lado): solo con la
        //    app instalada y cerrada. Ningún enlace dice cuál usa: se conservan la más alta, la que se usó por última vez
        //    y la que pide el «.sdk-version» de esa misma carpeta.
        if c.apps.bundleIDs.contains("com.anthropic.claudefordesktop"),
           c.procesos.appAbierta(["com.anthropic.claudefordesktop", "Claude"]) == nil {
            let fecha: (URL) -> Date? = { c.indice.masReciente(de: [$0]) ?? Fechas.modificacion($0) }
            let soporte = casa.appendingPathComponent("Library/Application Support/Claude")
            var activas: [String] = []
            var rutas: [URL] = []
            for sub in ["claude-code", "claude-code-vm"] {
                let carpeta = soporte.appendingPathComponent(sub)
                let sdk = try? String(contentsOf: carpeta.appendingPathComponent(".sdk-version"), encoding: .utf8)
                let pedida = sdk?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let a = versionesIDEsYAgentesPorFecha(carpeta, ademas: pedida, home: casa, procesos: procesos,
                                                            abierto: abierto, fecha: fecha) else { continue }
                activas.append(a.activa)
                rutas += a.rutas
            }
            if !rutas.isEmpty {
                r.append(versionesIDEsYAgentesElementoAgente(
                    "Claude Code (app Claude)", activas: activas, rutas: rutas,
                    enUso: .app(nombre: "Claude", claves: ["com.anthropic.claudefordesktop", "Claude"]), dueno: "Claude"))
            }
        }
        return r
    }

    /// Las versiones que sobran en `carpeta` cuando la activa es la que señala `enlace` (`ademas`: otras que se quedan).
    /// `nil` si no se sabe cuál es la activa (no hay enlace, o lleva fuera de la carpeta o a una versión que no está) o
    /// si no sobra ninguna.
    static func versionesIDEsYAgentesPorEnlace(_ carpeta: URL, enlace: URL, ademas: Set<String> = [], home: URL,
                                               procesos: [String],
                                               abierto: (String) -> Bool) -> (activa: String, rutas: [URL])? {
        let versiones = versionesIDEsYAgentesVersiones(en: carpeta)
        guard versiones.count > 1, let activa = versionesIDEsYAgentesActiva(enlace: enlace, carpeta: carpeta),
              versiones.contains(where: { $0.lastPathComponent == activa }) else { return nil }
        let sobran = versionesIDEsYAgentesSobrantes(versiones, conservar: ademas.union([activa]), home: home,
                                                    procesos: procesos, abierto: abierto)
        guard !sobran.isEmpty else { return nil }
        return (activa: activa, rutas: sobran)
    }

    /// Las versiones que sobran en `carpeta` cuando nada dice cuál es la activa: se conservan la más alta, la que se
    /// modificó por última vez (con empate, todas) y `ademas`, si es una de las que hay. `nil` si alguna fecha no se
    /// puede leer o si no sobra ninguna.
    static func versionesIDEsYAgentesPorFecha(_ carpeta: URL, ademas: String?, home: URL, procesos: [String],
                                              abierto: (String) -> Bool,
                                              fecha: (URL) -> Date?) -> (activa: String, rutas: [URL])? {
        let versiones = versionesIDEsYAgentesVersiones(en: carpeta)
        guard versiones.count > 1 else { return nil }
        var fechas: [String: Date] = [:]
        for v in versiones {
            guard let f = fecha(v) else { return nil }
            fechas[v.lastPathComponent] = f
        }
        guard let ultima = fechas.values.max() else { return nil }
        var conservar = Set(fechas.filter { $0.value == ultima }.map { $0.key })
        guard let reciente = conservar.max(by: { versionesIDEsYAgentesOrden($0, $1) }) else { return nil }
        var activa = reciente
        if let ademas, fechas[ademas] != nil {
            conservar.insert(ademas)
            activa = ademas
        }
        let sobran = versionesIDEsYAgentesSobrantes(versiones, conservar: conservar, home: home, procesos: procesos,
                                                    abierto: abierto)
        guard !sobran.isEmpty else { return nil }
        return (activa: activa, rutas: sobran)
    }

    /// De una carpeta de versiones, las que sobran, en orden: todas menos las de `conservar` y la más alta, y menos las
    /// que están en marcha (su ruta sale en la lista de procesos), las que tienen al lado un «<versión>.lock» (algo las
    /// está instalando o usando) y las que no se pueden ofrecer.
    static func versionesIDEsYAgentesSobrantes(_ versiones: [URL], conservar: Set<String>, home: URL, procesos: [String],
                                               abierto: (String) -> Bool) -> [URL] {
        let protegidas = conservar.union(versionesIDEsYAgentesLasMasAltas(versiones.map { $0.lastPathComponent }))
        var r: [URL] = []
        for v in versiones where !protegidas.contains(v.lastPathComponent) {
            let ruta = v.path.lowercased()
            guard !Rutas.existeSinSeguir(v.path + ".lock"), !procesos.contains(where: { $0.contains(ruta) }),
                  versionesIDEsYAgentesOfrecible(v, home: home, abierto: abierto) else { continue }
            r.append(v)
        }
        return r.sorted { versionesIDEsYAgentesOrden($0.lastPathComponent, $1.lastPathComponent) }
    }

    /// Lo que hay en una carpeta de versiones con nombre de versión (archivos o carpetas). Lo demás (ocultos,
    /// «2.0.1.lock», «.sdk-version»…) ni cuenta ni se ofrece nunca. Vacío si la carpeta no se puede leer o si alguna
    /// versión es un enlace: no se sabe a qué apunta, así que mejor no tocar nada de esa carpeta.
    static func versionesIDEsYAgentesVersiones(en carpeta: URL) -> [URL] {
        guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path) else { return [] }
        var r: [URL] = []
        for n in nombres.sorted() where versionesIDEsYAgentesEsVersion(n) {
            let u = carpeta.appendingPathComponent(n)
            if versionesIDEsYAgentesEsEnlace(u.path) { return [] }
            r.append(u)
        }
        return r
    }

    /// Las versiones que tienen un «<versión>.lock» en `carpeta` (vacío si no existe o no se puede leer).
    static func versionesIDEsYAgentesBloqueadas(en carpeta: URL) -> Set<String> {
        let nombres = (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? []
        return Set(nombres.filter { $0.hasSuffix(".lock") }.map { String($0.dropLast(".lock".count)) })
    }

    /// «2.0.1», «0.0.339», «17.0.8.1», «2025.08.25-896bbe1», «1.0.0-beta.2»: tres números y, si acaso, más números o
    /// un sufijo que empieza por «-» o «+». Más estricto que «x.y.z» seguido de cualquier cosa: «2.0.1.lock» o
    /// «2.0.1.tmp» no son versiones (y no deben pasar por la más alta).
    static func versionesIDEsYAgentesEsVersion(_ nombre: String) -> Bool {
        versionesIDEsYAgentesPatronVersion.firstMatch(in: nombre, range: NSRange(nombre.startIndex..., in: nombre)) != nil
    }

    private static let versionesIDEsYAgentesPatronVersion = try! NSRegularExpression(pattern: #"^\d+\.\d+\.\d+(\.\d+)*([-+].*)?$"#)

    /// A qué versión lleva `enlace` una vez resueltos los enlaces, si apunta dentro de `carpeta`: «~/.local/bin/claude»
    /// → «…/versions/2.0.1» da «2.0.1»; «…/versions/2025.08.25-x/cursor-agent» da «2025.08.25-x».
    static func versionesIDEsYAgentesActiva(enlace: URL, carpeta: URL) -> String? {
        guard Rutas.existeSinSeguir(enlace.path) else { return nil }
        let destino = enlace.resolvingSymlinksInPath().path
        let base = carpeta.resolvingSymlinksInPath().path + "/"
        guard destino.hasPrefix(base) else { return nil }
        return destino.dropFirst(base.count).split(separator: "/").first.map(String.init)
    }

    /// El elemento con las versiones viejas de una herramienta. `activas`: las que usa (una por carpeta de versiones).
    static func versionesIDEsYAgentesElementoAgente(_ herramienta: String, activas: [String], rutas: [URL], enUso: EnUso?,
                                                    dueno: String) -> Elemento {
        let nombres = Array(Set(rutas.map { $0.lastPathComponent })).sorted { versionesIDEsYAgentesOrden($0, $1) }
        let usadas = Array(Set(activas)).sorted { versionesIDEsYAgentesOrden($0, $1) }
        let cuales: String
        switch usadas.count {
        case 0: cuales = "otra versión"
        case 1: cuales = "la versión \(usadas[0])"
        default: cuales = "las versiones \(Formato.lista(usadas))"
        }
        let cuantas = nombres.count == 1 ? "1 versión" : "\(nombres.count) versiones"
        return Elemento(
            nombre: "Versiones anteriores de \(herramienta)",
            detalle: "\(cuantas) que ya no usas: \(Formato.listaCorta(nombres)).",
            consecuencia: "Nada: usas \(cuales); si alguna vez hace falta otra, la herramienta la descarga sola.",
            rutas: rutas, categoria: .desarrollo, riesgo: .seguro, seleccionado: false,
            motivos: [.bien("clock.arrow.circlepath", "Versiones anteriores",
                            "Se quedaron de actualizaciones anteriores; ya usas \(cuales).")],
            enUso: enUso, dueno: dueno)
    }

    // MARK: - JDKs repetidos

    /// Un JDK de ~/Library/Java/JavaVirtualMachines y lo que dice de sí mismo.
    struct VersionesIDEsYAgentesJDK {
        let url: URL
        let version: String
        let proveedor: String
        /// Proveedor, distribución, versión mayor y arquitectura: dos JDKs del mismo grupo se pueden cambiar uno por otro.
        let grupo: String
    }

    /// Archivos de la terminal donde se fija JAVA_HOME o DEVELOPER_DIR.
    static let versionesIDEsYAgentesArchivosDeTerminal = [".zshrc", ".zprofile", ".zshenv", ".bash_profile", ".bashrc",
                                                           ".profile"]

    /// JDKs que descargaron IntelliJ IDEA o Android Studio en tu carpeta (nunca los de /Library/Java, que son del
    /// sistema) y quedaron repetidos: del mismo proveedor, distribución, versión mayor y arquitectura se conserva el más
    /// nuevo. No se ofrece ninguno que nombre un ajuste o un proyecto, ni uno que esté en marcha.
    static func versionesIDEsYAgentesJDKs(_ c: Contexto, home: URL, abierto: (String) -> Bool) -> [Elemento] {
        let casa = home.standardizedFileURL
        let carpeta = casa.appendingPathComponent("Library/Java/JavaVirtualMachines")
        guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: carpeta.path) else { return [] }
        var grupos: [String: [VersionesIDEsYAgentesJDK]] = [:]
        for n in nombres.sorted() where !n.hasPrefix(".") {
            let u = carpeta.appendingPathComponent(n)
            guard versionesIDEsYAgentesEsCarpetaReal(u.path), let jdk = versionesIDEsYAgentesDatosJDK(u) else { continue }
            grupos[jdk.grupo, default: []].append(jdk)
        }

        // De cada grupo se conserva el de versión más alta, si de verdad tiene su java; los demás son candidatos.
        var candidatos: [(viejo: VersionesIDEsYAgentesJDK, nuevo: VersionesIDEsYAgentesJDK)] = []
        for lista in grupos.values where lista.count > 1 {
            let orden = lista.sorted { a, b in
                let comparacion = versionesIDEsYAgentesCompararJava(a.version, b.version)
                if comparacion == .orderedSame { return a.url.lastPathComponent < b.url.lastPathComponent }
                return comparacion == .orderedAscending
            }
            guard let nuevo = orden.last,
                  Rutas.existe(nuevo.url.appendingPathComponent("Contents/Home/bin/java")) else { continue }
            for viejo in orden.dropLast() { candidatos.append((viejo: viejo, nuevo: nuevo)) }
        }
        // Los ajustes y los proyectos solo se leen si hay candidatos; si alguno no se puede leer, no se ofrece ninguno.
        guard !candidatos.isEmpty,
              let textos = versionesIDEsYAgentesReferenciasJava(home: casa, repos: c.indice.repos) else { return [] }

        var r: [Elemento] = []
        for (viejo, nuevo) in candidatos.sorted(by: { $0.viejo.url.path < $1.viejo.url.path }) {
            let nombre = viejo.url.lastPathComponent.lowercased()
            let patron = viejo.url.path.lowercased() + "/"
            // Una versión exacta («17.0.8», «1.8.0_392»; no «21» a secas) también lo nombra: «java_home -v 17.0.8».
            let version = viejo.version.lowercased()
            let exacta = version.contains("_") || version.filter({ $0 == "." }).count >= 2
            guard !textos.contains(where: { $0.contains(nombre) || (exacta && $0.contains(version)) }),
                  !c.procesos.lineas.contains(where: { $0.contains(patron) }),
                  versionesIDEsYAgentesOfrecible(viejo.url, home: casa, abierto: abierto) else { continue }
            r.append(Elemento(
                nombre: "Java \(viejo.version) (\(viejo.proveedor)) repetido",
                detalle: "Tienes la \(nuevo.version) del mismo Java en \(Formato.rutaCorta(nuevo.url)).",
                consecuencia: "Si algún proyecto pedía esta versión exacta, el IDE te ofrecerá descargarla otra vez.",
                rutas: [viejo.url], categoria: .desarrollo, riesgo: .revisar, seleccionado: false,
                motivos: [.info("cup.and.saucer.fill", "Otra copia del mismo Java",
                                "Es del mismo proveedor y versión mayor que la \(nuevo.version), y ningún ajuste ni proyecto que encontré la nombra.")],
                enUso: .proceso(nombre: "Java \(viejo.version)", patron: patron), dueno: "Java"))
        }
        return r
    }

    /// Versión, proveedor y grupo de un JDK según su archivo «release» o, si no lo tiene, su Info.plist.
    /// `nil` si no se pueden leer la versión y el proveedor: ese JDK ni se ofrece ni cuenta para los demás.
    static func versionesIDEsYAgentesDatosJDK(_ jdk: URL) -> VersionesIDEsYAgentesJDK? {
        var version = "", proveedor = "", distribucion = "", arquitectura = ""
        let release = jdk.appendingPathComponent("Contents/Home/release")
        if Rutas.existeSinSeguir(release.path) {
            guard let texto = try? String(contentsOf: release, encoding: .utf8) else { return nil }
            var valores: [String: String] = [:]
            for linea in texto.split(separator: "\n") {
                let partes = linea.split(separator: "=", maxSplits: 1)
                guard partes.count == 2 else { continue }
                let clave = partes[0].trimmingCharacters(in: .whitespaces)
                let valor = partes[1].trimmingCharacters(in: .whitespacesAndNewlines)
                valores[clave] = valor.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            version = valores["JAVA_VERSION"] ?? ""
            proveedor = valores["IMPLEMENTOR"] ?? ""
            arquitectura = valores["OS_ARCH"] ?? ""
            // «Temurin-17.0.8+7» → «Temurin-». GraalVM y el OpenJDK de Oracle comparten proveedor y no son lo mismo.
            distribucion = String((valores["IMPLEMENTOR_VERSION"] ?? "").prefix(while: { !$0.isNumber }))
            if valores["GRAALVM_VERSION"] != nil { distribucion += "+graalvm" }
        } else {
            guard let info = NSDictionary(contentsOf: jdk.appendingPathComponent("Contents/Info.plist")),
                  let vm = info["JavaVM"] as? [String: Any] else { return nil }
            version = vm["JVMVersion"] as? String ?? ""
            proveedor = vm["JVMVendor"] as? String ?? ""
        }
        guard !version.isEmpty, !proveedor.isEmpty, let mayor = versionesIDEsYAgentesMayor(version) else { return nil }
        return VersionesIDEsYAgentesJDK(url: jdk, version: version, proveedor: proveedor,
                                        grupo: [proveedor, distribucion, String(mayor), arquitectura].joined(separator: "|"))
    }

    /// Versión mayor de Java: «17.0.8» → 17; «1.8.0_392» → 8 (Java 8 y anteriores empiezan por «1.»).
    static func versionesIDEsYAgentesMayor(_ version: String) -> Int? {
        let numeros = version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let primero = numeros.first else { return nil }
        return version.hasPrefix("1.") && numeros.count > 1 ? numeros[1] : primero
    }

    /// Versiones de Java: «1.8.0_392» se compara como «1.8.0.392».
    static func versionesIDEsYAgentesCompararJava(_ a: String, _ b: String) -> ComparisonResult {
        a.replacingOccurrences(of: "_", with: ".").compare(b.replacingOccurrences(of: "_", with: "."), options: .numeric)
    }

    /// Todo lo que puede nombrar un JDK de tu carpeta, en minúsculas: ajustes de Gradle, Maven, Flutter, jenv y la
    /// terminal, las listas de JDKs de los IDEs de JetBrains y de Android Studio, los ajustes de Java de cada proyecto
    /// y a dónde apuntan los enlaces de jenv. `nil` si algo de eso existe y no se puede leer.
    static func versionesIDEsYAgentesReferenciasJava(home: URL, repos: Set<String>) -> [String]? {
        let casa = home.standardizedFileURL
        var archivos = ([".gradle/gradle.properties", ".config/flutter/settings", ".mavenrc", ".m2/toolchains.xml",
                         ".jenv/version"] + versionesIDEsYAgentesArchivosDeTerminal).map { casa.appendingPathComponent($0) }
        // options/jdk.table.xml de cada IDE de JetBrains y de cada versión de Android Studio.
        for (fabricante, prefijo) in [("JetBrains", ""), ("Google", "AndroidStudio")] {
            let base = casa.appendingPathComponent("Library/Application Support").appendingPathComponent(fabricante)
            guard Rutas.existe(base) else { continue }
            guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: base.path) else { return nil }
            for n in nombres.sorted() where n.hasPrefix(prefijo) {
                archivos.append(base.appendingPathComponent(n).appendingPathComponent("options/jdk.table.xml"))
            }
        }
        let prefijoCasa = casa.path + "/"
        for repo in repos.sorted() where repo.hasPrefix(prefijoCasa) {
            let raiz = URL(fileURLWithPath: repo)
            for rel in ["gradle.properties", ".idea/gradle.xml", ".idea/misc.xml", ".java-version", ".tool-versions"] {
                archivos.append(raiz.appendingPathComponent(rel))
            }
        }
        guard var textos = versionesIDEsYAgentesTextos(archivos) else { return nil }
        // jenv: cada versión es un enlace al JDK que usa.
        let jenv = casa.appendingPathComponent(".jenv/versions")
        if Rutas.existe(jenv) {
            guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: jenv.path) else { return nil }
            for n in nombres {
                if let destino = try? FileManager.default.destinationOfSymbolicLink(atPath: jenv.appendingPathComponent(n).path) {
                    textos.append(destino.lowercased())
                }
            }
        }
        return textos
    }

    /// El texto de cada archivo que existe, en minúsculas. `nil` si alguno existe y no se puede leer como UTF-8: entonces
    /// no se sabe qué nombra, y quien lo pide no ofrece nada.
    static func versionesIDEsYAgentesTextos(_ archivos: [URL]) -> [String]? {
        var r: [String] = []
        for a in archivos where Rutas.existe(a) {
            guard let texto = try? String(contentsOf: a, encoding: .utf8) else { return nil }
            r.append(texto.lowercased())
        }
        return r
    }

    // MARK: - Copias de Xcode

    /// Copias completas de Xcode (de 10 a 40 GB cada una) en ~/Applications que no son la activa (la de xcode-select) ni
    /// la más nueva. Las de /Applications solo cuentan para saber cuál es la más nueva: borrarlas pediría tocar el sistema.
    static func versionesIDEsYAgentesXcode(_ c: Contexto, home: URL, abierto: (String) -> Bool) -> [Elemento] {
        let casa = home.standardizedFileURL
        let personal = casa.appendingPathComponent("Applications")
        let enCasa = versionesIDEsYAgentesXcodes(en: personal)
        guard !enCasa.isEmpty else { return [] }

        // La activa, según xcode-select. Si no se sabe cuál es, no se ofrece ninguna.
        let seleccion = Shell.ejecutar("/usr/bin/xcode-select", ["-p"], limite: 10)
        let salida = seleccion.salida.trimmingCharacters(in: .whitespacesAndNewlines)
        let sufijo = "/Contents/Developer"
        guard seleccion.estado == 0, salida.hasPrefix("/"), salida.hasSuffix(sufijo), salida.count > sufijo.count else {
            return []
        }
        let activa = URL(fileURLWithPath: String(salida.dropLast(sufijo.count))).resolvingSymlinksInPath()
        // Quien usa otra con DEVELOPER_DIR la fija en los archivos de la terminal: esa tampoco se ofrece.
        let terminal = versionesIDEsYAgentesArchivosDeTerminal.map { casa.appendingPathComponent($0) }
        guard let versionActiva = versionesIDEsYAgentesVersionDeXcode(activa),
              let textos = versionesIDEsYAgentesTextos(terminal) else { return [] }

        let todas = versionesIDEsYAgentesXcodes(en: URL(fileURLWithPath: "/Applications")) + enCasa
        var r: [Elemento] = []
        for x in versionesIDEsYAgentesXcodesSobrantes(todas, activa: activa.path, carpeta: personal,
                                                      procesos: c.procesos.lineas) {
            let nombrada = "applications/" + x.app.lastPathComponent.lowercased()
            guard !textos.contains(where: { $0.contains(nombrada) }),
                  versionesIDEsYAgentesOfrecible(x.app, home: casa, abierto: abierto) else { continue }
            r.append(Elemento(
                nombre: "Xcode \(x.version) (copia adicional)",
                detalle: "Otra instalación completa de Xcode en \(Formato.rutaCorta(x.app)).",
                consecuencia: "Usas Xcode \(versionActiva). Si necesitas esta versión, tendrás que volver a descargarla (de 10 a 40 GB).",
                rutas: [x.app], categoria: .desarrollo, riesgo: .revisar, seleccionado: false,
                motivos: [.info("hammer.fill", "No es la que usas",
                                "xcode-select usa \(Formato.rutaCorta(activa)) (Xcode \(versionActiva)), y esta copia tampoco es la más nueva que tienes.")],
                enUso: .app(nombre: "Xcode", claves: ["com.apple.dt.Xcode"]), dueno: "Xcode"))
        }
        return r
    }

    /// Las copias de Xcode que sobran: solo las que están directamente en `carpeta` (~/Applications), y nunca la activa,
    /// ni la de versión más alta (con empate, ninguna de las más altas: una beta puede tener la misma versión), ni una en
    /// marcha. `real`: la ruta con los enlaces resueltos, como `activa`.
    static func versionesIDEsYAgentesXcodesSobrantes(_ xcodes: [(app: URL, real: String, version: String)], activa: String,
                                                     carpeta: URL, procesos: [String]) -> [(app: URL, version: String)] {
        let masAltas = versionesIDEsYAgentesLasMasAltas(xcodes.map { $0.version })
        let base = carpeta.standardizedFileURL.path
        var r: [(app: URL, version: String)] = []
        for x in xcodes where x.app.deletingLastPathComponent().standardizedFileURL.path == base
            && x.real != activa && !masAltas.contains(x.version) {
            let formas = [x.app.path.lowercased() + "/", x.real.lowercased() + "/"]
            if procesos.contains(where: { l in formas.contains { l.contains($0) } }) { continue }
            r.append((app: x.app, version: x.version))
        }
        return r
    }

    /// Los Xcode que hay directamente en una carpeta, con su ruta real (enlaces resueltos) y su versión.
    static func versionesIDEsYAgentesXcodes(en carpeta: URL) -> [(app: URL, real: String, version: String)] {
        let nombres = (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? []
        var r: [(app: URL, real: String, version: String)] = []
        for n in nombres.sorted() where n.hasSuffix(".app") {
            let app = carpeta.appendingPathComponent(n)
            if let version = versionesIDEsYAgentesVersionDeXcode(app) {
                r.append((app: app, real: app.resolvingSymlinksInPath().path, version: version))
            }
        }
        return r
    }

    /// La versión de un Xcode («16.0»), o `nil` si no es un Xcode o no se puede leer su Info.plist.
    static func versionesIDEsYAgentesVersionDeXcode(_ app: URL) -> String? {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              (info["CFBundleIdentifier"] as? String) == "com.apple.dt.Xcode",
              let version = info["CFBundleShortVersionString"] as? String, !version.isEmpty else { return nil }
        return version
    }

    // MARK: - Comprobaciones comunes

    /// Lo que el grupo puede ofrecer: existe, no es un enlace, está dentro de tu carpeta (también con los enlaces
    /// resueltos), se puede mover a la Papelera y ningún programa lo tiene abierto ahora mismo.
    static func versionesIDEsYAgentesOfrecible(_ u: URL, home: URL, abierto: (String) -> Bool) -> Bool {
        let casa = home.standardizedFileURL.path
        guard Rutas.existeSinSeguir(u.path), !versionesIDEsYAgentesEsEnlace(u.path), u.path.hasPrefix(casa + "/"),
              Seguridad.normalizada(u.path).hasPrefix(Seguridad.normalizada(casa) + "/"),
              Escaner.sePuedeQuitar(u, admin: false) else { return false }
        return !abierto(u.path)
    }

    static func versionesIDEsYAgentesEsEnlace(_ ruta: String) -> Bool {
        var st = stat()
        return lstat(ruta, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
    }

    /// Una carpeta de verdad (no un enlace a una carpeta).
    static func versionesIDEsYAgentesEsCarpetaReal(_ ruta: String) -> Bool {
        var st = stat()
        return lstat(ruta, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// Orden de versiones: «2.0.10» va después de «2.0.9».
    static func versionesIDEsYAgentesOrden(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedAscending
    }

    /// Las versiones más altas de una lista (si dos se escriben distinto pero valen lo mismo, las dos).
    static func versionesIDEsYAgentesLasMasAltas(_ versiones: [String]) -> Set<String> {
        guard let alta = versiones.max(by: { versionesIDEsYAgentesOrden($0, $1) }) else { return [] }
        return Set(versiones.filter { $0.compare(alta, options: .numeric) == .orderedSame })
    }
}
