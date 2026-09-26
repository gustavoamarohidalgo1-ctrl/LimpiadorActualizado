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
    @Published var elementos: [Elemento] = [] { didSet { recalcular() } }
    @Published var analizando = false
    @Published var estado = EstadoAnalisis(fraccion: 0, fase: 0, mensaje: "")
    @Published var analizado = false
    @Published var disco = InfoDisco.actual()
    @Published var limpiando = false
    @Published var progresoLimpieza: Double = 0
    @Published var mensajeLimpieza = ""
    @Published var resultado: ResultadoLimpieza?
    @Published var tamanoPapelera: Int64 = 0
    @Published var accesoTotal = Seguridad.tieneAccesoTotal()
    @Published var seccion: Seccion? = .resumen
    /// Elemento que se muestra en el panel de detalle.
    @Published var detalle: Elemento.ID?
    @Published var ultimaLimpieza: LimpiezaGuardada? = Historial.cargarUltima()
    @Published var mensajeDeshacer: String?
    @Published private(set) var indice: Indice?
    @Published private(set) var bytesSeleccionados: Int64 = 0
    @Published private(set) var efectivos: [Elemento] = []
    @Published private(set) var totales: [Categoria: Int64] = [:]
    @Published private(set) var totalesSeleccionados: [Categoria: Int64] = [:]
    @Published private(set) var totalEncontrado: Int64 = 0
    @Published private(set) var duracionAnalisis: TimeInterval = 0

    // MARK: Análisis

    func analizar() {
        guard !analizando else { return }
        analizando = true
        analizado = false
        elementos = []
        resultado = nil
        detalle = nil
        accesoTotal = Seguridad.tieneAccesoTotal()
        estado = EstadoAnalisis(fraccion: 0, fase: 0, mensaje: "Preparando…")
        let inicio = Date()
        Task.detached(priority: .userInitiated) {
            let indice = Escaner().ejecutar(
                progreso: { e in Task { @MainActor in self.estado = e } },
                entrega: { nuevos in Task { @MainActor in self.elementos.append(contentsOf: nuevos) } })
            let papelera = Limpiador.tamanoPapelera()
            await MainActor.run {
                self.indice = indice
                self.analizando = false
                self.analizado = true
                self.duracionAnalisis = Date().timeIntervalSince(inicio)
                self.disco = InfoDisco.actual()
                self.tamanoPapelera = papelera
                self.ultimaLimpieza = Historial.cargarUltima()
            }
        }
    }

    // MARK: Consultas

    func elementos(de c: Categoria) -> [Elemento] {
        elementos.filter { $0.categoria == c }
    }

    func total(de c: Categoria) -> Int64 { totales[c] ?? 0 }

    func totalSeleccionado(de c: Categoria) -> Int64 { totalesSeleccionados[c] ?? 0 }

    func elemento(_ id: Elemento.ID?) -> Elemento? {
        guard let id else { return nil }
        return elementos.first { $0.id == id }
    }

    /// Lo que conviene revisar sí o sí: elementos con avisos graves.
    var avisosImportantes: [Elemento] {
        elementos.filter { el in el.motivos.contains { $0.nivel == .peligro } }
            .sorted { $0.tamano > $1.tamano }
    }

    /// Qué elemento del análisis corresponde a una ruta (para el explorador).
    func elemento(enRuta ruta: String) -> Elemento? {
        elementos.first { el in el.rutas.contains { $0.path == ruta } }
    }

    /// Todos los totales cuentan cada ruta una sola vez, aunque esté en dos elementos
    /// (el emulador entero y su «Restablecer») o dentro de otra carpeta ya contada.
    private func recalcular() {
        var t: [Categoria: Int64] = [:]
        var s: [Categoria: Int64] = [:]
        let porCategoria = Dictionary(grouping: elementos, by: \.categoria)
        for (c, lista) in porCategoria {
            t[c] = Self.sumaSinRepetir(lista)
            s[c] = Self.sumaSinRepetir(lista.filter(\.seleccionado))
        }
        totales = t
        totalesSeleccionados = s
        totalEncontrado = Self.sumaSinRepetir(elementos)

        let seleccionados = elementos.filter(\.seleccionado)
        bytesSeleccionados = Self.sumaSinRepetir(seleccionados)
        // Un elemento se limpia si le queda alguna ruta que no esté dentro de otra seleccionada.
        let rutas = Set(seleccionados.filter { $0.accion == .borrar }.flatMap { $0.rutas.map(\.path) })
        efectivos = seleccionados.filter { el in
            guard el.accion == .borrar else { return true }
            return el.rutas.contains { !Self.dentroDe($0.path, rutas) }
        }
    }

    private static func sumaSinRepetir(_ lista: [Elemento]) -> Int64 {
        var total: Int64 = 0
        var pares: [(String, Int64)] = []
        for el in lista {
            if el.accion != .borrar || el.tamanoFijo != nil {
                total += el.tamano
                continue
            }
            for (i, u) in el.rutas.enumerated() {
                pares.append((u.path, i < el.tamanosRutas.count ? el.tamanosRutas[i] : 0))
            }
        }
        pares.sort { $0.0.count < $1.0.count }
        var contadas = Set<String>()
        for (ruta, bytes) in pares where !contadas.contains(ruta) && !dentroDe(ruta, contadas) {
            contadas.insert(ruta)
            total += bytes
        }
        return total
    }

    /// ¿Alguna carpeta superior de `ruta` está en el conjunto?
    private static func dentroDe(_ ruta: String, _ conjunto: Set<String>) -> Bool {
        var actual = Substring(ruta)
        while let barra = actual.lastIndex(of: "/"), barra > actual.startIndex {
            actual = actual[..<barra]
            if conjunto.contains(String(actual)) { return true }
        }
        return false
    }

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
        var copia = elementos
        for i in copia.indices where copia[i].categoria == c { copia[i].seleccionado = criterio(copia[i]) }
        elementos = copia
    }

    /// Lo que recomendó el análisis: seguro, sin avisos y que no se esté usando.
    func seleccionarRecomendados() {
        var copia = elementos
        for i in copia.indices {
            copia[i].seleccionado = copia[i].recomendado && copia[i].avisos.isEmpty && !copia[i].abiertoAhora
        }
        elementos = copia
    }

    func irA(_ el: Elemento) {
        seccion = .categoria(el.categoria)
        detalle = el.id
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
                let omitidos = Set(r.omitidos)
                // Quita de la lista lo que se limpió (lo omitido o fallido sigue apareciendo).
                self.elementos.removeAll { el in
                    guard !omitidos.contains(where: { $0.hasPrefix(el.nombre + ":") }) else { return false }
                    return el.accion == .borrar
                        ? !el.rutas.contains(where: Rutas.existe)
                        : limpiados.contains(el.id)
                }
                self.resultado = r
                self.limpiando = false
                self.disco = InfoDisco.actual()
                self.tamanoPapelera = papelera
                self.ultimaLimpieza = Historial.cargarUltima()
                self.mensajeDeshacer = nil
            }
        }
    }

    func deshacer() {
        guard let l = ultimaLimpieza, !limpiando else { return }
        limpiando = true
        mensajeLimpieza = "Devolviendo todo a su sitio…"
        Task.detached {
            let r = Historial.deshacer(l)
            let papelera = Limpiador.tamanoPapelera()
            await MainActor.run {
                self.limpiando = false
                self.ultimaLimpieza = nil
                self.tamanoPapelera = papelera
                self.disco = InfoDisco.actual()
                var texto = "Devolví \(r.restaurados) \(r.restaurados == 1 ? "elemento" : "elementos") a su sitio (\(Formato.bytes(r.bytes)))."
                if !r.errores.isEmpty { texto += " \(r.errores.count) no se pudieron devolver." }
                self.mensajeDeshacer = texto
                self.resultado = nil
                // Lo restaurado vuelve a aparecer en el próximo análisis.
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
                self.ultimaLimpieza = nil
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
        ultimaLimpieza = Historial.cargarUltima()
        Task.detached {
            let p = Limpiador.tamanoPapelera()
            await MainActor.run { self.tamanoPapelera = p }
        }
    }

    /// Vuelve a mirar qué apps están abiertas (por si el usuario las cerró tras el análisis).
    func comprobarAppsAbiertas() {
        Task.detached {
            let p = Procesos.capturar()
            await MainActor.run {
                var copia = self.elementos
                for i in copia.indices {
                    guard let uso = copia[i].enUso else { continue }
                    let abierta = p.estaEnUso(uso)
                    if copia[i].abiertoAhora && !abierta {
                        copia[i].abiertoAhora = false
                        copia[i].motivos.removeAll { $0.icono == "macwindow.badge.plus" || $0.icono == "play.circle.fill" }
                    } else if abierta {
                        copia[i].abiertoAhora = true
                    }
                }
                self.elementos = copia
            }
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

    func abrirHistorial() {
        if Rutas.existe(Historial.registroURL) { NSWorkspace.shared.open(Historial.registroURL) }
    }
}
