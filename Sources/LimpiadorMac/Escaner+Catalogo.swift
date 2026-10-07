import Foundation

/// Aplica las reglas del catálogo (`Catalogo.reglas`) a cada categoría.
extension Escaner {
    /// Elementos que salen de las reglas del catálogo para una categoría.
    /// `excluir`: rutas que ya ofreció otra parte del análisis (no se ofrecen dos veces).
    func catalogo(_ categoria: Categoria, _ c: Contexto, excluir: Set<String>) -> [Elemento] {
        var r: [Elemento] = []
        var vistas = excluir
        for regla in Catalogo.reglas where regla.categoria == categoria {
            if regla.requiereAccesoTotal && !c.accesoTotal { continue }
            if regla.soloSiInstalada && !Self.instalada(regla, c) { continue }
            // Lo de una app que ya no está, en las carpetas donde se buscan restos, sale allí entero (con el resto de la app).
            if regla.app != nil && Self.enCarpetaDeRestos(regla.patron) && !Self.instalada(regla, c) { continue }
            // Ni lo que ya se ofreció, ni lo que está dentro, ni lo que lo contiene (se contaría dos veces);
            // tampoco lo que macOS no deja borrar.
            var rutas = Self.aplicar(regla, c).filter { u in
                let prefijo = u.path + "/"
                return !vistas.contains(u.path) && !Rutas.estaDentro(u.path, de: vistas)
                    && !vistas.contains { $0.hasPrefix(prefijo) } && Self.sePuedeQuitar(u, admin: regla.requiereAdmin)
            }
            if regla.id == "sistema-aerial" || regla.id == "aerial-usuario-videos" {
                // El vídeo que tienes de fondo o de salvapantallas no se ofrece; si no se sabe cuál es, ninguno.
                guard let enUso = FondosEnUso.identificadores() else { continue }
                rutas = rutas.filter { !enUso.contains($0.deletingPathExtension().lastPathComponent.uppercased()) }
            }
            if regla.siNadaLoTieneAbierto && !rutas.isEmpty {
                let abiertos = c.memoria.archivosAbiertos()
                guard abiertos.disponible else { continue }   // si no se sabe, no se ofrece
                rutas = rutas.filter { !abiertos.tieneAbierto($0.path) }
            }
            guard !rutas.isEmpty else { continue }
            for u in rutas { vistas.insert(u.path) }
            r.append(Self.elemento(regla, rutas))
        }
        return r
    }

    static func elemento(_ regla: Regla, _ rutas: [URL]) -> Elemento {
        var uso: EnUso?
        if let app = regla.app {
            uso = .app(nombre: app, claves: regla.bundleIDs + [app])
        } else if let p = regla.proceso {
            uso = .proceso(nombre: p.nombre, patron: p.patron.lowercased())
        }
        var motivos: [Motivo] = []
        switch regla.riesgo {
        case .seguro:
            motivos.append(.bien("arrow.triangle.2.circlepath", "Se regenera o sobra", regla.consecuencia))
        case .revisar:
            motivos.append(.info("questionmark.circle", "Revísalo antes", regla.consecuencia))
        case .cuidado:
            motivos.append(.aviso("exclamationmark.triangle.fill", "Puede ser importante", regla.consecuencia))
        }
        if regla.requiereAdmin {
            motivos.append(.info("lock.fill", "Pide contraseña",
                                 "Está fuera de tu carpeta y es del sistema: para borrarlo te pediré la contraseña de administrador. No pasa por la Papelera."))
        }
        let detalle = rutas.count > 1 && regla.modo != .carpeta
            ? "\(regla.detalle) (\(Formato.numero(rutas.count)) elementos)"
            : regla.detalle
        return Elemento(
            nombre: regla.nombre, detalle: detalle, consecuencia: regla.consecuencia, rutas: rutas,
            categoria: regla.categoria, riesgo: regla.riesgo, seleccionado: regla.preseleccionar,
            accion: regla.requiereAdmin ? .borrarComoAdmin : .borrar, motivos: motivos, enUso: uso, dueno: regla.app)
    }

    /// Carpetas donde «Restos de apps borradas» busca lo que dejan las apps desinstaladas.
    static func enCarpetaDeRestos(_ patron: String) -> Bool {
        ["~/Library/Application Support/", "~/Library/Caches/", "~/Library/Logs/", "~/Library/Containers/",
         "~/Library/Group Containers/", "~/Library/HTTPStorages/", "~/Library/WebKit/", "~/Library/Saved Application State/"]
            .contains { patron.hasPrefix($0) }
    }

    /// Banderas con las que macOS impide borrar, incluso a root: SIP (restricted, sunlnk), inmutable, solo añadir
    /// y UF_DATAVAULT (carpetas que solo tocan los servicios de Apple).
    private static let banderasQueImpidenBorrar: UInt32 = 0x0008_0000 | 0x0010_0000 | 0x0002_0000 | 0x0000_0002
        | 0x0004_0000 | 0x0000_0004 | 0x0000_0080

