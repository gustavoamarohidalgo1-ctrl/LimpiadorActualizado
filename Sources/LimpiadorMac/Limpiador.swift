import Foundation

/// Borra lo que el usuario seleccionó. Antes de tocar cada elemento vuelve a comprobar que sea seguro:
/// rutas protegidas, apps abiertas, emuladores encendidos y que quede al menos una copia de cada duplicado.
enum Limpiador {
    static func limpiar(_ seleccion: [Elemento], modo: ModoLimpieza,
                        progreso: @Sendable (Double, String) -> Void) -> ResultadoLimpieza {
        let fm = FileManager.default
        let libreAntes = InfoDisco.actual().libre
        let procesos = Procesos.capturar()
        // Vaciar la Papelera va al final y solo borra lo que ya estaba en ella al empezar:
        // lo que esta misma limpieza mande a la Papelera tiene que poder deshacerse.
        let elementos = seleccion.filter { $0.accion != .vaciarPapelera } + seleccion.filter { $0.accion == .vaciarPapelera }
        let papeleraAntes = seleccion.contains { $0.accion == .vaciarPapelera } ? contenidoPapelera() : []
        // Todo lo que se va a borrar, para no borrar nunca la última copia de un duplicado.
        let aBorrar = Set(seleccion.filter { $0.accion == .borrar }.flatMap { $0.rutas.map(\.path) })

        var errores: [String] = []
        var omitidos: [String] = []
        var movimientos: [Movimiento] = []
        var registro: [String] = []
        var hechos = Set<UUID>()
        var forzados = 0
        var bytes: Int64 = 0
        // Lo del sistema se borra todo junto al final, para pedir la contraseña una sola vez.
        var delSistema: [Elemento] = []

        for (i, el) in elementos.enumerated() {
            progreso(Double(i) / Double(max(elementos.count, 1)), el.nombre)

            // Comprobación de último momento: puede que la app se haya abierto después del análisis.
            if let uso = el.enUso, procesos.estaEnUso(uso) {
                let quien: String
                if case .app(_, let claves) = uso, let abierta = procesos.appAbierta(claves) { quien = abierta } else { quien = uso.descripcion }
                omitidos.append("\(el.nombre): \(quien) está en uso. Ciérralo y vuelve a limpiar.")
                continue
            }
            if let original = el.conservar,
               !Rutas.existe(original) || aBorrar.contains(original) || Rutas.estaDentro(original, de: aBorrar) {
                omitidos.append("\(el.nombre): es la última copia que queda (la de \(Formato.rutaCorta(Rutas.padre(original))) también se iba a borrar o ya no está).")
                continue
            }
            if el.accion == .borrarComoAdmin {
                delSistema.append(el)
                continue
            }
            // Lo que no es 100 % seguro nunca se elimina sin pasar por la Papelera.
            let modoElemento: ModoLimpieza = (modo == .definitivo && el.riesgo != .seguro) ? .papelera : modo
            if el.accion == .borrar && modoElemento != modo { forzados += 1 }

            var ok = true
            switch el.accion {
            case .borrar:
                if let disco = el.imagenMontada {
                    Shell.ejecutar("/usr/bin/hdiutil", ["detach", disco, "-quiet"], limite: 30)
                }
                for (j, url) in el.rutas.enumerated() {
                    guard Rutas.existeSinSeguir(url.path) else { continue }
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
                        for (original, destino) in parcial.hechos {
                            if let destino {
                                movimientos.append(Movimiento(original: original, enPapelera: destino, nombre: el.nombre, bytes: 0))
                            }
                            registro.append("\(modoElemento == .papelera ? "papelera" : "eliminado")\t0\t\(original)")
                        }
                        if !parcial.completo {
                            errores.append("\(Formato.rutaCorta(url)): \(error.localizedDescription)")
                            ok = false
                        }
                    }
                }
            case .eliminarSimulador(let udid):
                ok = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "delete", udid], limite: 120).estado == 0
                if ok { registro.append("simulador eliminado\t\(el.tamano)\t\(udid)") }
                else { errores.append("\(el.nombre): no se pudo eliminar el simulador.") }
            case .vaciarSimulador(let udid):
                Shell.ejecutar("/usr/bin/xcrun", ["simctl", "shutdown", udid], limite: 60)
                ok = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "erase", udid], limite: 120).estado == 0
                if ok { registro.append("simulador vaciado\t\(el.tamano)\t\(udid)") }
                else { errores.append("\(el.nombre): no se pudo borrar (¿está abierto el simulador?).") }
            case .eliminarRuntime(let id):
                ok = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "runtime", "delete", id], limite: 300).estado == 0
                if ok { registro.append("sistema iOS eliminado\t\(el.tamano)\t\(id)") }
                else { errores.append("\(el.nombre): Xcode no pudo eliminarlo. Prueba desde Xcode › Ajustes › Componentes.") }
            case .vaciarPapelera:
                ok = vaciar(papeleraAntes)
                if ok { registro.append("papelera vaciada\t\(el.tamano)\t~/.Trash") }
                else { errores.append("No se pudo vaciar toda la Papelera. Dale Acceso total al disco a LimpiadorMac.") }
            case .borrarComoAdmin:
                break   // se hace abajo, todo junto
            }
            if ok {
                hechos.insert(el.id)
                bytes += el.tamano
            }
        }

        if !delSistema.isEmpty {
            progreso(0.99, "Basura del sistema: macOS te pedirá la contraseña de administrador…")
            // Se vuelve a comprobar cada ruta justo antes: solo lo que el catálogo permite y que no sea un enlace.
            let rutas = delSistema.flatMap(\.rutas).filter { u in
                Rutas.existeSinSeguir(u.path) && Seguridad.sePuedeBorrarComoAdmin(u) && !esEnlace(u.path)
            }
            let rechazadas = delSistema.flatMap(\.rutas).filter { Rutas.existeSinSeguir($0.path) && !rutas.contains($0) }
            for u in rechazadas { errores.append("\(u.path): ruta del sistema no permitida, no se tocó.") }
            if !rutas.isEmpty { Administrador.borrar(rutas.map(\.path)) }
            var quedaron = 0
            for el in delSistema {
                let quedan = el.rutas.filter { Rutas.existeSinSeguir($0.path) }
                for u in el.rutas where !quedan.contains(u) { registro.append("eliminado (administrador)\t0\t\(u.path)") }
                if quedan.isEmpty {
                    hechos.insert(el.id)
                    bytes += el.tamano
                } else {
                    quedaron += 1
                }
            }
            if quedaron > 0 {
                errores.append("\(quedaron) \(quedaron == 1 ? "elemento del sistema no se borró" : "elementos del sistema no se borraron") del todo: cancelaste la contraseña o macOS los protege.")
            }
        }
        progreso(1, "Listo")

        Historial.registrar(registro)
        if !movimientos.isEmpty {
            Historial.guardar(LimpiezaGuardada(fecha: Date(), movimientos: movimientos))
        }
        return ResultadoLimpieza(elementosLimpiados: hechos.count, bytesLimpiados: bytes,
                                 libreAntes: libreAntes, libreDespues: InfoDisco.actual().libre,
                                 errores: errores, modo: modo, omitidos: omitidos,
                                 forzadosAPapelera: forzados,
                                 restaurables: movimientos.filter { Rutas.existeSinSeguir($0.enPapelera) }.count,
                                 hechos: hechos)
    }

    private static func vaciarContenido(de url: URL, modo: ModoLimpieza) -> (completo: Bool, hechos: [(String, String?)]) {
        guard Rutas.esCarpeta(url) else { return (false, []) }
        var completo = true
        var hechos: [(String, String?)] = []
        for hijo in Rutas.hijos(url) {
            // Las mismas reglas que para la carpeta entera: ni llaves de firma ni rutas protegidas.
            guard Seguridad.sePuedeBorrar(hijo) else { completo = false; continue }
            do {
                if modo == .papelera {
                    var destino: NSURL?
                    try FileManager.default.trashItem(at: hijo, resultingItemURL: &destino)
                    hechos.append((hijo.path, destino?.path))
                } else {
                    try FileManager.default.removeItem(at: hijo)
                    hechos.append((hijo.path, nil))
                }
            } catch { completo = false }
        }
        return (completo, hechos)
    }

    static func contenidoPapelera() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: Rutas.enHome(".Trash"), includingPropertiesForKeys: nil)) ?? []
    }

    /// Vacía toda la Papelera (el botón «Vaciar Papelera»).
    static func vaciarPapelera() -> Bool {
        guard let hijos = try? FileManager.default.contentsOfDirectory(at: Rutas.enHome(".Trash"),
                                                                        includingPropertiesForKeys: nil) else {
            return false
        }
        return vaciar(hijos)
    }

    private static func vaciar(_ items: [URL]) -> Bool {
        var todo = true
        for h in items {
            do { try FileManager.default.removeItem(at: h) } catch {
                if Rutas.existeSinSeguir(h.path) { todo = false }
            }
        }
        Historial.depurar()   // lo que había para deshacer de esas cosas ya no existe
        return todo
    }

    static func tamanoPapelera() -> Int64 {
        Tamanos.de(Rutas.enHome(".Trash"))
    }

    private static func esEnlace(_ ruta: String) -> Bool {
        var st = stat()
        return lstat(ruta, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
    }
}

