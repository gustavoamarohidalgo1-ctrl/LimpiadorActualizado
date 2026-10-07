import XCTest
@testable import LimpiadorMac

/// conda y mamba: qué se ofrece de sus carpetas de paquetes y de sus entornos, qué se conserva siempre y que, si algo
/// no se puede leer, no se ofrece nada.
final class DetectoresACondaTests: XCTestCase {
    private var casa: URL!

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("Conda-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: casa)
    }

    // MARK: Ayudas

    private func ruta(_ rel: String) -> String { casa.appendingPathComponent(rel).path }

    private func crear(_ rel: String, _ texto: String = "x") throws {
        let url = casa.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texto.utf8).write(to: url)
    }

    /// Una instalación con un entorno «e1»: un comprimido, el índice de paquetes, libA (que no usa nadie) y libB (que
    /// e1 usa sin enlaces duros, como cuando conda enlaza con enlaces simbólicos). `base`: la instalación es también un
    /// entorno (conda, Miniforge…); la de micromamba no lo es.
    private func instalacion(_ raiz: String, base: Bool = true) throws {
        if base { try crear("\(raiz)/conda-meta/history", "==> 2024-01-01 10:00:00 <==\n") }
        try crear("\(raiz)/pkgs/urls.txt", "")
        try crear("\(raiz)/pkgs/x-1.0-0.tar.bz2")
        try crear("\(raiz)/pkgs/cache/a.json", "{}")
        try crear("\(raiz)/pkgs/libA-1.0-0/info/index.json", "{}")
        try crear("\(raiz)/pkgs/libA-1.0-0/lib/a.dylib")
        // Un enlace que se queda dentro del propio paquete no molesta.
        try FileManager.default.createSymbolicLink(atPath: ruta("\(raiz)/pkgs/libA-1.0-0/lib/a.1.dylib"),
                                                   withDestinationPath: "a.dylib")
        try crear("\(raiz)/pkgs/libB-1.0-0/info/index.json", "{}")
        try crear("\(raiz)/envs/e1/conda-meta/history", "==> 2024-01-01 10:00:00 <==\n")
        let registro = try JSONSerialization.data(withJSONObject: ["extracted_package_dir": ruta("\(raiz)/pkgs/libB-1.0-0")])
        try crear("\(raiz)/envs/e1/conda-meta/libB-1.0-0.json", String(decoding: registro, as: UTF8.self))
    }

    private func contexto(_ lineas: [String]) -> Contexto {
        let indice = Indice.construir(accesoTotal: false, home: casa.path, extras: [], progreso: { _ in })
        return Contexto(indice: indice, apps: AppsInstaladas(), procesos: Procesos(lineas: lineas), accesoTotal: false)
    }

    /// Una lista de procesos en la que no hay nada de conda.
    private let sinConda = ["/sbin/launchd", "/applications/limpiadormac.app/contents/macos/limpiadormac"]

    /// El detector sobre la carpeta de prueba, con `lineas` como lista de procesos (por defecto, sin nada de conda)
    /// y como si `conda()` ya no existiera.
    private func elementos(_ lineas: [String]? = nil, comprimidosYaOfrecidos: [String] = []) -> [Elemento] {
        Escaner.condaElementos(contexto(lineas ?? sinConda), home: casa, comprimidosYaOfrecidos: comprimidosYaOfrecidos)
    }

    /// Las rutas ofrecidas, relativas a la carpeta de prueba.
    private func ofrecidas(_ els: [Elemento]) -> Set<String> {
        let base = Seguridad.normalizada(casa.path) + "/"
        return Set(els.flatMap { $0.rutas }.map { (u: URL) -> String in
            let p = Seguridad.normalizada(u.path)
            return p.hasPrefix(base) ? String(p.dropFirst(base.count)) : p
        })
    }

    /// Pone la fecha de modificación de una carpeta y de todo lo que tiene dentro `dias` atrás.
    private func envejecer(_ rel: String, dias: Double) throws {
        let fecha = Date().addingTimeInterval(-dias * 86400)
        let raiz = ruta(rel)
        for sub in FileManager.default.subpaths(atPath: raiz) ?? [] {
            try FileManager.default.setAttributes([.modificationDate: fecha], ofItemAtPath: raiz + "/" + sub)
        }
        try FileManager.default.setAttributes([.modificationDate: fecha], ofItemAtPath: raiz)
    }

    // MARK: Lo que se ofrece

    func testComoCondaClean() throws {
        try instalacion("micromamba", base: false)
        let els = elementos()
        let r = ofrecidas(els)
        XCTAssertTrue(r.contains("micromamba/pkgs/x-1.0-0.tar.bz2"), "\(r)")
        XCTAssertTrue(r.contains("micromamba/pkgs/cache"), "\(r)")
        XCTAssertTrue(r.contains("micromamba/pkgs/libA-1.0-0"), "\(r)")
        // libB lo usa e1 (lo dice su registro). La instalación, sus entornos y los archivos de conda se conservan siempre.
        for nunca in ["micromamba/pkgs/libB-1.0-0", "micromamba", "micromamba/pkgs", "micromamba/pkgs/urls.txt",
                      "micromamba/envs", "micromamba/envs/e1", "micromamba/envs/e1/conda-meta"] {
            XCTAssertFalse(r.contains(nunca), nunca)
        }
        for el in els {
            XCTAssertEqual(el.categoria, .desarrollo)
            XCTAssertEqual(el.dueno, "conda")
            XCTAssertEqual(el.accion, .borrar)
            XCTAssertEqual(el.riesgo, .seguro)
            XCTAssertTrue(el.seleccionado)
            XCTAssertEqual(el.enUso, .proceso(nombre: "conda", patron: "/bin/conda"))
        }
        // Todo lo ofrecido existe, no es un enlace y está dentro de la carpeta personal.
        let base = Seguridad.normalizada(casa.path) + "/"
        for u in els.flatMap({ $0.rutas }) {
            var st = stat()
            let existe = lstat(u.path, &st) == 0
            XCTAssertTrue(existe, u.path)
            XCTAssertNotEqual(st.st_mode & S_IFMT, S_IFLNK, u.path)
            XCTAssertTrue(u.path.hasPrefix(base), u.path)
        }
    }

    func testUnEnlaceDuroProtegeElPaquete() throws {
        try instalacion("micromamba", base: false)
        // e1 tiene instalado un archivo de libA con un enlace duro, como hace conda: libA está en uso.
        try FileManager.default.createDirectory(atPath: ruta("micromamba/envs/e1/lib"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(atPath: ruta("micromamba/pkgs/libA-1.0-0/lib/a.dylib"),
                                         toPath: ruta("micromamba/envs/e1/lib/a.dylib"))
        let r = ofrecidas(elementos())
        XCTAssertFalse(r.contains("micromamba/pkgs/libA-1.0-0"))
        XCTAssertTrue(r.contains("micromamba/pkgs/x-1.0-0.tar.bz2"))
    }

    func testEnlacesSimbolicosQueSalenDelPaquete() throws {
        try instalacion("micromamba", base: false)
        try crear("Documents/notas.txt")
        try FileManager.default.createSymbolicLink(atPath: ruta("micromamba/pkgs/libA-1.0-0/lib/docs"),
                                                   withDestinationPath: "../../../../Documents")
        try FileManager.default.createSymbolicLink(atPath: ruta("micromamba/pkgs/y-1.0-0.conda"),
                                                   withDestinationPath: ruta("Documents/notas.txt"))
        let r = ofrecidas(elementos())
        XCTAssertFalse(r.contains("micromamba/pkgs/libA-1.0-0"))
        XCTAssertFalse(r.contains("micromamba/pkgs/y-1.0-0.conda"))
        XCTAssertFalse(r.contains { $0.hasPrefix("Documents") })
        XCTAssertTrue(r.contains("micromamba/pkgs/x-1.0-0.tar.bz2"))
    }

    func testEntornoSinCambiosHaceMeses() throws {
        try instalacion("miniconda3")
        XCTAssertFalse(ofrecidas(elementos()).contains("miniconda3/envs/e1"), "Recién usado: no se ofrece")

        try envejecer("miniconda3/envs/e1", dias: 200)
        try envejecer("miniconda3/conda-meta", dias: 400)
        let els = elementos()
        let e1 = try XCTUnwrap(els.first { ofrecidas([$0]) == ["miniconda3/envs/e1"] })
        XCTAssertEqual(e1.nombre, "Entorno de conda «e1» sin usar")
        XCTAssertEqual(e1.riesgo, .revisar)
        XCTAssertFalse(e1.seleccionado)
        XCTAssertNotNil(e1.ultimoUso)
        let prefijo = Seguridad.normalizada(ruta("miniconda3/envs/e1")).lowercased() + "/"
        XCTAssertEqual(e1.enUso, .proceso(nombre: "Entorno e1", patron: prefijo))
        // La instalación base nunca, aunque tampoco haya cambiado.
        XCTAssertFalse(ofrecidas(els).contains("miniconda3"))

        // Con un programa del entorno en marcha: ni el entorno ni los paquetes descomprimidos; los comprimidos, sí.
        let r = ofrecidas(elementos(sinConda + [prefijo + "bin/python -m ipykernel_launcher"]))
        XCTAssertFalse(r.contains("miniconda3/envs/e1"))
        XCTAssertFalse(r.contains("miniconda3/pkgs/libA-1.0-0"))
        XCTAssertTrue(r.contains("miniconda3/pkgs/x-1.0-0.tar.bz2"))
    }

    func testEntornosDeAppsNoSeOfrecen() throws {
        // Spyder usa su entorno aunque no cambie: nunca se ofrece. Sus descargas, sí.
        try instalacion("Library/spyder-6")
        try envejecer("Library/spyder-6/envs/e1", dias: 400)
        let r = ofrecidas(elementos())
        XCTAssertFalse(r.contains("Library/spyder-6/envs/e1"))
        XCTAssertTrue(r.contains("Library/spyder-6/pkgs/cache"))
        XCTAssertTrue(r.contains("Library/spyder-6/pkgs/libA-1.0-0"))
    }

    func testInstalacionesDeEnvironmentsTxtYCarpetasDeCondarc() throws {
        try instalacion("herramientas/conda")
        try crear(".conda/environments.txt", ruta("herramientas/conda/envs/e1") + "\n")
        try crear("conda_pkgs/urls.txt", "")
        try crear("conda_pkgs/z-2.0-0.conda")
        try crear(".condarc", "channels:\n  - conda-forge\npkgs_dirs:\n  - ~/conda_pkgs\n")
        let r = ofrecidas(elementos())
        XCTAssertTrue(r.contains("herramientas/conda/pkgs/x-1.0-0.tar.bz2"), "\(r)")
        XCTAssertTrue(r.contains("herramientas/conda/pkgs/libA-1.0-0"), "\(r)")
        XCTAssertTrue(r.contains("conda_pkgs/z-2.0-0.conda"), "\(r)")
        XCTAssertFalse(r.contains("herramientas/conda/pkgs/libB-1.0-0"))
    }

    /// Lo que ya ofrecen `conda()` (los comprimidos) y las reglas del catálogo (el índice de algunas instalaciones)
    /// no se repite.
    func testNoRepiteLoQueYaSeOfrece() throws {
        try instalacion("miniconda3")
        let els = Escaner.condaElementos(contexto(sinConda), home: casa)
        let r = ofrecidas(els)
        if Escaner.condaComprimidosDeEscaner.contains("miniconda3/pkgs") {
            XCTAssertFalse(r.contains("miniconda3/pkgs/x-1.0-0.tar.bz2"))
        }
        let cubiertas = Escaner.condaCubiertasPorCatalogo(home: casa)
        for u in els.flatMap({ $0.rutas }) {
            let p = Seguridad.normalizada(u.path)
            XCTAssertFalse(cubiertas.contains(p) || Rutas.estaDentro(p, de: cubiertas), p)
        }
        let indice = Seguridad.normalizada(ruta("miniconda3/pkgs/cache"))
        XCTAssertEqual(r.contains("miniconda3/pkgs/cache"), !cubiertas.contains(indice))
        // Lo que no ofrece nadie más, sí.
        XCTAssertTrue(r.contains("miniconda3/pkgs/libA-1.0-0"))
    }

    // MARK: Lo que se conserva siempre

    func testSinUrlsTxtNoEsUnaInstalacionDeConda() throws {
        try instalacion("miniconda3")
        try envejecer("miniconda3/envs/e1", dias: 200)
        try FileManager.default.removeItem(atPath: ruta("miniconda3/pkgs/urls.txt"))
        XCTAssertTrue(elementos().isEmpty)
    }

    func testTuCarpetaNuncaEsUnaCarpetaDePaquetes() throws {
        // Un .condarc que apunta a tu carpeta o a Documents: aunque tengan «urls.txt», no se toca nada de ahí.
        try crear(".condarc", "pkgs_dirs: [~, ~/Documents]\n")
        try crear("urls.txt", "")
        try crear("copia-de-fotos-2024.tar.bz2")
        try crear("cache/a.json", "{}")
        try crear("Documents/urls.txt", "")
        try crear("Documents/informe-final-v2.conda")
        try crear("Documents/mi-proyecto-1/info/index.json", "{}")
        XCTAssertTrue(elementos().isEmpty)
    }

    // MARK: Si algo no se puede leer, nada

    func testNadaMientrasCondaOMambaTrabajan() throws {
        try instalacion("micromamba", base: false)
        XCTAssertFalse(elementos().isEmpty)
        for linea in ["/users/ana/miniconda3/bin/python /users/ana/miniconda3/bin/conda install numpy",
                      "/users/ana/miniforge3/bin/mamba update --all", "/opt/homebrew/bin/micromamba create -n x",
                      "/users/ana/miniconda3/bin/python -m conda-libmamba-solver"] {
            XCTAssertTrue(elementos(sinConda + [linea]).isEmpty, linea)
        }
        // Sin la lista de procesos no se sabe si conda está trabajando.
        XCTAssertTrue(elementos([]).isEmpty)
    }

    func testEnvironmentsTxtIlegible() throws {
        try instalacion("micromamba", base: false)
        // Existe pero no se puede leer como texto: no se sabe qué entornos hay.
        try FileManager.default.createDirectory(atPath: ruta(".conda/environments.txt"), withIntermediateDirectories: true)
        XCTAssertTrue(elementos().isEmpty)
    }

    func testCondarcIlegible() throws {
        try instalacion("micromamba", base: false)
        try FileManager.default.createDirectory(atPath: ruta(".condarc"), withIntermediateDirectories: true)
        XCTAssertTrue(elementos().isEmpty)
    }

    func testRegistroDePaqueteIlegible() throws {
        try instalacion("micromamba", base: false)
        try crear("micromamba/envs/e1/conda-meta/roto-1.0-0.json", "{ esto no es JSON")
        let r = ofrecidas(elementos())
        // Sin saber qué usa e1, ningún paquete descomprimido; lo demás, sí.
        XCTAssertFalse(r.contains("micromamba/pkgs/libA-1.0-0"))
        XCTAssertTrue(r.contains("micromamba/pkgs/x-1.0-0.tar.bz2"))
        XCTAssertTrue(r.contains("micromamba/pkgs/cache"))
    }

    func testPaqueteQueNoSePuedeRecorrer() throws {
        try XCTSkipIf(getuid() == 0, "Con root se puede leer todo")
        try instalacion("micromamba", base: false)
        let bloqueada = ruta("micromamba/pkgs/libA-1.0-0/lib")
        XCTAssertEqual(chmod(bloqueada, 0), 0)
        defer { chmod(bloqueada, 0o755) }
        XCTAssertFalse(ofrecidas(elementos()).contains("micromamba/pkgs/libA-1.0-0"))
    }

    func testPaquetesQueUsaUnEntorno() throws {
        let p = ruta("entorno")
        try crear("entorno/conda-meta/history", "")
        try crear("entorno/conda-meta/a-1.0-0.json", #"{"link": {"source": "/x/pkgs/a-1.0-0", "type": 2}}"#)
        try crear("entorno/conda-meta/b-2.0-h1_0.json", #"{"name": "b", "version": "2.0", "build": "h1_0", "fn": "b-2.0-h1_0.conda"}"#)
        XCTAssertEqual(Escaner.condaPaquetesUsados([p]), ["a-1.0-0", "b-2.0-h1_0"])
        // Un registro que no dice qué paquete es: no se sabe qué se usa.
        try crear("entorno/conda-meta/c.json", #"{"otra": "cosa"}"#)
        XCTAssertNil(Escaner.condaPaquetesUsados([p]))
    }

    // MARK: Configuración

    func testPkgsDirsDeCondarc() {
        let texto = """
        channels:
          - conda-forge
        pkgs_dirs:   # cachés de paquetes
          - ~/conda_pkgs
          - "$HOME/otra pkgs"

          - '${HOME}/tercera'
          - /Volumes/Disco/pkgs
          - relativa/pkgs
        envs_dirs:
          - ~/envs
        """
        XCTAssertEqual(Escaner.condaPkgsDirs(texto, home: "/Users/ana"),
                       ["/Users/ana/conda_pkgs", "/Users/ana/otra pkgs", "/Users/ana/tercera", "/Volumes/Disco/pkgs"])
        XCTAssertEqual(Escaner.condaPkgsDirs("pkgs_dirs: [~/a, \"/b\"]", home: "/Users/ana"), ["/Users/ana/a", "/b"])
        XCTAssertEqual(Escaner.condaPkgsDirs("channels: [defaults]", home: "/Users/ana"), [])
    }

    func testLineasDeEnvironmentsTxt() {
        XCTAssertEqual(Escaner.condaLineasDeEntornos("/Users/ana/miniconda3\n/Users/ana/miniconda3/envs/x/\r\n\nbasura\n"),
                       ["/Users/ana/miniconda3", "/Users/ana/miniconda3/envs/x"])
    }
}