    /// ¿Se puede quitar de verdad? Si no, al limpiar solo daría errores (o borraría solo una parte).
    static func sePuedeQuitar(_ u: URL, admin: Bool) -> Bool {
        var st = stat()
        let padre = u.deletingLastPathComponent().path
        guard lstat(u.path, &st) == 0, st.st_flags & banderasQueImpidenBorrar == 0 else { return false }
        var sp = stat()
        guard lstat(padre, &sp) == 0, sp.st_flags & banderasQueImpidenBorrar == 0 else { return false }
        // Sin contraseña, hace falta poder escribir en la carpeta que lo contiene (para moverlo a la Papelera).
        return admin || access(padre, W_OK) == 0
    }

    /// ¿Sigue instalada la app de la regla?
    static func instalada(_ regla: Regla, _ c: Contexto) -> Bool {
        if regla.bundleIDs.contains(where: { c.apps.bundleIDs.contains($0.lowercased()) }) { return true }
        if let app = regla.app { return c.apps.estaInstalado(carpeta: app) }
        if let p = regla.proceso { return c.apps.comandoPara(carpetaOculta: "." + p.nombre) != nil }
        return true
    }

    /// Las rutas que cubre una regla, según su modo.
    static func aplicar(_ regla: Regla, _ c: Contexto) -> [URL] {
        func excluida(_ u: URL) -> Bool {
            regla.exclusiones.contains { patron in u.pathComponents.contains { fnmatch(patron, $0, 0) == 0 } }
        }
        let base = expandir(regla.patron).filter { !esEnlace($0.path) && !excluida($0) }
        var rutas: [URL] = []
        switch regla.modo {
        case .carpeta:
            rutas = conservar(regla.conservar, de: base, c)
        case .hijos:
            for b in base where Rutas.esCarpeta(b) {
                let hijos = Rutas.hijos(b).filter {
                    let n = $0.lastPathComponent
                    return n != ".DS_Store" && n != ".localized" && !esEnlace($0.path)
                }
                rutas += conservar(regla.conservar, de: hijos.filter { !excluida($0) }, c)
            }
        case .archivos(let extensiones):
            for b in base { rutas += archivos(en: b, extensiones: extensiones).filter { !excluida($0) } }
        }
        if regla.edadMinimaDias > 0 {
            let limite = Date().addingTimeInterval(-Double(regla.edadMinimaDias) * 86400)
            rutas = rutas.filter { fecha($0, c) < limite }
        }
        return rutas
    }

    /// Quita de la lista la que se conserva (la más reciente o la de versión más alta).
    private static func conservar(_ modo: Regla.Conservar, de lista: [URL], _ c: Contexto) -> [URL] {
        var r = lista
        switch modo {
        case .nada:
            break
        case .masReciente:
            if let mas = r.max(by: { fecha($0, c) < fecha($1, c) }) { r.removeAll { $0 == mas } }
        case .versionMasAlta:
            if let mas = r.max(by: {
                $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending
            }) { r.removeAll { $0 == mas } }
        }
        return r
    }

    /// La ruta absoluta de un patrón: «~/…», «$TEMPORAL/…», «$CACHES/…» o «/…».
    static func absoluto(_ patron: String) -> String? {
        if patron.hasPrefix("~/") { return Rutas.home.path + String(patron.dropFirst(1)) }
        if patron.hasPrefix("$TEMPORAL/") { return Sistema.temporal.map { $0 + String(patron.dropFirst("$TEMPORAL".count)) } }
        if patron.hasPrefix("$CACHES/") { return Sistema.caches.map { $0 + String(patron.dropFirst("$CACHES".count)) } }
        return patron.hasPrefix("/") ? patron : nil
    }

    /// «~/Library/Application Support/Steam/steamapps/shadercache/*» → cada carpeta que existe.
    static func expandir(_ patron: String) -> [URL] {
        guard let absoluto = absoluto(patron) else { return [] }
        var actuales = [""]
        for parte in absoluto.split(separator: "/").map(String.init) {
            var siguientes: [String] = []
            let comodin = parte.contains("*") || parte.contains("?") || parte.contains("[")
            for base in actuales {
                if comodin {
                    let nombres = (try? FileManager.default.contentsOfDirectory(atPath: base.isEmpty ? "/" : base)) ?? []
                    for n in nombres.sorted() where fnmatch(parte, n, 0) == 0 { siguientes.append(base + "/" + n) }
                } else {
                    let p = base + "/" + parte
                    if Rutas.existeSinSeguir(p) { siguientes.append(p) }
                }
            }
            actuales = siguientes
            if actuales.isEmpty { return [] }
        }
        return actuales.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
    }

