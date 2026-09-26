import SwiftUI

/// Panel lateral: todo lo que el análisis sabe de un elemento y por qué es (o no) seguro borrarlo.
struct VistaDetalle: View {
    @EnvironmentObject var almacen: Almacen
    let elemento: Elemento

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cabecera
                veredicto
                if !elemento.motivos.isEmpty {
                    BloqueDetalle(titulo: "Por qué") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(elemento.motivos, id: \.self) { FilaMotivo(motivo: $0) }
                        }
                    }
                }
                BloqueDetalle(titulo: "Si lo borras") {
                    Text(elemento.consecuencia)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                contenido
                ubicaciones
                acciones
            }
            .padding(18)
        }
    }

    // MARK: Partes

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                IconoArchivo(url: elemento.rutaPrincipal)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(elemento.nombre)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                    Label(elemento.categoria.titulo, systemImage: elemento.categoria.icono)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(elemento.detalle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 18) {
                Dato(titulo: "Ocupa", valor: Formato.bytes(elemento.tamano))
                Dato(titulo: "Último uso", valor: Formato.haceCuanto(elemento.ultimoUso))
                if let dueno = elemento.dueno { Dato(titulo: "Pertenece a", valor: dueno) }
            }
        }
    }

    private var veredicto: some View {
        let color = EtiquetaRiesgo.color(elemento.riesgo)
        let resumen: String
        if elemento.abiertoAhora {
            resumen = "Ahora mismo algo lo está usando: ciérralo antes de limpiar."
        } else if let peor = elemento.avisos.first {
            resumen = peor.texto
        } else {
            resumen = elemento.riesgo.explicacion
        }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: elemento.riesgo.icono)
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(elemento.riesgo.veredicto).font(.headline)
                Text(resumen)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var contenido: some View {
        let c = elemento.contenido
        let subcarpetas = elemento.rutas.count == 1 ? partesMasGrandes(de: elemento.rutaPrincipal.path) : []
        let archivos = elemento.rutas.compactMap { almacen.indice?.info($0.path)?.archivos }.reduce(0) { $0 + Int($1) }
        if !c.vacio || !subcarpetas.isEmpty || archivos > 0 {
            BloqueDetalle(titulo: "Qué contiene") {
                VStack(alignment: .leading, spacing: 10) {
                    if archivos > 0 {
                        Text("\(Formato.numero(archivos)) \(archivos == 1 ? "archivo" : "archivos")")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    let tipos = Self.tipos(c)
                    if !tipos.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tipos, id: \.0) { t in
                                Label(t.0, systemImage: t.1)
                                    .font(.caption)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                    if !subcarpetas.isEmpty {
                        let total = max(subcarpetas.reduce(0) { $0 + $1.bytes }, 1)
                        VStack(spacing: 6) {
                            ForEach(subcarpetas.prefix(6), id: \.ruta) { h in
                                HStack(spacing: 8) {
                                    Text(Rutas.nombre(h.ruta))
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    GeometryReader { g in
                                        Capsule().fill(Color.accentColor.opacity(0.7))
                                            .frame(width: max(3, g.size.width * Double(h.bytes) / Double(total)))
                                    }
                                    .frame(width: 60, height: 5)
                                    Text(Formato.bytes(h.bytes))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 64, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Subcarpetas y archivos grandes que hay directamente dentro, de mayor a menor.
    private func partesMasGrandes(de ruta: String) -> [(ruta: String, bytes: Int64)] {
        guard let indice = almacen.indice else { return [] }
        let archivos = indice.grandes.filter { $0.carpeta == ruta }.map { (ruta: $0.ruta, bytes: $0.bytes) }
        return (indice.hijosOrdenados(de: ruta) + archivos).sorted { $0.bytes > $1.bytes }
    }

    private static func tipos(_ c: Contenido) -> [(String, String)] {
        var r: [(String, String)] = []
        if c.documentos > 0 { r.append(("\(c.documentos) doc.", "doc.text")) }
        if c.fotos > 0 { r.append(("\(c.fotos) fotos", "photo")) }
        if c.videos > 0 { r.append(("\(c.videos) vídeos", "film")) }
        if c.audio > 0 { r.append(("\(c.audio) audios", "music.note")) }
        if c.codigo > 0 { r.append(("\(c.codigo) código", "chevron.left.forwardslash.chevron.right")) }
        if c.bases > 0 { r.append(("\(c.bases) bases de datos", "cylinder")) }
        return Array(r.prefix(4))
    }

    @ViewBuilder
    private var ubicaciones: some View {
        BloqueDetalle(titulo: elemento.rutas.count == 1 ? "Ubicación" : "\(elemento.rutas.count) ubicaciones") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(elemento.rutas.prefix(12).enumerated()), id: \.offset) { i, u in
                    HStack(spacing: 8) {
                        Text(Formato.rutaCorta(u))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if elemento.rutas.count > 1, i < elemento.tamanosRutas.count, elemento.tamanoFijo == nil {
                            Text(Formato.bytes(elemento.tamanosRutas[i]))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            almacen.mostrarEnFinder(u)
                        } label: {
                            Image(systemName: "magnifyingglass.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Mostrar en Finder")
                    }
                }
                if elemento.rutas.count > 12 {
                    Text("y \(elemento.rutas.count - 12) más…").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var acciones: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Toggle(isOn: almacen.seleccionado(elemento.id)) {
                Text("Marcar para limpiar").font(.callout.weight(.medium))
            }
            .toggleStyle(.switch)
            if elemento.riesgo == .cuidado {
                Text("Si lo marcas, te pediré confirmación otra vez antes de borrarlo y lo enviaré a la Papelera para que puedas recuperarlo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BloqueDetalle<C: View>: View {
    let titulo: String
    @ViewBuilder var contenido: C

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            contenido
        }
    }
}

private struct Dato: View {
    let titulo: String
    let valor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo).font(.caption2).foregroundStyle(.secondary)
            Text(valor).font(.callout.weight(.semibold)).lineLimit(1)
        }
    }
}

struct FilaMotivo: View {
    let motivo: Motivo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: motivo.icono)
                .foregroundStyle(ColorMotivo.de(motivo.nivel))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(motivo.etiqueta).font(.callout.weight(.semibold))
                Text(motivo.texto)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
