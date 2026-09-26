import SwiftUI

/// Recorre las carpetas ordenadas por tamaño para ver en detalle qué ocupa espacio.
struct VistaExplorador: View {
    @EnvironmentObject var almacen: Almacen
    @State private var ruta: [URL] = [Rutas.home]
    @State private var hijos: [(url: URL, tamano: Int64)] = []
    @State private var cargando = false
    @State private var cache: [URL: [(url: URL, tamano: Int64)]] = [:]
    @State private var aBorrar: URL?

    private var actual: URL { ruta.last ?? Rutas.home }
    private var total: Int64 { hijos.reduce(0) { $0 + $1.tamano } }

    var body: some View {
        VStack(spacing: 0) {
            barraRuta
            Divider()
            if cargando {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Midiendo \(Formato.rutaCorta(actual))…").foregroundStyle(.secondary)
                    Text("La primera vez puede tardar un minuto.").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(hijos.enumerated()), id: \.element.url) { i, h in
                            fila(h.url, h.tamano)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(i.isMultiple(of: 2) ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(.clear),
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(12)
                }
                .frame(minHeight: 0, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Explorador de espacio")
        .task(id: actual) { await cargar() }
        .confirmationDialog("¿Mover a la Papelera?", isPresented: Binding(get: { aBorrar != nil }, set: { if !$0 { aBorrar = nil } })) {
            Button("Mover a la Papelera", role: .destructive) {
                if let u = aBorrar { moverAPapelera(u) }
            }
        } message: {
            Text(aBorrar.map { Formato.rutaCorta($0) } ?? "")
        }
    }

    private var barraRuta: some View {
        HStack(spacing: 6) {
            Button {
                if ruta.count > 1 { ruta.removeLast() }
            } label: { Image(systemName: "chevron.left") }
            .disabled(ruta.count <= 1)
            ForEach(Array(ruta.enumerated()), id: \.offset) { i, u in
                if i > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                Button(i == 0 ? "Carpeta personal" : u.lastPathComponent) {
                    ruta = Array(ruta.prefix(i + 1))
                }
                .buttonStyle(.plain)
                .fontWeight(i == ruta.count - 1 ? .semibold : .regular)
            }
            Spacer()
            Menu("Ir a") {
                Button("Carpeta personal") { ruta = [Rutas.home] }
                Button("Library (datos de apps)") { ruta = [Rutas.home, Rutas.enHome("Library")] }
                Button("Aplicaciones") { ruta = [URL(fileURLWithPath: "/Applications")] }
                Button("Carpeta compartida") { ruta = [URL(fileURLWithPath: "/Users/Shared")] }
            }
            .fixedSize()
            Button {
                cache[actual] = nil
                Task { await cargar() }
            } label: { Image(systemName: "arrow.clockwise") }
            .help("Volver a medir")
            if !cargando {
                Text(Formato.bytes(total)).font(.headline.monospacedDigit())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func fila(_ url: URL, _ tamano: Int64) -> some View {
        let esCarpeta = Rutas.esCarpeta(url) && url.pathExtension != "app"
        let fraccion = total > 0 ? Double(tamano) / Double(total) : 0
        return HStack(spacing: 10) {
            IconoArchivo(url: url).frame(width: 22, height: 22)
            Text(url.lastPathComponent).lineLimit(1)
            Spacer()
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor.gradient).frame(width: max(2, g.size.width * fraccion))
                }
            }
            .frame(width: 160, height: 6)
            Text(Formato.bytes(tamano))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .opacity(esCarpeta ? 1 : 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { if esCarpeta { ruta.append(url) } }
        .contextMenu {
            Button("Mostrar en Finder") { almacen.mostrarEnFinder(url) }
            Divider()
            Button("Mover a la Papelera…", role: .destructive) { aBorrar = url }
                .disabled(!Seguridad.sePuedeBorrar(url))
        }
    }

    private func cargar() async {
        let destino = actual
        if let c = cache[destino] { hijos = c; return }
        cargando = true
        let r = await Task.detached(priority: .userInitiated) { Tamanos.hijos(de: destino) }.value
        guard destino == actual else { return }
        cache[destino] = r
        hijos = r
        cargando = false
    }

    private func moverAPapelera(_ url: URL) {
        guard Seguridad.sePuedeBorrar(url) else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            hijos.removeAll { $0.url == url }
            // Las carpetas padre ahora pesan menos: se vuelven a medir al visitarlas.
            for u in ruta { cache[u] = nil }
            cache[actual] = hijos
            almacen.actualizarDisco()
        } catch {
            NSSound.beep()
        }
    }
}
