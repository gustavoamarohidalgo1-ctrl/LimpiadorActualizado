import SwiftUI

struct VistaResumen: View {
    @EnvironmentObject var almacen: Almacen

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                encabezado
                if !almacen.accesoTotal { avisoAcceso }
                if let mensaje = almacen.mensajeDeshacer { avisoDeshecho(mensaje) }
                if let ultima = almacen.ultimaLimpieza, !almacen.analizando { tarjetaDeshacer(ultima) }
                tarjetaDisco
                if almacen.analizando {
                    tarjetaProgreso
                } else if !almacen.analizado {
                    botonInicial
                }
                if almacen.analizado && !almacen.avisosImportantes.isEmpty { tarjetaAvisos }
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
                Text("Sin ese permiso no puedo medir la Papelera, las cachés de apps de la App Store ni las copias de seguridad de tu iPhone. Abre Ajustes, activa LimpiadorMac en la lista (o agrégala con +) y vuelve a abrir la app.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Abrir Ajustes") { almacen.abrirAccesoTotal() }
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func avisoDeshecho(_ mensaje: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill").font(.title2).foregroundStyle(.green)
            Text(mensaje).font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Volver a analizar") { almacen.analizar() }
        }
        .padding(14)
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tarjetaDeshacer(_ l: LimpiezaGuardada) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle.fill").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tu última limpieza está en la Papelera").font(.headline)
                Text("\(Formato.haceCuanto(l.fecha)) enviaste \(l.movimientos.count) \(l.movimientos.count == 1 ? "cosa" : "cosas") (\(Formato.bytes(l.bytes))). Puedes devolverlas a su sitio o vaciar la Papelera para liberar el espacio.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                almacen.deshacer()
            } label: {
                Label("Deshacer", systemImage: "arrow.uturn.backward")
            }
            .disabled(almacen.limpiando)
            BotonVaciarPapelera()
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
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
            if almacen.tamanoPapelera > 50_000_000 && almacen.ultimaLimpieza == nil {
                HStack {
                    Label("La Papelera ocupa \(Formato.bytes(almacen.tamanoPapelera))", systemImage: "trash")
                    Spacer()
                    BotonVaciarPapelera()
                }
                .font(.callout)
            }
            if almacen.analizado, let indice = almacen.indice {
                Text("Revisé \(Formato.numero(indice.archivosTotales)) archivos (\(Formato.bytes(indice.bytesTotales))) en \(Int(almacen.duracionAnalisis.rounded())) s.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Text("Reviso archivo por archivo tu carpeta personal: emuladores, cachés, restos de apps, proyectos, instaladores, duplicados y archivos grandes. Te explico qué es cada cosa y te aviso de lo que no deberías borrar. No se borra nada hasta que tú lo confirmes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ProgressView().controlSize(.small)
                Text(almacen.estado.mensaje).font(.headline)
                Spacer()
                Text("\(Formato.bytes(almacen.totalEncontrado)) encontrados")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: almacen.estado.fraccion)
            if !almacen.estado.detalle.isEmpty {
                Text(almacen.estado.detalle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(Array(Escaner.fases.enumerated()), id: \.offset) { i, fase in
                    let hecho = i < almacen.estado.fase
                    let actual = i == almacen.estado.fase
                    Label {
                        Text(fase).lineLimit(1)
                    } icon: {
                        Image(systemName: hecho ? "checkmark.circle.fill" : actual ? "circle.dotted" : "circle")
                            .foregroundStyle(hecho ? Color.green : actual ? Color.accentColor : Color.secondary)
                    }
                    .font(.caption)
                    .foregroundStyle(actual ? .primary : .secondary)
                }
            }
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var tarjetaAvisos: some View {
        let avisos = almacen.avisosImportantes
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.red)
                Text("Cosas que no deberías borrar sin revisar").font(.headline)
                Spacer()
                Text("\(avisos.count)").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("Encontré claves, código, archivos tuyos o cosas en uso dentro de elementos que se podrían borrar. No están marcados; te los enseño para que decidas con calma.")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(avisos.prefix(5)) { el in
                    let m = el.motivos.first { $0.nivel == .peligro } ?? el.motivos[0]
                    Button {
                        almacen.irA(el)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: m.icono).foregroundStyle(.red).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(el.nombre).font(.callout.weight(.medium)).lineLimit(1)
                                Text(m.etiqueta + " · " + el.categoria.titulo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Formato.bytes(el.tamano)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if avisos.count > 5 {
                Text("Y \(avisos.count - 5) más: búscalos con la etiqueta roja «Cuidado».").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
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
        let lista = almacen.elementos(de: categoria)
        let n = lista.count
        let cuidado = lista.filter { $0.riesgo == .cuidado }.count
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
                HStack(spacing: 6) {
                    Text(n == 0 ? (almacen.analizando ? "Analizando…" : "Nada que limpiar")
                         : "\(n) \(n == 1 ? "elemento" : "elementos") · \(sel > 0 ? Formato.bytes(sel) + " seleccionados" : "nada seleccionado")")
                        .foregroundStyle(sel > 0 ? .green : .secondary)
                    if cuidado > 0 {
                        Label("\(cuidado)", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .help("\(cuidado) con «Cuidado»")
                    }
                }
                .font(.caption)
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
                Text("Lo que está en la Papelera se borrará para siempre y ya no podrás deshacer la última limpieza.")
            }
    }
}
