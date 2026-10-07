import Foundation

/// conda y mamba, como «conda clean --all»: los comprimidos que ya se descomprimieron, el índice de paquetes, los
/// registros y los paquetes descomprimidos que ya no usa ningún entorno; además, los entornos que llevan meses sin
/// cambios. Solo dentro de tu carpeta (las instalaciones de /opt piden contraseña). No repite lo que ya ofrecen
/// las reglas del catálogo (el índice de algunas instalaciones, las carpetas «share/jupyter/lab/staging»), y no busca
/// los temporales «*.c~»: valen poco y recorrer los entornos es caro.
extension Escaner {
    func detectoresA_Conda(_ c: Contexto) -> [Elemento] {
        Self.condaElementos(c, home: Rutas.home)
    }

    /// Instalaciones de conda y mamba que se buscan en tu carpeta. Solo cuentan si de verdad lo son (`condaInventario`).
    static let condaRaicesConocidas = [
        "miniconda3", "anaconda3", "miniforge3", "mambaforge", "opt/anaconda3", "opt/miniconda3",
        // micromamba 1.x y mamba 2.x.
        "micromamba", ".local/share/mamba",
        // Si la instalación no es tuya, conda guarda aquí tus paquetes y tus entornos.
        ".conda",
        // Las que instalan otras apps: Spyder 6 y reticulate (R).
        "Library/spyder-6", "Library/r-miniconda", "Library/r-miniconda-arm64",
    ]

    /// Carpetas de paquetes cuyos comprimidos ya ofrece otra parte del análisis (hoy, ninguna: este detector los
    /// ofrece todos, con más comprobaciones que la antigua «Descargas de conda»).
    static let condaComprimidosDeEscaner: [String] = []

    /// Si alguno está en marcha, conda o mamba están instalando, actualizando o limpiando: no se ofrece nada.
    static let condaProgramas = ["/bin/conda", "/bin/mamba", "micromamba", "conda-libmamba"]

    /// Un entorno de conda (o una instalación base) y cómo puede aparecer su ruta en la lista de procesos.
    struct CondaPrefijo {
        let ruta: String
        /// En minúsculas y terminadas en «/», como se buscan en `Procesos.lineas`.
        let formas: Set<String>

        func enUso(_ lineas: [String]) -> Bool {
            lineas.contains { l in formas.contains { l.contains($0) } }
        }
    }

    /// Lo que hay de conda y mamba en tu carpeta.
    struct CondaInventario {
        /// Tu carpeta, sin enlaces.
        var casa = ""
        /// Carpetas de paquetes de conda (las que tienen «urls.txt»), dentro de tu carpeta.
        var paquetes: [String] = []
        /// Todos los entornos que se conocen, estén donde estén: deciden qué paquetes se usan.
        var prefijos: [CondaPrefijo] = []
        /// Entornos con nombre (<instalación>/envs/<nombre>) de tus instalaciones. Nunca la base.
        var entornos: [CondaPrefijo] = []
        /// `false` si alguna carpeta de entornos no se pudo listar: entonces no se sabe qué paquetes se usan.
        var completo = true
    }

