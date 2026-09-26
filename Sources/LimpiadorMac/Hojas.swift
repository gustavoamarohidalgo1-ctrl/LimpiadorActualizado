import SwiftUI

struct HojaConfirmacion: View {
    @EnvironmentObject var almacen: Almacen
    @Environment(\.dismiss) private var cerrar
    @State private var modo: ModoLimpieza = .papelera
    @State private var entendido = false

    var body: some View {
        let sel = almacen.efectivos
        let seguros = sel.filter { $0.riesgo == .seguro }
        let revisar = sel.filter { $0.riesgo == .revisar }
        let cuidado = sel.filter { $0.riesgo == .cuidado }
        let abiertos = sel.filter { $0.abiertoAhora }

        VStack(alignment: .leading, spacing: 16) {
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        GrupoRiesgo(riesgo: .seguro, elementos: seguros, resumido: true)
                        GrupoRiesgo(riesgo: .revisar, elementos: revisar, resumido: false)
                        GrupoRiesgo(riesgo: .cuidado, elementos: cuidado, resumido: false)
                    }
                }
                .frame(maxHeight: 300)

                if !abiertos.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bolt.circle.fill").foregroundStyle(.orange).font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hay \(abiertos.count) \(abiertos.count == 1 ? "elemento" : "elementos") en uso ahora mismo")
                                .font(.callout.weight(.semibold))
                            Text("Cierra \(Formato.listaCorta(Array(Set(abiertos.compactMap(\.dueno))).sorted())) antes de limpiar. Si siguen abiertas, me saltaré sus archivos para no causarles problemas.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Comprobar otra vez") { almacen.comprobarAppsAbiertas() }
                            .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $modo) {
                        ForEach(ModoLimpieza.allCases) { Text($0.titulo).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text(modo.descripcion).font(.caption).foregroundStyle(.secondary)
                }

                if !cuidado.isEmpty {
                    Toggle(isOn: $entendido) {
                        Text("Revisé lo marcado como «Cuidado» y quiero borrarlo")
                            .font(.callout.weight(.medium))
                    }
                    .toggleStyle(.checkbox)
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
                    .disabled(!cuidado.isEmpty && !entendido)
                    .help("Hay que hacer clic: por seguridad, la tecla Enter no borra nada")
                }
            }
        }
        .padding(24)
        .frame(width: 580)
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

private struct GrupoRiesgo: View {
    let riesgo: Riesgo
    let elementos: [Elemento]
    let resumido: Bool

    var body: some View {
        if !elementos.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    EtiquetaRiesgo(riesgo: riesgo)
                    Text("\(elementos.count) \(elementos.count == 1 ? "elemento" : "elementos")")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(Formato.bytes(elementos.reduce(0) { $0 + $1.tamano }))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if resumido {
                    Text(Formato.listaCorta(elementos.sorted { $0.tamano > $1.tamano }.map(\.nombre), maximo: 4))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    ForEach(elementos.sorted { $0.tamano > $1.tamano }) { el in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(el.nombre).font(.caption.weight(.medium)).lineLimit(1)
                                if let m = el.avisos.first ?? el.motivos.first {
                                    Label(m.texto, systemImage: m.icono)
                                        .font(.caption2)
                                        .foregroundStyle(ColorMotivo.de(m.nivel))
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Formato.bytes(el.tamano))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .background(EtiquetaRiesgo.color(riesgo).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct HojaResultado: View {
    @EnvironmentObject var almacen: Almacen
    @Environment(\.dismiss) private var cerrar
    let resultado: ResultadoLimpieza

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: resultado.errores.isEmpty && resultado.omitidos.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(resultado.errores.isEmpty && resultado.omitidos.isEmpty ? .green : .orange)
            if resultado.modo == .papelera {
                Text("\(Formato.bytes(resultado.bytesLimpiados)) movidos a la Papelera").font(.title2.weight(.bold))
                Text("Para liberar el espacio de verdad tienes que vaciar la Papelera. Mientras tanto, puedes deshacerlo.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Text("¡Listo! Liberaste \(Formato.bytes(max(resultado.liberadoReal, resultado.bytesLimpiados)))")
                    .font(.title2.weight(.bold))
                if resultado.forzadosAPapelera > 0 {
                    Text("Por seguridad, \(resultado.forzadosAPapelera) \(resultado.forzadosAPapelera == 1 ? "elemento marcado" : "elementos marcados") como Revisar o Cuidado se \(resultado.forzadosAPapelera == 1 ? "movió" : "movieron") a la Papelera en vez de eliminarse.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            Text("Ahora tienes \(Formato.bytes(almacen.disco.libre)) libres")
                .font(.headline)
                .foregroundStyle(.green)

            if !resultado.omitidos.isEmpty {
                ListaMensajes(titulo: "Me salté \(resultado.omitidos.count) \(resultado.omitidos.count == 1 ? "elemento" : "elementos") porque estaba en uso:",
                              mensajes: resultado.omitidos, color: .orange)
            }
            if !resultado.errores.isEmpty {
                ListaMensajes(titulo: "No se pudo borrar todo (\(resultado.errores.count)):", mensajes: resultado.errores, color: .secondary)
            }

            HStack {
                if resultado.restaurables > 0, almacen.ultimaLimpieza != nil {
                    Button {
                        almacen.deshacer()
                        cerrar()
                    } label: {
                        Label("Deshacer", systemImage: "arrow.uturn.backward")
                    }
                    .help("Devuelve todo a su sitio original")
                }
                Spacer()
                if resultado.modo == .papelera && almacen.tamanoPapelera > 0 {
                    BotonVaciarPapelera()
                }
                Button("Cerrar") { cerrar() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 500)
    }
}

private struct ListaMensajes: View {
    let titulo: String
    let mensajes: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.callout.weight(.semibold)).foregroundStyle(color)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(mensajes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}
