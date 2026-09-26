import AppKit
import Foundation
import SwiftUI

enum Seccion: Hashable {
    case resumen
    case explorador
    case categoria(Categoria)
}

@MainActor
final class Almacen: ObservableObject {
    @Published var elementos: [Elemento] = []
    @Published var analizando = false
    @Published var progreso: Double = 0
    @Published var mensaje = ""
    @Published var analizado = false
    @Published var disco = InfoDisco.actual()
    @Published var limpiando = false
    @Published var progresoLimpieza: Double = 0
    @Published var mensajeLimpieza = ""
    @Published var resultado: ResultadoLimpieza?
    @Published var tamanoPapelera: Int64 = 0
    @Published var accesoTotal = Seguridad.tieneAccesoTotal()
    @Published var seccion: Seccion? = .resumen

    // MARK: Análisis

    func analizar() {
        guard !analizando else { return }
        analizando = true
        analizado = false
        elementos = []
        progreso = 0
        resultado = nil
        accesoTotal = Seguridad.tieneAccesoTotal()
        Task.detached(priority: .userInitiated) {
            Escaner().ejecutar(
                progreso: { f, m in
                    Task { @MainActor in self.progreso = f; self.mensaje = m }
                },
                entrega: { nuevos in
                    Task { @MainActor in self.elementos.append(contentsOf: nuevos) }
                })
            let papelera = Limpiador.tamanoPapelera()
            await MainActor.run {
                self.analizando = false
                self.analizado = true
                self.disco = InfoDisco.actual()
                self.tamanoPapelera = papelera
            }
        }
    }

    // MARK: Consultas

    func elementos(de c: Categoria) -> [Elemento] {
        elementos.filter { $0.categoria == c }
    }

    func total(de c: Categoria) -> Int64 {
        elementos.lazy.filter { $0.categoria == c }.reduce(0) { $0 + $1.tamano }
    }

    func totalSeleccionado(de c: Categoria) -> Int64 {
        efectivos.lazy.filter { $0.categoria == c }.reduce(0) { $0 + $1.tamano }
    }

    /// Lo seleccionado, sin contar dos veces una carpeta que está dentro de otra también seleccionada.
    var efectivos: [Elemento] {
        let sel = elementos.filter(\.seleccionado).sorted { $0.rutaPrincipal.path.count < $1.rutaPrincipal.path.count }
        var carpetas: [String] = []
        var r: [Elemento] = []
        for el in sel {
            let p = el.rutaPrincipal.path
            if carpetas.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { continue }
            if case .borrar = el.accion { carpetas.append(contentsOf: el.rutas.map(\.path)) }
            r.append(el)
        }
        return r
    }

    var bytesSeleccionados: Int64 { efectivos.reduce(0) { $0 + $1.tamano } }
    var totalEncontrado: Int64 { Categoria.allCases.reduce(0) { $0 + total(de: $1) } }

    // MARK: Selección

    func alternar(_ id: Elemento.ID) {
        if let i = elementos.firstIndex(where: { $0.id == id }) { elementos[i].seleccionado.toggle() }
    }

    func seleccionado(_ id: Elemento.ID) -> Binding<Bool> {
        Binding(
            get: { self.elementos.first(where: { $0.id == id })?.seleccionado ?? false },
            set: { v in
                if let i = self.elementos.firstIndex(where: { $0.id == id }) { self.elementos[i].seleccionado = v }
            })
    }

    func seleccionar(_ c: Categoria, _ criterio: (Elemento) -> Bool) {
        for i in elementos.indices where elementos[i].categoria == c {
            elementos[i].seleccionado = criterio(elementos[i])
        }
    }

    func seleccionarRecomendados() {
        for i in elementos.indices { elementos[i].seleccionado = elementos[i].riesgo == .seguro }
    }

    // MARK: Limpieza

    func limpiar(modo: ModoLimpieza) {
        let aLimpiar = efectivos
        guard !aLimpiar.isEmpty, !limpiando else { return }
        limpiando = true
        progresoLimpieza = 0
        Task.detached(priority: .userInitiated) {
            let r = Limpiador.limpiar(aLimpiar, modo: modo) { f, m in
                Task { @MainActor in self.progresoLimpieza = f; self.mensajeLimpieza = m }
            }
            let papelera = Limpiador.tamanoPapelera()
            await MainActor.run {
                let limpiados = Set(aLimpiar.map(\.id))
                // Quita de la lista lo que se limpió (lo que falló sigue apareciendo).
                self.elementos.removeAll { el in
                    el.accion == .borrar
                        ? !el.rutas.contains(where: Rutas.existe)
                        : limpiados.contains(el.id)
                }
                self.resultado = r
                self.limpiando = false
                self.disco = InfoDisco.actual()
                self.tamanoPapelera = papelera
            }
        }
    }

    func vaciarPapelera() {
        limpiando = true
        mensajeLimpieza = "Vaciando la Papelera…"
        Task.detached {
            let antes = InfoDisco.actual().libre
            let ok = Limpiador.vaciarPapelera()
            let despues = InfoDisco.actual().libre
            let papelera = Limpiador.tamanoPapelera()
            await MainActor.run {
                self.limpiando = false
                self.disco = InfoDisco.actual()
                self.tamanoPapelera = papelera
                self.elementos.removeAll { $0.accion == .vaciarPapelera }
                self.resultado = ResultadoLimpieza(
                    elementosLimpiados: 1, bytesLimpiados: max(0, despues - antes), libreAntes: antes,
                    libreDespues: despues,
                    errores: ok ? [] : ["No se pudo vaciar toda la Papelera. Dale Acceso total al disco a LimpiadorMac."],
                    modo: .definitivo)
            }
        }
    }

    func actualizarDisco() {
        disco = InfoDisco.actual()
        accesoTotal = Seguridad.tieneAccesoTotal()
        Task.detached {
            let p = Limpiador.tamanoPapelera()
            await MainActor.run { self.tamanoPapelera = p }
        }
    }

    // MARK: Finder

    func mostrarEnFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func abrirAccesoTotal() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