    /// Todo el grupo sobre una carpeta personal cualquiera. `comprimidosYaOfrecidos`: carpetas de paquetes (relativas
    /// a `home`) cuyos comprimidos ya ofrece otra parte del análisis.
    static func condaElementos(_ c: Contexto, home: URL,
                               comprimidosYaOfrecidos: [String] = Escaner.condaComprimidosDeEscaner,
                               ahora: Date = Date()) -> [Elemento] {
        let lineas = c.procesos.lineas
        // Sin la lista de procesos no se sabe si conda está trabajando ni qué entornos están en marcha.
        guard !lineas.isEmpty else { return [] }
        // conda o mamba trabajando: lo que hay en sus carpetas puede estar a medias.
        if lineas.contains(where: { l in condaProgramas.contains(where: { l.contains($0) }) }) { return [] }
        guard let inv = condaInventario(home: home) else { return [] }
        let casa = home.standardizedFileURL.path
        let yaOfrecidos = Set(comprimidosYaOfrecidos.map { Seguridad.normalizada(casa + "/" + $0) })
        let cubiertas = condaCubiertasPorCatalogo(home: home)
        func sePuedeOfrecer(_ ruta: String) -> Bool {
            !cubiertas.contains(ruta) && !Rutas.estaDentro(ruta, de: cubiertas) && condaOfrecible(ruta, casa: inv.casa)
        }
        // Los paquetes descomprimidos solo se miran si se conocen todos los entornos y ninguno está en marcha.
        let mirarDescomprimidos = inv.completo && !inv.prefijos.contains { $0.enUso(lineas) }
        var r: [Elemento] = []
        var sinUso: [(carpeta: String, nombre: String, paquetes: [String])] = []

        for p in inv.paquetes {
            guard let hijos = try? FileManager.default.contentsOfDirectory(atPath: p) else { continue }
            let nombre = Formato.rutaCorta(Rutas.nombre(p) == "pkgs" ? Rutas.padre(p) : p)

            // a) Comprimidos que conda ya descomprimió («conda clean --tarballs»).
            if !yaOfrecidos.contains(p) {
                let comprimidos = hijos.filter { n in
                    guard n.hasSuffix(".tar.bz2") || n.hasSuffix(".conda"), condaEsNombreDePaquete(n),
                          let st = condaEstado(p + "/" + n), (st.st_mode & S_IFMT) == S_IFREG, st.st_nlink == 1 else { return false }
                    return sePuedeOfrecer(p + "/" + n)
                }.sorted()
                if !comprimidos.isEmpty {
                    let cuantos = comprimidos.count == 1 ? "1 paquete comprimido" : "\(comprimidos.count) paquetes comprimidos"
                    r.append(condaLimpieza(
                        "Descargas de conda (\(nombre))", "\(cuantos) que conda ya descomprimió.",
                        "Nada: los paquetes ya están instalados. Es lo mismo que «conda clean --tarballs».",
                        comprimidos.map { p + "/" + $0 },
                        .bien("archivebox.fill", "Ya descomprimidos", "Conda solo los necesita para instalar, y ya lo hizo.")))
                }
            }

            // b) El índice de paquetes de los canales («conda clean --index-cache»).
            let indice = p + "/cache"
            if condaEsCarpeta(indice) && sePuedeOfrecer(indice) {
                r.append(condaLimpieza(
                    "Índice de paquetes de conda (\(nombre))", "Listas de paquetes disponibles que conda descargó de sus canales.",
                    "conda lo vuelve a descargar la próxima vez que instales algo. Es lo mismo que «conda clean --index-cache».",
                    [indice], .bien("arrow.triangle.2.circlepath", "Se regenera", "conda lo vuelve a descargar cuando lo necesita.")))
            }

            // c) Registros («conda clean --logfiles»).
            let registros = p + "/.logs"
            if condaEsCarpeta(registros) && sePuedeOfrecer(registros) {
                r.append(condaLimpieza(
                    "Registros de conda (\(nombre))", "Registros que conda guardó al instalar paquetes.",
                    "Nada: solo son registros.", [registros],
                    .bien("doc.text.fill", "Solo registros", "conda no los necesita para funcionar.")))
            }

            // d) Paquetes descomprimidos (los que tienen «info») en los que ningún archivo tiene otro enlace duro.
            if mirarDescomprimidos {
                let candidatos = hijos.filter { n in
                    let ruta = p + "/" + n
                    return !n.hasPrefix(".") && n != "cache" && condaEsNombreDePaquete(n) && condaEsCarpeta(ruta)
                        && condaEsCarpeta(ruta + "/info") && condaEsArchivo(ruta + "/info/index.json")
                        && sePuedeOfrecer(ruta) && condaSinEnlaces(ruta)
                }.sorted()
                if !candidatos.isEmpty { sinUso.append((carpeta: p, nombre: nombre, paquetes: candidatos)) }
            }
        }

        // El registro de cada entorno (conda-meta/*.json) dice de qué carpeta sacó cada paquete: los que aparecen ahí se
        // usan aunque sus archivos no tengan otro enlace (entornos enlazados con enlaces simbólicos o con copias). Si un
        // registro no se puede leer, no se ofrece ninguno.
        if !sinUso.isEmpty, let usados = condaPaquetesUsados(inv.prefijos.map(\.ruta)) {
            for s in sinUso {
                let paquetes = s.paquetes.filter { !usados.contains($0) }
                guard !paquetes.isEmpty else { continue }
                let cuantos = paquetes.count == 1 ? "1 paquete" : "\(paquetes.count) paquetes"
                r.append(condaLimpieza(
                    "Paquetes descomprimidos que no usa ningún entorno (\(s.nombre))",
                    "\(cuantos) que conda descomprimió y que ya no usa ningún entorno: \(Formato.listaCorta(paquetes, maximo: 4)).",
                    "conda los vuelve a descomprimir (o descargar) si un entorno nuevo los necesita. Es lo mismo que «conda clean --packages».",
                    paquetes.map { s.carpeta + "/" + $0 },
                    .bien("shippingbox.fill", "Ningún entorno los usa",
                          "Revisé el registro de tus entornos de conda: ninguno tiene instalados estos paquetes.")))
            }
        }

        // g) Entornos con nombre que llevan más de 180 días sin cambios y que nada está usando. La base, nunca.
        let limite = ahora.addingTimeInterval(-180 * 86400)
        for e in inv.entornos where !e.enUso(lineas) && sePuedeOfrecer(e.ruta) {
            guard let st = condaEstado(e.ruta + "/conda-meta/history"), (st.st_mode & S_IFMT) == S_IFREG else { continue }
            let instalado = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            // Lo último que cambió dentro también cuenta (paquetes instalados con pip, por ejemplo).
            let ultimo = max(instalado, c.indice.masReciente(de: [URL(fileURLWithPath: e.ruta)]) ?? instalado)
            guard ultimo < limite else { continue }
            let nombre = Rutas.nombre(e.ruta)
            r.append(Elemento(
                nombre: "Entorno de conda «\(nombre)» sin usar",
                detalle: "Última instalación de paquetes: \(Formato.haceCuanto(instalado).lowercased()).",
                consecuencia: "Los programas y cuadernos que usen este entorno dejarán de funcionar hasta que lo vuelvas a crear (si guardaste su environment.yml, con «conda env create»).",
                rutas: [URL(fileURLWithPath: e.ruta)], ultimoUso: ultimo, categoria: .desarrollo, riesgo: .revisar,
                seleccionado: false,
                motivos: [.info("clock.fill", "Sin cambios hace tiempo",
                                "Nada ha cambiado en este entorno en más de seis meses. Si todavía lo usas (aunque no le instales nada), consérvalo.")],
                enUso: .proceso(nombre: "Entorno \(nombre)", patron: e.ruta.lowercased() + "/"), dueno: "conda"))
        }
        return r
    }

