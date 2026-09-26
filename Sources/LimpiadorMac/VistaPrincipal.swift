import SwiftUI

struct VistaPrincipal: View {
    @EnvironmentObject var almacen: Almacen
    @State private var mostrarConfirmacion = false

    var body: some View {
        NavigationSplitView {
            BarraLateral()
                .navigationSplitViewColumnWidth(min: 290, ideal: 310, max: 380)
        } detail: {
            Group {
                switch almacen.seccion ?? .resumen {
                case .resumen: VistaResumen()
                case .explorador: VistaExplorador()
                case .categoria(let c): VistaCategoria(categoria: c)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                if almacen.seccion != .explorador && almacen.analizado {
                    BarraLimpiar(mostrarConfirmacion: $mostrarConfirmacion)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    almacen.analizar()
                } label: {
                    Label(almacen.analizado ? "Volver a analizar" : "Analizar a fondo",
                          systemImage: almacen.analizado ? "arrow.clockwise" : "sparkle.magnifyingglass")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 4)
                }
                .disabled(almacen.analizando || almacen.limpiando)
                .help("Revisa todo el Mac en busca de cosas que se pueden borrar")
            }
        }
        .sheet(isPresented: $mostrarConfirmacion) {
            HojaConfirmacion()
        }
        .sheet(item: Binding(get: { almacen.resultado.map { ResultadoID(r: $0) } },
                             set: { if $0 == nil { almacen.resultado = nil } })) { item in
            HojaResultado(resultado: item.r)
        }
        .onAppear {
            almacen.actualizarDisco()
            // `--analizar [categoria]` arranca el análisis al abrir (útil para probar la interfaz).
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--analizar") {
                almacen.analizar()
                if i + 1 < args.count, let c = Categoria(rawValue: args[i + 1]) { almacen.seccion = .categoria(c) }
            }
        }
    }
}

private struct ResultadoID: Identifiable {
    let id = UUID()
    let r: ResultadoLimpieza
}

struct BarraLateral: View {
    @EnvironmentObject var almacen: Almacen

    var body: some View {
        List(selection: $almacen.seccion) {
            Section {
                Label("Resumen", systemImage: "gauge.with.dots.needle.67percent")
                    .tag(Seccion.resumen)
                Label("Explorador de espacio", systemImage: "chart.bar.doc.horizontal")
                    .tag(Seccion.explorador)
            }
            if almacen.analizado || almacen.analizando {
                Section("Lo que encontré") {
                    ForEach(Categoria.allCases) { c in
                        let total = almacen.total(de: c)
                        HStack {
                            Label(c.titulo, systemImage: c.icono)
                                .lineLimit(1)
                            Spacer()
                            if total > 0 {
                                Text(Formato.bytes(total))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(Seccion.categoria(c))
                        .opacity(total > 0 ? 1 : 0.45)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minHeight: 0, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            MiniDisco()
                .padding(12)
        }
    }
}

struct MiniDisco: View {
    @EnvironmentObject var almacen: Almacen

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive.fill")
                Text("Macintosh HD").font(.caption.weight(.semibold))
                Spacer()
            }
            BarraDisco(fraccion: almacen.disco.fraccionUsada, extra: 0)
                .frame(height: 6)
            Text("\(Formato.bytes(almacen.disco.libre)) libres de \(Formato.bytes(almacen.disco.total))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Barra de uso del disco. `extra` marca en verde lo que se liberaría al limpiar.
struct BarraDisco: View {
    var fraccion: Double
    var extra: Double

    var color: Color {
        fraccion > 0.9 ? .red : fraccion > 0.8 ? .orange : .accentColor
    }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color.gradient)
                    .frame(width: g.size.width * min(1, fraccion))
                if extra > 0 {
                    Rectangle().fill(Color.green.gradient)
                        .frame(width: g.size.width * min(fraccion, extra))
                        .offset(x: g.size.width * max(0, fraccion - extra))
                }
            }
            .clipShape(Capsule())
        }
    }
}

struct BarraLimpiar: View {
    @EnvironmentObject var almacen: Almacen
    @Binding var mostrarConfirmacion: Bool

    var body: some View {
        let seleccion = almacen.efectivos
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(seleccion.isEmpty ? "Nada seleccionado" : "Seleccionado: \(Formato.bytes(almacen.bytesSeleccionados))")
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
                Text(seleccion.isEmpty
                     ? "Marca lo que quieras borrar en cada categoría."
                     : "\(seleccion.count) elementos en \(Set(seleccion.map(\.categoria)).count) categorías")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Seleccionar lo recomendado") { almacen.seleccionarRecomendados() }
                .controlSize(.large)
                .help("Marca solo lo que es seguro borrar")
            Button {
                mostrarConfirmacion = true
            } label: {
                Label("Limpiar", systemImage: "sparkles")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(seleccion.isEmpty || almacen.analizando || almacen.limpiando)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .animation(.default, value: almacen.bytesSeleccionados)
    }
}
