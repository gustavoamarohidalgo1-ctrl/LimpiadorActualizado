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
            let rutas = Self.aplicar(regla, c).filter { u in
                !vistas.contains(u.path) && !Rutas.estaDentro(u.path, de: vistas)
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

    /// ¿Sigue instalada la app de la regla?
    static func instalada(_ regla: Regla, _ c: Contexto) -> Bool {
        if regla.bundleIDs.contains(where: { c.apps.bundleIDs.contains($0.lowercased()) }) { return true }
        if let app = regla.app { return c.apps.estaInstalado(carpeta: app) }
        if let p = regla.proceso { return c.apps.comandoPara(carpetaOculta: "." + p.nombre) != nil }
        return true
    }

    /// Las rutas que cubre una regla, según su modo.
    static func aplicar(_ regla: Regla, _ c: Contexto) -> [URL] {
        let base = expandir(regla.patron).filter { !esEnlace($0.path) }
        var rutas: [URL] = []
        switch regla.modo {
        case .carpeta:
            rutas = base
        case .hijos:
            for b in base where Rutas.esCarpeta(b) {
                var hijos = Rutas.hijos(b).filter {
                    let n = $0.lastPathComponent
                    return n != ".DS_Store" && n != ".localized" && !esEnlace($0.path)
                }
                switch regla.conservar {
                case .nada:
                    break
                case .masReciente:
                    if let mas = hijos.max(by: { fecha($0, c) < fecha($1, c) }) { hijos.removeAll { $0 == mas } }
                case .versionMasAlta:
                    if let mas = hijos.max(by: {
                        $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending
                    }) { hijos.removeAll { $0 == mas } }
                }
                rutas += hijos
            }
        case .archivos(let extensiones):
            for b in base { rutas += archivos(en: b, extensiones: extensiones) }
        }
        if regla.edadMinimaDias > 0 {
            let limite = Date().addingTimeInterval(-Double(regla.edadMinimaDias) * 86400)
            rutas = rutas.filter { fecha($0, c) < limite }
        }
        return rutas
    }

    /// «~/Library/Application Support/Steam/steamapps/shadercache/*» → cada carpeta que existe.
    static func expandir(_ patron: String) -> [URL] {
        let absoluto = patron.hasPrefix("~/") ? Rutas.home.path + String(patron.dropFirst(1)) : patron
        guard absoluto.hasPrefix("/") else { return [] }
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
            guard extensiones.contains(where: { n.hasSuffix("." + $0) }),
                  (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
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
    /// ¿Esta ruta sale de alguna regla del catálogo? Se usa para permitir borrar fuera de la carpeta personal
    /// solo lo que el catálogo conoce. `admin`: reglas que piden contraseña.
    static func cubre(_ ruta: String, admin: Bool, lista: [Regla] = Catalogo.reglas) -> Bool {
        let partes = ruta.split(separator: "/").map(String.init)
        for regla in lista where regla.requiereAdmin == admin && !regla.patron.hasPrefix("~/") {
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
            case .archivos:
                if partes.count > patron.count && coincide(patron, Array(partes.prefix(patron.count))) { return true }
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