    // MARK: Dónde está cada cosa

    /// Las carpetas de paquetes y los entornos de conda y mamba, o `nil` si .condarc o environments.txt existen y no se
    /// pueden leer: no se sabría dónde guarda conda los paquetes ni qué entornos los usan.
    static func condaInventario(home: URL) -> CondaInventario? {
        let fm = FileManager.default
        let casa = home.standardizedFileURL.path
        var inv = CondaInventario()
        inv.casa = Seguridad.normalizada(casa)
        let dentro = inv.casa + "/"

        var pkgsDirs: [String] = []
        if Rutas.existeSinSeguir(casa + "/.condarc") {
            guard let texto = try? String(contentsOfFile: casa + "/.condarc", encoding: .utf8) else { return nil }
            pkgsDirs = condaPkgsDirs(texto, home: casa)
        }
        var registrados: [String] = []
        if Rutas.existeSinSeguir(casa + "/.conda/environments.txt") {
            guard let texto = try? String(contentsOfFile: casa + "/.conda/environments.txt", encoding: .utf8) else { return nil }
            registrados = condaLineasDeEntornos(texto)
        }

        // Instalaciones: las conocidas y las de environments.txt (lo que va antes de «/envs/», o la propia línea).
        let conocidas = condaRaicesConocidas.map { casa + "/" + $0 }
        var candidatas = conocidas
        for l in registrados {
            if let r = l.range(of: "/envs/", options: .backwards) {
                let raiz = String(l[..<r.lowerBound])
                if raiz.hasPrefix("/") && !l[r.upperBound...].contains("/") { candidatas.append(raiz) }
            } else {
                candidatas.append(l)
            }
        }
        var raices: [String] = []
        var formasDe: [String: Set<String>] = [:]   // ruta real → cómo se escribe
        for cand in candidatas {
            let forma = URL(fileURLWithPath: cand).standardizedFileURL.path
            let real = Seguridad.normalizada(forma)
            guard condaEsCarpeta(real) else { continue }
            if formasDe[real] == nil { raices.append(real) }
            formasDe[real, default: []].formUnion([forma, real])
        }

        // Entornos: cada instalación que lo sea, lo que hay en su «envs» y cada línea de environments.txt, estén donde
        // estén (solo sirven para saber qué paquetes se usan y si algo está en marcha).
        var formasDePrefijo: [String: Set<String>] = [:]
        var orden: [String] = []
        func agregar(_ real: String, _ formas: Set<String>) {
            guard condaEsCarpeta(real + "/conda-meta") else { return }
            if formasDePrefijo[real] == nil { orden.append(real) }
            formasDePrefijo[real, default: []].formUnion(formas.union([real]))
        }
        for raiz in raices {
            let formas = formasDe[raiz] ?? [raiz]
            agregar(raiz, formas)
            let envs = raiz + "/envs"
            guard Rutas.existeSinSeguir(envs) else { continue }
            guard let nombres = try? fm.contentsOfDirectory(atPath: envs) else {
                inv.completo = false
                continue
            }
            for n in nombres { agregar(Seguridad.normalizada(envs + "/" + n), Set(formas.map { $0 + "/envs/" + n })) }
        }
        for l in registrados {
            let forma = URL(fileURLWithPath: l).standardizedFileURL.path
            agregar(Seguridad.normalizada(forma), [forma])
        }
        inv.prefijos = orden.map { p in CondaPrefijo(ruta: p, formas: condaFormas(formasDePrefijo[p] ?? [p])) }

        // Carpetas de paquetes: la «pkgs» de cada instalación de verdad (con «urls.txt», que conda y mamba crean en todas
        // sus carpetas de paquetes) y las de `pkgs_dirs`. Solo dentro de tu carpeta; en Library, solo las conocidas (las
        // demás pueden ser de una app cuya carpeta se ofrece entera).
        let conocidasReales = Set(conocidas.map { Seguridad.normalizada($0) })
        let propia = Seguridad.normalizada(casa + "/.conda")
        var instalaciones: [String] = []
        for raiz in raices where raiz.hasPrefix(dentro) && (!raiz.hasPrefix(dentro + "Library/") || conocidasReales.contains(raiz)) {
            guard condaEsCarpeta(raiz + "/pkgs"), condaEsArchivo(raiz + "/pkgs/urls.txt") else { continue }
            let entornos = (try? fm.contentsOfDirectory(atPath: raiz + "/envs")) ?? []
            let conEntornos = entornos.contains { condaEsArchivo(raiz + "/envs/" + $0 + "/conda-meta/history") }
            guard condaEsArchivo(raiz + "/conda-meta/history") || condaEsCarpeta(raiz + "/condabin") || raiz == propia
                    || conEntornos else { continue }
            instalaciones.append(raiz)
            inv.paquetes.append(raiz + "/pkgs")
        }
        for d in pkgsDirs {
            let real = Seguridad.normalizada(URL(fileURLWithPath: d).standardizedFileURL.path)
            // Nunca tu carpeta ni otra tuya puesta ahí por error: solo las que se llaman como una carpeta de paquetes.
            guard real.hasPrefix(dentro), Rutas.nombre(real).lowercased().contains("pkg"), condaEsCarpeta(real),
                  condaEsArchivo(real + "/urls.txt"), !inv.paquetes.contains(real) else { continue }
            inv.paquetes.append(real)
        }

        // Entornos con nombre de tus instalaciones: no los de apps (viven en Library y la app los usa aunque no cambien)
        // ni nada que sea a su vez una instalación o tenga dentro una carpeta de paquetes.
        for raiz in instalaciones where !raiz.hasPrefix(dentro + "Library/") {
            let envs = raiz + "/envs"
            guard condaEsCarpeta(envs), let nombres = try? fm.contentsOfDirectory(atPath: envs) else { continue }
            for n in nombres.sorted() where !n.hasPrefix(".") {
                let e = envs + "/" + n
                guard condaEsCarpeta(e), condaEsArchivo(e + "/conda-meta/history"), !instalaciones.contains(e),
                      !Rutas.existeSinSeguir(e + "/condabin"), !Rutas.existeSinSeguir(e + "/pkgs/urls.txt"),
                      !inv.paquetes.contains(where: { $0 == e || $0.hasPrefix(e + "/") }) else { continue }
                inv.entornos.append(CondaPrefijo(ruta: e, formas: condaFormas(formasDePrefijo[e] ?? [e])))
            }
        }
        return inv
    }

