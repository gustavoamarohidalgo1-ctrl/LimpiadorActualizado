import AppKit
import SwiftUI

@main
struct LimpiadorMacApp: App {
    @StateObject private var almacen = Almacen()

    init() {
        // Modo diagnóstico: `LimpiadorMac --diagnostico` imprime el análisis en la terminal sin abrir ventanas.
        if CommandLine.arguments.contains("--diagnostico") {
            Diagnostico.ejecutar(detallado: CommandLine.arguments.contains("--motivos"))
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("LimpiadorMac") {
            VistaPrincipal()
                .environmentObject(almacen)
                .frame(minWidth: 1180, minHeight: 700)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Análisis") {
                Button("Analizar a fondo") { almacen.analizar() }
                    .keyboardShortcut("r")
                    .disabled(almacen.analizando)
                Button("Ver historial de limpiezas") { almacen.abrirHistorial() }
            }
        }
    }
}

enum Diagnostico {
    static func ejecutar(detallado: Bool) {
        let d = InfoDisco.actual()
        print("Disco «\(d.nombre)»: \(Formato.bytes(d.libre)) libres de \(Formato.bytes(d.total)) (\(Formato.bytes(d.purgable)) purgables)")
        print("Acceso total al disco: \(Seguridad.tieneAccesoTotal() ? "sí" : "no")")
        print("Carpeta personal analizada: \(Rutas.home.path)")
        print("Temporales del sistema: \(Sistema.temporal ?? "?") · Cachés del sistema: \(Sistema.caches ?? "?")")
        final class Suma: @unchecked Sendable {
            var total: Int64 = 0
            var seleccion: Int64 = 0
            var rutasSeleccion: [String] = []
            var porRiesgo: [Riesgo: Int] = [:]
            var ultimaFase = -1
            var inicioFase = Date()
        }
        let suma = Suma()
        let inicio = Date()
        let indice = Escaner().ejecutar(
            progreso: { e in
                if e.fase != suma.ultimaFase {
                    if suma.ultimaFase >= 0 {
                        print("  (\(String(format: "%.1f", Date().timeIntervalSince(suma.inicioFase))) s)")
                    }
                    suma.ultimaFase = e.fase
                    suma.inicioFase = Date()
                    print("\n▶︎ \(e.mensaje)  \(e.detalle)")
                    fflush(stdout)
                }
            },
            entrega: { els in
                for e in els {
                    suma.total += e.tamano
                    if e.seleccionado { suma.seleccion += e.tamano }
                    if e.seleccionado && e.accion == .borrar { suma.rutasSeleccion += e.rutas.map(\.path) }
                    suma.porRiesgo[e.riesgo, default: 0] += 1
                    let marca = e.seleccionado ? "[x]" : "[ ]"
                    let abierta = e.abiertoAhora ? " ⚡︎" : ""
                    print("  \(marca) \(Formato.bytes(e.tamano).padding(toLength: 10, withPad: " ", startingAt: 0)) \(e.riesgo.etiqueta.padding(toLength: 8, withPad: " ", startingAt: 0)) \(Formato.haceCuanto(e.ultimoUso).padding(toLength: 14, withPad: " ", startingAt: 0)) \(e.nombre)\(abierta)  —  \(e.rutas.count > 1 ? "\(e.rutas.count) rutas" : Formato.rutaCorta(e.rutaPrincipal))")
                    let mostrar = detallado ? e.motivos : e.motivos.filter { $0.nivel >= .aviso }
                    for m in mostrar {
                        let icono = ["✓", "·", "!", "✗"][m.nivel.rawValue]
                        print("         \(icono) \(m.etiqueta): \(m.texto)")
                    }
                }
            })
        print("\nÍndice: \(Formato.numero(indice.archivosTotales)) archivos, \(Formato.bytes(indice.bytesTotales)), \(indice.carpetas.count) carpetas registradas, \(String(format: "%.1f", indice.duracion)) s (sin permiso: \(indice.sinPermiso))")
        print("Sensibles: \(indice.sensibles.count) · Repos: \(indice.repos.count) · Releases: \(indice.releases.count) · Artefactos: \(indice.artefactos.count) · Duplicables: \(indice.duplicables.count)")
        print("Total encontrado: \(Formato.bytes(suma.total)) · Preseleccionado: \(Formato.bytes(suma.seleccion))")
        let real = EspacioReal.calcular(suma.rutasSeleccion)
        print("Lo preseleccionado que se borra de la carpeta libera de verdad \(Formato.bytes(real.liberable)) "
              + "(\(Formato.numero(real.archivos)) archivos; \(Formato.bytes(real.compartido)) compartidos con clones, instantáneas o enlaces)")
        print("Por riesgo: seguro \(suma.porRiesgo[.seguro] ?? 0), revisar \(suma.porRiesgo[.revisar] ?? 0), cuidado \(suma.porRiesgo[.cuidado] ?? 0)")
        print("Tiempo total: \(String(format: "%.1f", Date().timeIntervalSince(inicio))) s")
    }
}