/// Borra rutas del sistema con permisos de administrador: macOS muestra su propia ventana para pedir la contraseña.
/// Las rutas van escritas dentro de la orden (nunca en un archivo que otro programa pudiera cambiar).
enum Administrador {
    @discardableResult
    static func borrar(_ rutas: [String]) -> Bool {
        guard !rutas.isEmpty else { return true }
        let orden = "/bin/rm -rf -- " + rutas.map(comillasShell).joined(separator: " ")
        let script = "do shell script " + textoAppleScript(orden) + " with administrator privileges"
        return Shell.ejecutar("/usr/bin/osascript", ["-e", script], limite: 900).estado == 0
    }

    /// Entre comillas simples para la terminal: «it's» → «'it'\''s'».
    static func comillasShell(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Como texto de AppleScript, con barras y comillas escapadas.
    static func textoAppleScript(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

// MARK: - Deshacer e historial

struct Movimiento: Codable, Hashable {
    let original: String
    let enPapelera: String
    let nombre: String
    let bytes: Int64
}

struct LimpiezaGuardada: Codable, Identifiable {
    var id: UUID
    let fecha: Date
    var movimientos: [Movimiento]

    init(fecha: Date, movimientos: [Movimiento]) {
        id = UUID()
        self.fecha = fecha
        self.movimientos = movimientos
    }

    private enum CodingKeys: String, CodingKey { case id, fecha, movimientos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Las limpiezas guardadas por la versión anterior no tenían identificador.
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fecha = try c.decode(Date.self, forKey: .fecha)
        movimientos = try c.decode([Movimiento].self, forKey: .movimientos)
    }

    var bytes: Int64 { movimientos.reduce(0) { $0 + $1.bytes } }
    var elementos: Int { Set(movimientos.map(\.nombre)).count }
}

/// Guarda las últimas limpiezas (para poder deshacerlas, de la más reciente a la más antigua)
/// y un registro de todo lo que se borró.
enum Historial {
    private static let carpeta = Rutas.enHome("Library/Application Support/LimpiadorMac")
    private static let archivo = carpeta.appendingPathComponent("limpiezas.json")
    /// Formato de la versión anterior: solo la última limpieza.
    private static let anterior = carpeta.appendingPathComponent("ultima-limpieza.json")
    static let registroURL = Rutas.enHome("Library/Logs/LimpiadorMac/historial.log")
    private static let maximo = 30
    private static let candado = NSLock()

    /// Las limpiezas que todavía tienen algo en la Papelera, de la más antigua a la más reciente.
    static func todas() -> [LimpiezaGuardada] {
        candado.lock(); defer { candado.unlock() }
        return leer().compactMap(vigente)
    }

    /// La limpieza más reciente que todavía se puede deshacer.
    static func cargarUltima() -> LimpiezaGuardada? { todas().last }

    /// Agrega una limpieza sin tocar las anteriores (borrar algo desde el Explorador no impide deshacer una limpieza grande).
    static func guardar(_ l: LimpiezaGuardada) {
        guard !l.movimientos.isEmpty else { return }
        candado.lock(); defer { candado.unlock() }
        var lista = leer().compactMap(vigente)
        lista.append(l)
        escribir(Array(lista.suffix(maximo)))
    }

    /// Olvida lo que ya no está en la Papelera (por ejemplo, después de vaciarla).
    static func depurar() {
        candado.lock(); defer { candado.unlock() }
        escribir(leer().compactMap(vigente))
    }

    /// Devuelve cada cosa a su sitio original. Lo que no se pudo devolver queda guardado para intentarlo otra vez.
    static func deshacer(_ l: LimpiezaGuardada) -> (restaurados: Int, bytes: Int64, errores: [String]) {
        let fm = FileManager.default
        var restaurados = 0
        var bytes: Int64 = 0
        var errores: [String] = []
        var lineas: [String] = []
        var pendientes: [Movimiento] = []
        // Primero las carpetas de arriba, para que lo que iba dentro encuentre su sitio.
        let orden = l.movimientos.sorted {
            $0.original.split(separator: "/").count < $1.original.split(separator: "/").count
        }
        for m in orden {
            let origen = URL(fileURLWithPath: m.enPapelera)
            let destino = URL(fileURLWithPath: m.original)
            guard Rutas.existeSinSeguir(origen.path) else {
                errores.append("\(Formato.rutaCorta(destino)): ya no está en la Papelera.")
                continue
            }
            guard !Rutas.existeSinSeguir(destino.path) else {
                errores.append("\(Formato.rutaCorta(destino)): ya existe algo con ese nombre; sigue en la Papelera.")
                pendientes.append(m)
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
                pendientes.append(m)
            }
        }
        registrar(lineas)

        candado.lock()
        var lista = leer()
        if let i = lista.firstIndex(where: { $0.id == l.id }) {
            if pendientes.isEmpty { lista.remove(at: i) } else { lista[i].movimientos = pendientes }
        }
        escribir(lista.compactMap(vigente))
        candado.unlock()
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

    private static func vigente(_ l: LimpiezaGuardada) -> LimpiezaGuardada? {
        var l = l
        l.movimientos = l.movimientos.filter { Rutas.existeSinSeguir($0.enPapelera) }
        return l.movimientos.isEmpty ? nil : l
    }

    private static func leer() -> [LimpiezaGuardada] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        if let datos = try? Data(contentsOf: archivo), let lista = try? d.decode([LimpiezaGuardada].self, from: datos) {
            return lista
        }
        // Lo que guardó la versión anterior (una sola limpieza).
        if let datos = try? Data(contentsOf: anterior), let l = try? d.decode(LimpiezaGuardada.self, from: datos) {
            return [l]
        }
        return []
    }

    private static func escribir(_ lista: [LimpiezaGuardada]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        if let datos = try? e.encode(lista) { try? datos.write(to: archivo, options: .atomic) }
        try? fm.removeItem(at: anterior)
    }
}