    /// Lo que ya ofrecen las reglas de conda del catálogo (hoy, el índice de paquetes de algunas instalaciones), tal
    /// como existe ahora: aquí no se repite. Si se quitan esas reglas, este detector lo ofrece solo.
    static func condaCubiertasPorCatalogo(home: URL) -> Set<String> {
        let casa = home.standardizedFileURL.path
        var r = Set<String>()
        for regla in Catalogo.reglas where !regla.requiereAdmin && regla.patron.hasPrefix("~/")
            && ["conda", "mamba", "/pkgs"].contains(where: { regla.patron.contains($0) }) {
            for u in expandir(casa + String(regla.patron.dropFirst(1))) { r.insert(Seguridad.normalizada(u.path)) }
        }
        return r
    }

    /// Los paquetes (carpetas de «pkgs») que usa algún entorno según su registro (conda-meta/*.json), o `nil` si alguno
    /// no se puede leer o no dice qué paquete es: entonces no se sabe cuáles sobran.
    static func condaPaquetesUsados(_ prefijos: [String]) -> Set<String>? {
        var usados = Set<String>()
        for p in prefijos {
            let meta = p + "/conda-meta"
            guard let archivos = try? FileManager.default.contentsOfDirectory(atPath: meta) else { return nil }
            for a in archivos where a.hasSuffix(".json") && !a.hasPrefix(".") {
                guard let datos = FileManager.default.contents(atPath: meta + "/" + a),
                      let registro = try? JSONSerialization.jsonObject(with: datos) as? [String: Any] else { return nil }
                var paquetes: [String] = []
                if let d = registro["extracted_package_dir"] as? String { paquetes.append((d as NSString).lastPathComponent) }
                if let d = (registro["link"] as? [String: Any])?["source"] as? String {
                    paquetes.append((d as NSString).lastPathComponent)
                }
                if let fn = registro["fn"] as? String {
                    for ext in [".tar.bz2", ".conda"] where fn.hasSuffix(ext) { paquetes.append(String(fn.dropLast(ext.count))) }
                }
                if let n = registro["name"] as? String, let v = registro["version"] as? String, let b = registro["build"] as? String {
                    paquetes.append("\(n)-\(v)-\(b)")
                }
                paquetes.removeAll { $0.isEmpty }
                guard !paquetes.isEmpty else { return nil }
                usados.formUnion(paquetes)
            }
        }
        return usados
    }

