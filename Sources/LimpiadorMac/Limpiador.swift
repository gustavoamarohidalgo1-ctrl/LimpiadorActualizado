import Foundation

/// Borra lo que el usuario seleccionó, respetando siempre las reglas de `Seguridad`.
enum Limpiador {
    static func limpiar(_ elementos: [Elemento], modo: ModoLimpieza,
                        progreso: @Sendable (Double, String) -> Void) -> ResultadoLimpieza {
        let fm = FileManager.default
        let libreAntes = InfoDisco.actual().libre
        var errores: [String] = []
        var limpiados = 0
        var bytes: Int64 = 0

        for (i, el) in elementos.enumerated() {
            progreso(Double(i) / Double(max(elementos.count, 1)), el.nombre)
            var ok = true
            switch el.accion {
            case .borrar:
                for url in el.rutas {
                    guard Rutas.existe(url) else { continue }
                    guard Seguridad.sePuedeBorrar(url) else {
                        errores.append("\(Formato.rutaCorta(url)): ruta protegida, no se tocó.")
                        ok = false
                        continue
                    }
                    do {
                        if modo == .papelera {
                            try fm.trashItem(at: url, resultingItemURL: nil)
                        } else {
                            try fm.removeItem(at: url)
                        }
                    } catch {
                        // Algunas carpetas no se pueden mover enteras (permisos): se intenta vaciar su contenido.
                        if !vaciarContenido(de: url, modo: modo) {
                            errores.append("\(Formato.rutaCorta(url)): \(error.localizedDescription)")
                            ok = false
                        }
                    }
                }
            case .eliminarSimulador(let udid):
                ok = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "delete", udid]).estado == 0
                if !ok { errores.append("\(el.nombre): no se pudo eliminar el simulador.") }
            case .vaciarSimulador(let udid):
                Shell.ejecutar("/usr/bin/xcrun", ["simctl", "shutdown", udid])
                ok = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "erase", udid]).estado == 0
                if !ok { errores.append("\(el.nombre): no se pudo borrar (¿está abierto el simulador?).") }
            case .vaciarPapelera:
                ok = vaciarPapelera()
                if !ok { errores.append("No se pudo vaciar toda la Papelera. Dale Acceso total al disco a LimpiadorMac.") }
            }
            if ok {
                limpiados += 1
                bytes += el.tamano
            }
        }
        progreso(1, "Listo")
        return ResultadoLimpieza(elementosLimpiados: limpiados, bytesLimpiados: bytes,
                                 libreAntes: libreAntes, libreDespues: InfoDisco.actual().libre,
                                 errores: errores, modo: modo)
    }

    private static func vaciarContenido(de url: URL, modo: ModoLimpieza) -> Bool {
        guard Rutas.esCarpeta(url) else { return false }
        var todo = true
        for hijo in Rutas.hijos(url) {
            do {
                if modo == .papelera { try FileManager.default.trashItem(at: hijo, resultingItemURL: nil) }
                else { try FileManager.default.removeItem(at: hijo) }
            } catch { todo = false }
        }
        return todo
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
        return todo
    }

    static func tamanoPapelera() -> Int64 {
        Tamanos.de(Rutas.enHome(".Trash"))
    }
}
