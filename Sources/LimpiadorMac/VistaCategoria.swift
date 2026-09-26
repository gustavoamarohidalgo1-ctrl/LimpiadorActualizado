import SwiftUI

enum Orden: String, CaseIterable, Identifiable {
    case tamano = "Tamaño"
    case antiguedad = "Más tiempo sin usar"
    case nombre = "Nombre"
    var id: String { rawValue }
}

struct VistaCategoria: View {
    @EnvironmentObject var almacen: Almacen
    let categoria: Categoria
    @State private var orden: Orden = .tamano
    @State private var busqueda = ""

    private var lista: [Elemento] {
        var l = almacen.elementos(de: categoria)
        if !busqueda.isEmpty {
            l = l.filter { $0.nombre.localizedCaseInsensitiveContains(busqueda) || $0.rutaPrincipal.path.localizedCaseInsensitiveContains(busqueda) }
        }
        switch orden {
        case .tamano: l.sort { $0.tamano > $1.tamano }
        case .antiguedad: l.sort { ($0.ultimoUso ?? .distantPast) < ($1.ultimoUso ?? .distantPast) }
        case .nombre: l.sort { $0.nombre.localizedCompare($1.nombre) == .orderedAscending }
        }
        return l
    }

    var body: some View {
        VStack(spacing: 0) {
            encabezado
            Divider()
            if lista.isEmpty {
                ContentUnavailableView(
                    almacen.analizando ? "Analizando…" : "Nada por aquí",
                    systemImage: almacen.analizando ? "hourglass" : "checkmark.seal",
                    description: Text(almacen.analizando ? "Todavía estoy revisando esta categoría." : "No encontré nada que ocupe espacio en esta categoría."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(lista) { el in
                            FilaElemento(elemento: el)
                        }
                    }
                    .padding(16)
                }
                .frame(minHeight: 0, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("")
        .searchable(text: $busqueda, placement: .toolbar, prompt: "Buscar")
    }

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: categoria.icono)
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(categoria.titulo).font(.title2.weight(.bold))
                    Text(categoria.subtitulo).foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                VStack(alignment: .trailing) {
                    Text(Formato.bytes(almacen.total(de: categoria)))
                        .font(.title.weight(.bold).monospacedDigit())
                    Text("\(Formato.bytes(almacen.totalSeleccionado(de: categoria))) seleccionados")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            HStack(spacing: 8) {
                Button("Todo") { almacen.seleccionar(categoria) { _ in true } }
                Button("Nada") { almacen.seleccionar(categoria) { _ in false } }
                Button("Solo lo seguro") { almacen.seleccionar(categoria) { $0.riesgo == .seguro } }
                Button("Sin usar +90 días") {
                    almacen.seleccionar(categoria) { ($0.diasSinUso ?? 0) >= 90 && $0.riesgo != .cuidado }
                }
                .help("Marca lo que lleva más de 3 meses sin usarse (excepto lo marcado como «Cuidado»)")
                Spacer()
                Picker("Ordenar por", selection: $orden) {
                    ForEach(Orden.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 250)
            }
            .controlSize(.small)
        }
        .padding(20)
    }
}

struct FilaElemento: View {
    @EnvironmentObject var almacen: Almacen
    let elemento: Elemento

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: almacen.seleccionado(elemento.id))
                .toggleStyle(.checkbox)
                .labelsHidden()
            IconoArchivo(url: elemento.rutaPrincipal)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(elemento.nombre).font(.body.weight(.medium)).lineLimit(1)
                Text(elemento.detalle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(elemento.rutas.count > 1 ? "\(elemento.rutas.count) archivos en \(Formato.rutaCorta(elemento.rutaPrincipal.deletingLastPathComponent()))" : Formato.rutaCorta(elemento.rutaPrincipal))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Formato.bytes(elemento.tamano))
                    .font(.body.weight(.semibold).monospacedDigit())
                HStack(spacing: 6) {
                    Text(Formato.haceCuanto(elemento.ultimoUso))
                        .font(.caption)
                        .foregroundStyle((elemento.diasSinUso ?? 0) >= 90 ? .orange : .secondary)
                        .help("Última vez que se usó o modificó")
                    EtiquetaRiesgo(riesgo: elemento.riesgo)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            elemento.seleccionado ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.background.secondary),
            in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(elemento.seleccionado ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { almacen.alternar(elemento.id) }
        .contextMenu {
            Button("Mostrar en Finder") { almacen.mostrarEnFinder(elemento.rutaPrincipal) }
            Button("Copiar ruta") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(elemento.rutaPrincipal.path, forType: .string)
            }
        }
    }
}

struct EtiquetaRiesgo: View {
    let riesgo: Riesgo

    var color: Color {
        switch riesgo {
        case .seguro: return .green
        case .revisar: return .orange
        case .cuidado: return .red
        }
    }

    var body: some View {
        Text(riesgo.etiqueta)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .help(riesgo.explicacion)
    }
}

struct IconoArchivo: View {
    let url: URL
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