    /// ¿Se puede borrar este paquete descomprimido sin tocar ningún entorno? Ningún archivo puede tener otro enlace duro
    /// (lo tendría si un entorno lo usa), ningún enlace simbólico puede apuntar fuera y todo se tiene que poder leer.
    /// Con más de 20 000 entradas no se revisa: no se ofrece.
    static func condaSinEnlaces(_ carpeta: String) -> Bool {
        var pendientes = [carpeta]
        var vistas = 0
        while let actual = pendientes.popLast() {
            guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: actual) else { return false }
            for n in nombres {
                vistas += 1
                let ruta = actual + "/" + n
                guard vistas <= 20_000, let st = condaEstado(ruta) else { return false }
                let tipo = st.st_mode & S_IFMT
                if tipo == S_IFDIR {
                    pendientes.append(ruta)
                } else if tipo == S_IFREG {
                    guard st.st_nlink == 1 else { return false }
                } else if tipo == S_IFLNK {
                    guard let destino = try? FileManager.default.destinationOfSymbolicLink(atPath: ruta) else { return false }
                    let apunta = condaSinPuntos(destino.hasPrefix("/") ? destino : actual + "/" + destino)
                    guard apunta == carpeta || apunta.hasPrefix(carpeta + "/") else { return false }
                } else {
                    return false
                }
            }
        }
        return vistas > 0
    }

    // MARK: Configuración de conda

    /// Las carpetas de `pkgs_dirs` de un .condarc. «~», «$HOME» y «${HOME}» son tu carpeta; las rutas relativas o con
    /// otras variables no se entienden y se dejan fuera.
    static func condaPkgsDirs(_ texto: String, home: String) -> [String] {
        var valores: [String] = []
        var enLista = false
        for linea in texto.components(separatedBy: .newlines) {
            var t = linea
            if let comentario = t.range(of: " #") { t = String(t[..<comentario.lowerBound]) }
            t = t.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            if enLista {
                if t.hasPrefix("-") {
                    valores.append(String(t.dropFirst()))
                    continue
                }
                enLista = false
            }
            guard t.hasPrefix("pkgs_dirs:") else { continue }
            let resto = t.dropFirst("pkgs_dirs:".count).trimmingCharacters(in: .whitespaces)
            if resto.isEmpty {
                enLista = true
            } else if resto.hasPrefix("[") && resto.hasSuffix("]") {
                valores += resto.dropFirst().dropLast().split(separator: ",").map(String.init)
            }
        }
        return valores.compactMap { (v: String) -> String? in
            var s = v.trimmingCharacters(in: .whitespaces)
            if s.count >= 2, let q = s.first, (q == "\"" || q == "'") && s.last == q { s = String(s.dropFirst().dropLast()) }
            for variable in ["${HOME}", "$HOME", "~"] where s == variable || s.hasPrefix(variable + "/") {
                s = home + s.dropFirst(variable.count)
                break
            }
            return s.hasPrefix("/") ? s : nil
        }
    }

    /// Las rutas de environments.txt (una por línea), sin «/» al final.
    static func condaLineasDeEntornos(_ texto: String) -> [String] {
        texto.components(separatedBy: .newlines).compactMap { (linea: String) -> String? in
            var l = linea.trimmingCharacters(in: .whitespaces)
            while l.count > 1 && l.hasSuffix("/") { l.removeLast() }
            return l.hasPrefix("/") ? l : nil
        }
    }

    // MARK: Utilidades

    /// «/Users/ana/miniconda3» → «/users/ana/miniconda3/», como se busca en `Procesos.lineas`.
    static func condaFormas(_ rutas: Set<String>) -> Set<String> {
        Set(rutas.map { $0.lowercased() + "/" })
    }

    /// Los paquetes de conda se llaman «nombre-versión-build» (y sus comprimidos, igual con la extensión).
    static func condaEsNombreDePaquete(_ n: String) -> Bool {
        n.split(separator: "-").count >= 3
    }

    /// «/a/b/../c/./d» → «/a/c/d», sin mirar el disco.
    static func condaSinPuntos(_ ruta: String) -> String {
        var partes: [Substring] = []
        for parte in ruta.split(separator: "/") where parte != "." {
            if parte == ".." {
                _ = partes.popLast()
            } else {
                partes.append(parte)
            }
        }
        return "/" + partes.joined(separator: "/")
    }

    /// Lo que se ofrece: existe, no es un enlace, está dentro de tu carpeta y se puede mover a la Papelera.
    static func condaOfrecible(_ ruta: String, casa: String) -> Bool {
        guard ruta.hasPrefix(casa + "/"), let st = condaEstado(ruta), (st.st_mode & S_IFMT) != S_IFLNK else { return false }
        return sePuedeQuitar(URL(fileURLWithPath: ruta), admin: false)
    }

    /// Lo que dice `lstat` de una ruta (sin seguir enlaces), o `nil` si no existe o no se puede leer.
    static func condaEstado(_ ruta: String) -> stat? {
        var st = stat()
        return lstat(ruta, &st) == 0 ? st : nil
    }

    /// Una carpeta de verdad (no un enlace a una carpeta).
    static func condaEsCarpeta(_ ruta: String) -> Bool {
        guard let st = condaEstado(ruta) else { return false }
        return (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// Un archivo normal (no un enlace).
    static func condaEsArchivo(_ ruta: String) -> Bool {
        guard let st = condaEstado(ruta) else { return false }
        return (st.st_mode & S_IFMT) == S_IFREG
    }

    /// Lo que borra «conda clean»: se regenera solo, así que va como seguro y marcado.
    private static func condaLimpieza(_ nombre: String, _ detalle: String, _ consecuencia: String, _ rutas: [String],
                                      _ motivo: Motivo) -> Elemento {
        Elemento(nombre: nombre, detalle: detalle, consecuencia: consecuencia, rutas: rutas.map { URL(fileURLWithPath: $0) },
                 categoria: .desarrollo, riesgo: .seguro, seleccionado: true, motivos: [motivo],
                 enUso: .proceso(nombre: "conda", patron: "/bin/conda"), dueno: "conda")
    }
}
