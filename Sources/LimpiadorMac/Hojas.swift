import SwiftUI

struct HojaConfirmacion: View {
    @EnvironmentObject var almacen: Almacen
    @Environment(\.dismiss) private var cerrar
    @State private var modo: ModoLimpieza = .papelera

    var body: some View {
        let sel = almacen.efectivos
        let delicados = sel.filter { $0.riesgo != .seguro }
        VStack(alignment: .leading, spacing: 18) {
            if almacen.limpiando {
                progreso
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text("Limpiar \(Formato.bytes(almacen.bytesSeleccionados))").font(.title.weight(.bold))
                        Text("\(sel.count) elementos seleccionados").foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Categoria.allCases.filter { c in sel.contains { $0.categoria == c } }) { c in
                        HStack {
                            Label(c.titulo, systemImage: c.icono)
                            Spacer()
                            Text(Formato.bytes(almacen.totalSeleccionado(de: c))).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

                if !delicados.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Revisa estos \(delicados.count) elementos antes de continuar:", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.callout.weight(.semibold))
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(delicados) { el in
                                    HStack {
                                        EtiquetaRiesgo(riesgo: el.riesgo)
                                        Text(el.nombre).lineLimit(1)
                                        Spacer()
                                        Text(Formato.bytes(el.tamano)).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .frame(maxHeight: 130)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $modo) {
                        ForEach(ModoLimpieza.allCases) { Text($0.titulo).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text(modo.descripcion).font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Cancelar") { cerrar() }
                        .keyboardShortcut(.cancelAction)
                    Button(role: modo == .definitivo ? .destructive : nil) {
                        almacen.limpiar(modo: modo)
                    } label: {
                        Text(modo == .papelera ? "Mover a la Papelera" : "Eliminar definitivamente")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(modo == .definitivo ? .red : .accentColor)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: almacen.resultado != nil) { _, hay in
            if hay { cerrar() }
        }
    }

    private var progreso: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Limpiando…").font(.title2.weight(.bold))
            ProgressView(value: almacen.progresoLimpieza)
            Text(almacen.mensajeLimpieza).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct HojaResultado: View {
    @EnvironmentObject var almacen: Almacen
    @Environment(\.dismiss) private var cerrar
    let resultado: ResultadoLimpieza

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: resultado.errores.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(resultado.errores.isEmpty ? .green : .orange)
            if resultado.modo == .papelera {
                Text("\(Formato.bytes(resultado.bytesLimpiados)) movidos a la Papelera").font(.title2.weight(.bold))
                Text("Para liberar el espacio de verdad tienes que vaciar la Papelera.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                if almacen.tamanoPapelera > 0 {
                    BotonVaciarPapelera()
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                Text("¡Listo! Liberaste \(Formato.bytes(max(resultado.liberadoReal, resultado.bytesLimpiados)))")
                    .font(.title2.weight(.bold))
            }
            Text("Ahora tienes \(Formato.bytes(almacen.disco.libre)) libres")
                .font(.headline)
                .foregroundStyle(.green)

            if !resultado.errores.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No se pudo borrar todo (\(resultado.errores.count)):").font(.callout.weight(.semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(resultado.errores, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    Text("Suele pasar con apps abiertas. Ciérralas y vuelve a intentarlo.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
            Button("Cerrar") { cerrar() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 460)
    }
}
