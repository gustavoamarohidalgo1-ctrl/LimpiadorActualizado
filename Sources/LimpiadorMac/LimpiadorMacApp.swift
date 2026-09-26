import AppKit
import SwiftUI

@main
struct LimpiadorMacApp: App {
    @StateObject private var almacen = Almacen()

    init() {
        // Modo diagnóstico: `LimpiadorMac --diagnostico` imprime el análisis en la terminal sin abrir ventanas.
        if CommandLine.arguments.contains("--diagnostico") {
            Diagnostico.ejecutar()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("LimpiadorMac") {
            VistaPrincipal()
                .environmentObject(almacen)
                .frame(minWidth: 1000, minHeight: 660)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Análisis") {
                Button("Analizar a fondo") { almacen.analizar() }
                    .keyboardShortcut("r")
                    .disabled(almacen.analizando)
            }
        }
    }
}

enum Diagnostico {
    static func ejecutar() {
        let d = InfoDisco.actual()
        print("Disco: \(Formato.bytes(d.libre)) libres de \(Formato.bytes(d.total))")
        print("Acceso total al disco: \(Seguridad.tieneAccesoTotal() ? "sí" : "no")")
        final class Suma: @unchecked Sendable { var total: Int64 = 0; var seleccion: Int64 = 0 }
        let suma = Suma()
        let inicio = Date()
        Escaner().ejecutar(progreso: { _, m in print("\n▶︎ \(m)") }, entrega: { els in
            for e in els {
                suma.total += e.tamano
                if e.seleccionado { suma.seleccion += e.tamano }
                let marca = e.seleccionado ? "[x]" : "[ ]"
                print("  \(marca) \(Formato.bytes(e.tamano).padding(toLength: 10, withPad: " ", startingAt: 0)) \(e.riesgo.etiqueta.padding(toLength: 8, withPad: " ", startingAt: 0)) \(Formato.haceCuanto(e.ultimoUso).padding(toLength: 14, withPad: " ", startingAt: 0)) \(e.nombre)  —  \(Formato.rutaCorta(e.rutaPrincipal))")
            }
        })
        print("\nTotal encontrado: \(Formato.bytes(suma.total)) · Recomendado (preseleccionado): \(Formato.bytes(suma.seleccion))")
        print("Tiempo: \(Int(Date().timeIntervalSince(inicio))) s")
    }
}
