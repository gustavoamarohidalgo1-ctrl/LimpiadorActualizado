import Foundation

/// Borra lo que el usuario seleccionó. Antes de tocar cada elemento vuelve a comprobar que sea seguro:
/// rutas protegidas, apps abiertas y emuladores encendidos.
enum Limpiador {
    static func limpiar(_ elementos: [Elemento], modo: ModoLimpieza,
                        progreso: @Sendable (Double, String) -> Void) -> ResultadoLimpieza {
        let fm = FileManager.default
        let libreAntes = InfoDisco.actual().libre
        let procesos = Procesos.capturar()
        var errores: [String] = []
        var omitidos: [String] = []
        var movimientos: [Movimiento] = []
        var registro: [String] = []
        var limpiados = 0
        var forzados = 0
        var bytes: Int64 = 0

        for (i, el) in elementos.enumerated() {
            progreso(Double(i) / Double(max(elementos.count, 1)), el.nombre)

            // Comprobación de último momento: puede que la app se haya abierto después del análisis.
            if let uso = el.enUso, procesos.estaEnUso(uso) {
                let quien: String
                if case .app(_, let claves) = uso, let abierta = procesos.appAbierta(claves) { quien = abierta } else { quien = uso.descripcion }
                omitidos.append("\(el.nombre): \(quien) está en uso. Ciérralo y vuelve a limpiar.")
                continue
            }
            // Lo que no es 100 % seguro nunca se elimina sin pasar por la Papelera.
            let modoElemento: ModoLimpieza = (modo == .definitivo && el.riesgo != .seguro) ? .papelera : modo
            if modoElemento != modo { forzados += 1 }

            var ok = true
            switch el.accion {
            case .borrar:
                if let disco = el.imagenMontada {
                    Shell.ejecutar("/usr/bin/hdiutil", ["detach", disco, "-quiet"], limite: 30)
                }
                for (j, url) in el.rutas.enumerated() {
                    guard Rutas.existe(url) else { continue }
                    guard Seguridad.sePuedeBorrar(url) else {
                        errores.append("\(Formato.rutaCorta(url)): ruta protegida, no se tocó.")
                        ok = false
                        continue
                    }
                    if url.path.contains("/Library/LaunchAgents/") {
                        // Se descarga el agente para que deje de intentar arrancar.
                        Shell.ejecutar("/bin/launchctl", ["bootout", "gui/\(getuid())", url.path], limite: 10)
                    }
                    let tamano = j < el.tamanosRutas.count ? el.tamanosRutas[j] : 0
                    do {
                        if modoElemento == .papelera {
                            var enPapelera: NSURL?
                            try fm.trashItem(at: url, resultingItemURL: &enPapelera)
                            if let destino = enPapelera?.path {
                                movimientos.append(Movimiento(original: url.path, enPapelera: destino, nombre: el.nombre, bytes: tamano))
                            }
                        } else {
                            try fm.removeItem(at: url)
                        }
                        registro.append("\(modoElemento == .papelera ? "papelera" : "eliminado")\t\(tamano)\t\(url.path)")
                    } catch {
                        // Algunas carpetas no se pueden mover enteras (permisos): se intenta con su contenido.
                        let parcial = vaciarContenido(de: url, modo: modoElemento)
                        movimientos += parcial.movimientos.map {
                            Movimiento(original: $0.0, enPapelera: $0.1, nombre: el.nombre, bytes: 0)
                        }
                        if !parcial.completo {
                            errores.append("\(Formato.rutaCorta(url)): \(error.localizedDescription)")
                            ok = false
                        }
                    }
                }
            case .eliminarSimulador(let udid):
                ok = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "delete", udid], limite: 120).estado == 0
                if !ok { errores.append("\(el.nombre): no se pudo eliminar el simulador.") }
                registro.append("simulador eliminado\t\(el.tamano)\t\(udid)")
            case .vaciarSimulador(let udid):
                Shell.ejecutar("/usr/bin/xcrun", ["simctl", "shutdown", udid], limite: 60)
                ok = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "erase", udid], limite: 120).estado == 0
                if !ok { errores.append("\(el.nombre): no se pudo borrar (¿está abierto el simulador?).") }
                registro.append("simulador vaciado\t\(el.tamano)\t\(udid)")
            case .eliminarRuntime(let id):
                ok = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "runtime", "delete", id], limite: 300).estado == 0
                if !ok { errores.append("\(el.nombre): Xcode no pudo eliminarlo. Prueba desde Xcode › Ajustes › Componentes.") }
                registro.append("sistema iOS eliminado\t\(el.tamano)\t\(id)")
            case .vaciarPapelera:
                ok = vaciarPapelera()
                if !ok { errores.append("No se pudo vaciar toda la Papelera. Dale Acceso total al disco a LimpiadorMac.") }
                registro.append("papelera vaciada\t\(el.tamano)\t~/.Trash")
            }
            if ok {
                limpiados += 1
                bytes += el.tamano
            }
        }
        progreso(1, "Listo")

        Historial.registrar(registro)
        if !movimientos.isEmpty {
            Historial.guardarUltima(LimpiezaGuardada(fecha: Date(), movimientos: movimientos))
        }
        return ResultadoLimpieza(elementosLimpiados: limpiados, bytesLimpiados: bytes,
                                 libreAntes: libreAntes, libreDespues: InfoDisco.actual().libre,
                                 errores: errores, modo: modo, omitidos: omitidos,
                                 forzadosAPapelera: forzados, restaurables: movimientos.count)
    }

    private static func vaciarContenido(de url: URL, modo: ModoLimpieza) -> (completo: Bool, movimientos: [(String, String)]) {
        guard Rutas.esCarpeta(url) else { return (false, []) }
        var completo = true
        var movimientos: [(String, String)] = []
        for hijo in Rutas.hijos(url) {
            do {
                if modo == .papelera {
                    var destino: NSURL?
                    try FileManager.default.trashItem(at: hijo, resultingItemURL: &destino)
                    if let d = destino?.path { movimientos.append((hijo.path, d)) }
                } else {
                    try FileManager.default.removeItem(at: hijo)
                }
            } catch { completo = false }
        }
        return (completo, movimientos)
    }

    static func vaciarPapelera() -> Bool {
        let trash = Rutas.enHome(".Trash")
        guard let hijos = try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) else {
            return false
        }
        var todo = true
        for h in hijos {
            do { try FileManager.default.removeItem(at: h) } catch { todo = false }
        }
        Historial.olvidarUltima()   // lo que había para deshacer ya no existe
        return todo
    }

    static func tamanoPapelera() -> Int64 {
        Tamanos.de(Rutas.enHome(".Trash"))
    }
}