    /// Archivos con esas extensiones dentro de una carpeta (hasta 4 niveles, sin entrar en paquetes).
    static func archivos(en carpeta: URL, extensiones: [String]) -> [URL] {
        guard let e = FileManager.default.enumerator(at: carpeta, includingPropertiesForKeys: [.isRegularFileKey],
                                                     options: [.skipsPackageDescendants]) else { return [] }
        var r: [URL] = []
        var vistos = 0
        for case let u as URL in e {
            vistos += 1
            if vistos > 50_000 { break }
            if e.level > 4 { e.skipDescendants(); continue }
            let n = u.lastPathComponent.lowercased()
            guard extensiones.contains(where: { n.hasSuffix("." + $0) }), !esEnlace(u.path) else { continue }
            // También carpetas con esa extensión (las descargas a medias de Safari son paquetes «.download»).
            if Rutas.esCarpeta(u) { e.skipDescendants() }
            r.append(u)
        }
        return r
    }

    private static func esEnlace(_ ruta: String) -> Bool {
        var st = stat()
        return lstat(ruta, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
    }

    private static func fecha(_ u: URL, _ c: Contexto) -> Date {
        c.indice.masReciente(de: [u]) ?? Fechas.modificacion(u) ?? .distantPast
    }
}

extension Catalogo {
    /// Carpetas de ~/Library/Caches para las que hay reglas que ofrecen solo una parte («~/Library/Caches/Coursier/v1»):
    /// la caché general de apps no las ofrece enteras.
    static let carpetasDeCachesConReglas: Set<String> = {
        var r = Set<String>()
        for regla in reglas where regla.patron.hasPrefix("~/Library/Caches/") {
            let partes = regla.patron.dropFirst("~/Library/Caches/".count).split(separator: "/")
            guard partes.count > 1 || regla.modo != .carpeta, let primera = partes.first, !primera.contains("*") else { continue }
            r.insert(String(primera))
        }
        return r
    }()

    /// Carpetas ocultas de tu carpeta personal («.sbt», «.lmstudio»…) para las que hay reglas.
    static let carpetasOcultasConReglas: Set<String> = {
        var r = Set<String>()
        for regla in reglas where regla.patron.hasPrefix("~/.") {
            guard let primera = regla.patron.dropFirst(2).split(separator: "/").first, !primera.contains("*") else { continue }
            r.insert(String(primera))
        }
        return r
    }()

    /// ¿Esta ruta sale de alguna regla del catálogo? Se usa para permitir borrar fuera de la carpeta personal
    /// solo lo que el catálogo conoce. `admin`: reglas que piden contraseña.
    static func cubre(_ ruta: String, admin: Bool, lista: [Regla] = Catalogo.reglas) -> Bool {
        let partes = ruta.split(separator: "/").map(String.init)
        for regla in lista where regla.requiereAdmin == admin && regla.patron.hasPrefix("/") {
            // Igual que las rutas que se comprueban: sin «/private» delante de /var y /tmp.
            var texto = regla.patron
            for prefijo in ["/private/var/", "/private/tmp/", "/private/etc/"] where texto.hasPrefix(prefijo) {
                texto = String(texto.dropFirst("/private".count))
            }
            let patron = texto.split(separator: "/").map(String.init)
            switch regla.modo {
            case .carpeta:
                if partes.count == patron.count && coincide(patron, partes) { return true }
            case .hijos:
                if partes.count == patron.count + 1 && coincide(patron, Array(partes.prefix(patron.count))) { return true }
            case .archivos(let extensiones):
                let nombre = partes.last?.lowercased() ?? ""
                if partes.count > patron.count && partes.count <= patron.count + 4
                    && extensiones.contains(where: { nombre.hasSuffix("." + $0) })
                    && coincide(patron, Array(partes.prefix(patron.count))) { return true }
            }
        }
        return false
    }

    private static func coincide(_ patron: [String], _ partes: [String]) -> Bool {
        guard patron.count == partes.count else { return false }
        for (p, n) in zip(patron, partes) where fnmatch(p, n, 0) != 0 { return false }
        return true
    }

    // MARK: Artefactos de proyecto

    private static let artefactosPorNombre: [String: [Int]] = {
        var d: [String: [Int]] = [:]
        for (i, a) in artefactos.enumerated() where !a.carpeta.contains("*") { d[a.carpeta, default: []].append(i) }
        return d
    }()
    private static let artefactosConComodin: [Int] = artefactos.indices.filter { artefactos[$0].carpeta.contains("*") }

    /// La regla de artefacto que corresponde a una carpeta de un proyecto, si alguna.
    static func artefacto(nombre: String, padre: String) -> Int? {
        let candidatos = (artefactosPorNombre[nombre] ?? [])
            + artefactosConComodin.filter { fnmatch(artefactos[$0].carpeta, nombre, 0) == 0 }
        guard !candidatos.isEmpty else { return nil }
        var listado: [String]?
        for i in candidatos {
            for m in artefactos[i].marcadores {
                if m.contains("*") {
                    if listado == nil { listado = (try? FileManager.default.contentsOfDirectory(atPath: padre)) ?? [] }
                    if listado!.contains(where: { fnmatch(m, $0, 0) == 0 }) { return i }
                } else if access(padre + "/" + m, F_OK) == 0 {
                    return i
                }
            }
        }
        return nil
    }
}
