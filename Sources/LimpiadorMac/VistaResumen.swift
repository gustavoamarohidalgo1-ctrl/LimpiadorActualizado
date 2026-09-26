import SwiftUI

struct VistaResumen: View {
    @EnvironmentObject var almacen: Almacen

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                encabezado
                if !almacen.accesoTotal { avisoAcceso }
                tarjetaDisco
                if almacen.analizando {
                    tarjetaProgreso
                } else if !almacen.analizado {
                    botonInicial
                }
                if almacen.analizado || almacen.analizando { cuadricula }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .defaultScrollAnchor(.top)
        .frame(minHeight: 0, maxHeight: .infinity)
    }

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LimpiadorMac").font(.largeTitle.weight(.bold))
            Text("MacBook Air (M2) · 16 GB · SSD de 256 GB")
                .foregroundStyle(.secondary)
        }
    }

    private var avisoAcceso: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Para un análisis completo, dale «Acceso total al disco»").font(.headline)
                Text("Sin ese permiso no puedo medir la Papelera ni algunas carpetas protegidas. Abre Ajustes, activa LimpiadorMac en la lista (o agrégala con +) y vuelve a abrir la app.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abrir Ajustes") { almacen.abrirAccesoTotal() }
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var tarjetaDisco: some View {
        let d = almacen.disco
        let extra = d.total > 0 ? Double(almacen.bytesSeleccionados) / Double(d.total) : 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Espacio libre").font(.headline).foregroundStyle(.secondary)
                    Text(Formato.bytes(d.libre))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(d.fraccionUsada > 0.9 ? .red : .primary)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(d.fraccionUsada * 100)) % usado")
                        .font(.title3.weight(.semibold))
                    Text("\(Formato.bytes(d.usado)) de \(Formato.bytes(d.total))")
                        .foregroundStyle(.secondary)
                }
            }
            BarraDisco(fraccion: d.fraccionUsada, extra: extra)
                .frame(height: 14)
                .animation(.easeInOut, value: extra)
            if almacen.bytesSeleccionados > 0 {
                Label("Si limpias lo seleccionado tendrás unos \(Formato.bytes(d.libre + almacen.bytesSeleccionados)) libres",
                      systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
            } else if d.fraccionUsada > 0.85 {
                Label("macOS va más lento cuando queda menos del 10–15 % libre.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            if almacen.tamanoPapelera > 50_000_000 {
                HStack {
                    Label("La Papelera ocupa \(Formato.bytes(almacen.tamanoPapelera))", systemImage: "trash")
                    Spacer()
                    BotonVaciarPapelera()
                }
                .font(.callout)
            }
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var botonInicial: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("Analiza tu Mac a fondo").font(.title2.weight(.semibold))
            Text("Reviso emuladores, cachés, restos de apps desinstaladas, proyectos, instaladores y archivos grandes. No se borra nada hasta que tú lo confirmes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            Button {
                almacen.analizar()
            } label: {
                Label("Analizar a fondo", systemImage: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var tarjetaProgreso: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ProgressView().controlSize(.small)
                Text(almacen.mensaje).font(.headline)
                Spacer()
                Text("\(Formato.bytes(almacen.totalEncontrado)) encontrados")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: almacen.progreso)
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Mientras analiza el orden es fijo (para que las tarjetas no salten); al terminar, de mayor a menor.
    private var ordenCategorias: [Categoria] {
        guard almacen.analizado else { return Categoria.allCases }
        return Categoria.allCases.sorted { almacen.total(de: $0) > almacen.total(de: $1) }
    }

    private var cuadricula: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lo que encontré").font(.title2.weight(.semibold))
                Spacer()
                if almacen.analizado {
                    Text("\(Formato.bytes(almacen.totalEncontrado)) en total")
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(ordenCategorias) { c in
                    TarjetaCategoria(categoria: c)
                }
            }
        }
    }
}

struct TarjetaCategoria: View {
    @EnvironmentObject var almacen: Almacen
    let categoria: Categoria

    var body: some View {
        let total = almacen.total(de: categoria)
        let sel = almacen.totalSeleccionado(de: categoria)
        let n = almacen.elementos(de: categoria).count
        Button {
            almacen.seccion = .categoria(categoria)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: categoria.icono)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                    Spacer()
                    if total > 0 || !almacen.analizando {
                        Text(total > 0 ? Formato.bytes(total) : "—")
                            .font(.title2.weight(.bold).monospacedDigit())
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: 30)
                Text(categoria.titulo).font(.headline)
                    .lineLimit(1)
                Text(n == 0 ? (almacen.analizando ? "Analizando…" : "Nada que limpiar")
                     : "\(n) \(n == 1 ? "elemento" : "elementos") · \(sel > 0 ? Formato.bytes(sel) + " seleccionados" : "nada seleccionado")")
                    .font(.caption)
                    .foregroundStyle(sel > 0 ? .green : .secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .opacity(total > 0 ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }
}

struct BotonVaciarPapelera: View {
    @EnvironmentObject var almacen: Almacen
    @State private var confirmar = false

    var body: some View {
        Button("Vaciar Papelera") { confirmar = true }
            .disabled(almacen.limpiando)
            .confirmationDialog("¿Vaciar la Papelera?", isPresented: $confirmar) {
                Button("Vaciar Papelera (\(Formato.bytes(almacen.tamanoPapelera)))", role: .destructive) {
                    almacen.vaciarPapelera()
                }
            } message: {
                Text("Lo que está en la Papelera se borrará para siempre.")
            }
    }
}