// MARK: - Deshacer e historial

struct Movimiento: Codable, Hashable {
    let original: String
    let enPapelera: String
    let nombre: String
    let bytes: Int64
}

struct LimpiezaGuardada: Codable {
    let fecha: Date
    var movimientos: [Movimiento]

    var bytes: Int64 { movimientos.reduce(0) { $0 + $1.bytes } }
    var elementos: Int { Set(movimientos.map(\.nombre)).count }
}

/// Guarda la última limpieza (para poder deshacerla) y un registro de todo lo que se borró.
enum Historial {
    private static let carpeta = Rutas.enHome("Library/Application Support/LimpiadorMac")
    private static let ultima = carpeta.appendingPathComponent("ultima-limpieza.json")
    static let registroURL = Rutas.enHome("Library/Logs/LimpiadorMac/historial.log")

    static func guardarUltima(_ l: LimpiezaGuardada) {
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        try? codificador.encode(l).write(to: ultima)
    }

    /// La última limpieza, si todavía queda algo en la Papelera para devolver.
    static func cargarUltima() -> LimpiezaGuardada? {
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        guard let datos = try? Data(contentsOf: ultima),
              var l = try? decodificador.decode(LimpiezaGuardada.self, from: datos) else { return nil }
        l.movimientos = l.movimientos.filter { Rutas.existe($0.enPapelera) }
        return l.movimientos.isEmpty ? nil : l
    }

    static func olvidarUltima() {
        try? FileManager.default.removeItem(at: ultima)
    }

    /// Devuelve cada cosa a su sitio original.
    static func deshacer(_ l: LimpiezaGuardada) -> (restaurados: Int, bytes: Int64, errores: [String]) {
        let fm = FileManager.default
        var restaurados = 0
        var bytes: Int64 = 0
        var errores: [String] = []
        var lineas: [String] = []
        for m in l.movimientos {
            let origen = URL(fileURLWithPath: m.enPapelera)
            let destino = URL(fileURLWithPath: m.original)
            guard fm.fileExists(atPath: origen.path) else {
                errores.append("\(Formato.rutaCorta(destino)): ya no está en la Papelera.")
                continue
            }
            guard !fm.fileExists(atPath: destino.path) else {
                errores.append("\(Formato.rutaCorta(destino)): ya existe algo con ese nombre; está en la Papelera.")
                continue
            }
            do {
                try fm.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: origen, to: destino)
                restaurados += 1
                bytes += m.bytes
                lineas.append("restaurado\t\(m.bytes)\t\(m.original)")
            } catch {
                errores.append("\(Formato.rutaCorta(destino)): \(error.localizedDescription)")
            }
        }
        registrar(lineas)
        olvidarUltima()
        return (restaurados, bytes, errores)
    }

    static func registrar(_ lineas: [String]) {
        guard !lineas.isEmpty else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: registroURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fecha = ISO8601DateFormatter().string(from: Date())
        let texto = lineas.map { "\(fecha)\t\($0)" }.joined(separator: "\n") + "\n"
        if let h = try? FileHandle(forWritingTo: registroURL) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(texto.utf8))
        } else {
            try? Data(texto.utf8).write(to: registroURL)
        }
    }
}
