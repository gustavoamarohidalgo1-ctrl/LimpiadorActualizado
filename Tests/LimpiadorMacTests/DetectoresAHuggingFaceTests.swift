import XCTest
@testable import LimpiadorMac

/// Hugging Face, swift-transformers y TensorFlow Datasets por partes, sobre una carpeta personal de prueba.
final class DetectoresAHuggingFaceTests: XCTestCase {
    private var casa: URL!

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("CasaHF-\(UUID().uuidString)")
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

    private func enlace(_ rel: String, a destino: String) throws {
        let url = casa.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destino)
    }

    /// Pone la fecha de modificación `dias` hacia atrás.
    private func envejecer(_ rel: String, dias: Double) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-dias * 86_400)],
                                              ofItemAtPath: ruta(rel))
    }

    /// Un repo con dos revisiones: «c1», a la que apunta main, y «c2», a la que no apunta ninguna rama.
    private func crearModelo(en raiz: String = ".cache/huggingface", repo: String = "models--org--m") throws {
        let r = "\(raiz)/hub/\(repo)"
        try crear("\(r)/blobs/a", String(repeating: "a", count: 2_000))
        try crear("\(r)/blobs/b", String(repeating: "b", count: 2_000))
        try crear("\(r)/refs/main", "c1")
        try enlace("\(r)/snapshots/c1/f", a: "../../blobs/a")
        try enlace("\(r)/snapshots/c2/f", a: "../../blobs/b")
    }

    private func elementos(abiertos: ArchivosAbiertos = ArchivosAbiertos(rutas: [], disponible: true),
                           entorno: [String: String] = [:], apps: AppsInstaladas = AppsInstaladas(),
                           accesoTotal: Bool = false) -> [Elemento] {
        Escaner.huggingFaceElementos(home: casa, entorno: entorno, apps: apps, accesoTotal: accesoTotal,
                                     abiertos: { abiertos }, ahora: Date())
    }

    private func rutas(_ els: [Elemento]) -> [String] { els.flatMap { $0.rutas.map(\.path) } }

    private func elemento(_ nombre: String, en els: [Elemento]) throws -> Elemento {
        try XCTUnwrap(els.first { $0.nombre == nombre }, "No está «\(nombre)»: \(els.map(\.nombre))")
    }

    /// Ninguna ruta es (ni contiene) el token, la configuración de accelerate o los candados; nunca la carpeta entera ni hub.
    private func comprobarQueNoToca(_ els: [Elemento], file: StaticString = #filePath, line: UInt = #line) {
        let protegidas = [".cache/huggingface/token", ".cache/huggingface/stored_tokens",
                          ".cache/huggingface/accelerate/default_config.yaml", ".cache/huggingface/hub/.locks"].map { ruta($0) }
        let nunca = Set([".cache/huggingface", ".cache/huggingface/hub", ".cache/huggingface/accelerate"].map { ruta($0) })
        for p in rutas(els) {
            XCTAssertFalse(nunca.contains(p), p, file: file, line: line)
            for t in protegidas {
                XCTAssertFalse(t == p || t.hasPrefix(p + "/"), "\(p) es o contiene \(t)", file: file, line: line)
            }
        }
    }

    // MARK: Hugging Face

    func testRevisionesAntiguasYModeloEntero() throws {
        try crear(".cache/huggingface/token", "hf_secreto")
        try crear(".cache/huggingface/stored_tokens", "[x]")
        try crear(".cache/huggingface/accelerate/default_config.yaml")
        try crear(".cache/huggingface/xet/x.bin")
        // Candados de una descarga que terminó hace un día.
        try crear(".cache/huggingface/hub/.locks/models--org--m/a.lock", "")
        try envejecer(".cache/huggingface/hub/.locks/models--org--m/a.lock", dias: 1)
        try envejecer(".cache/huggingface/hub/.locks/models--org--m", dias: 1)
        try crearModelo()
        let els = elementos()
        let repo = ruta(".cache/huggingface/hub/models--org--m")

        let revisiones = try elemento("Revisiones antiguas de modelos de Hugging Face", en: els)
        XCTAssertEqual(Set(revisiones.rutas.map(\.path)), [repo + "/snapshots/c2", repo + "/blobs/b"],
                       "Solo la revisión suelta y su blob: blobs/a es de la revisión actual")
        XCTAssertEqual(revisiones.riesgo, .seguro)
        XCTAssertTrue(revisiones.seleccionado)
        XCTAssertEqual(revisiones.categoria, .desarrollo)

        let modelo = try elemento("Modelo de IA: org/m", en: els)
        XCTAssertEqual(modelo.rutas.map(\.path), [repo])
        XCTAssertEqual(modelo.riesgo, .revisar)
        XCTAssertFalse(modelo.seleccionado)
        XCTAssertNotNil(modelo.ultimoUso)
        XCTAssertEqual(modelo.dueno, "Hugging Face")
        XCTAssertEqual(modelo.enUso, .proceso(nombre: "Hugging Face", patron: "huggingface"))

        let xet = try elemento("Caché de descargas de Hugging Face (Xet)", en: els)
        XCTAssertEqual(xet.rutas.map(\.path), [ruta(".cache/huggingface/xet")])
        XCTAssertTrue(xet.seleccionado)

        comprobarQueNoToca(els)
    }

    /// Si hay una descarga en marcha, o no se sabe qué tienen abierto los programas, no se ofrece nada de esa carpeta.
    func testDescargaEnCursoOSinSaberQueEstaAbierto() throws {
        try crearModelo()
        try crear(".cache/huggingface/xet/x.bin")
        XCTAssertFalse(elementos().isEmpty)

        XCTAssertTrue(elementos(abiertos: ArchivosAbiertos(rutas: [], disponible: false)).isEmpty)

        // Un «.incomplete» abierto: se está descargando algo.
        let bajando = ruta(".cache/huggingface/hub/models--org--m/blobs/zz.incomplete")
        XCTAssertTrue(elementos(abiertos: ArchivosAbiertos(rutas: [bajando], disponible: true)).isEmpty)

        // Un candado recién tocado: también.
        try crear(".cache/huggingface/hub/.locks/models--org--m/zz.lock", "")
        XCTAssertTrue(elementos().isEmpty)
    }

    /// Lo que un programa tiene abierto (un modelo cargado) no se ofrece.
    func testModeloAbiertoNoSeOfrece() throws {
        try crearModelo()
        let abierto = Seguridad.normalizada(ruta(".cache/huggingface/hub/models--org--m/blobs/b"))
        let els = elementos(abiertos: ArchivosAbiertos(rutas: [abierto], disponible: true))
        XCTAssertNil(els.first { $0.nombre.hasPrefix("Revisiones antiguas") })
        XCTAssertNil(els.first { $0.nombre == "Modelo de IA: org/m" })
    }

    func testDescargasAMedias() throws {
        try crearModelo()
        let blobs = ".cache/huggingface/hub/models--org--m/blobs"
        try crear("\(blobs)/vieja.incomplete")
        try envejecer("\(blobs)/vieja.incomplete", dias: 3)
        try crear("\(blobs)/reciente.incomplete")
        let medias = try elemento("Descargas a medias de Hugging Face", en: elementos())
        XCTAssertEqual(medias.rutas.map(\.path), [ruta("\(blobs)/vieja.incomplete")])
        XCTAssertEqual(medias.riesgo, .seguro)
        XCTAssertTrue(medias.seleccionado)
    }

    /// Un repo cuyo formato no se entiende no sale de ninguna forma (ni el almacén compartido hub/blobs).
    func testFormatosQueNoSeEntiendenNoSalen() throws {
        let hub = ".cache/huggingface/hub"
        try crearModelo()
        try crear("\(hub)/blobs/a")
        // blobs/ es un enlace.
        try crear("\(hub)/models--org--enlazado/refs/main", "c1")
        try enlace("\(hub)/models--org--enlazado/blobs", a: "../blobs")
        try enlace("\(hub)/models--org--enlazado/snapshots/c1/f", a: "../../blobs/a")
        // Un blob es un enlace al almacén compartido (y hay una descarga a medias vieja al lado).
        try crear("\(hub)/models--org--mixto/refs/main", "c1")
        try enlace("\(hub)/models--org--mixto/blobs/a", a: "../../blobs/a")
        try crear("\(hub)/models--org--mixto/blobs/x.incomplete")
        try envejecer("\(hub)/models--org--mixto/blobs/x.incomplete", dias: 3)
        try enlace("\(hub)/models--org--mixto/snapshots/c1/f", a: "../../blobs/a")
        // Un archivo de una revisión apunta a un blob que no existe.
        try crear("\(hub)/models--org--roto/refs/main", "c1")
        try crear("\(hub)/models--org--roto/blobs/a")
        try enlace("\(hub)/models--org--roto/snapshots/c1/f", a: "../../blobs/no-existe")
        // Sin refs/.
        try crear("\(hub)/models--org--sinrefs/blobs/a")
        try enlace("\(hub)/models--org--sinrefs/snapshots/c1/f", a: "../../blobs/a")

        let els = elementos()
        XCTAssertNotNil(els.first { $0.nombre == "Modelo de IA: org/m" }, "El repo normal sí sale")
        for p in rutas(els) {
            for repo in ["enlazado", "mixto", "roto", "sinrefs"] { XCTAssertFalse(p.contains("models--org--\(repo)"), p) }
            XCTAssertFalse(p == ruta("\(hub)/blobs") || p.hasPrefix(ruta("\(hub)/blobs") + "/"), p)
        }
    }

    /// Si alguna rama no es un commit, no se sabe qué revisiones sobran: no se ofrecen (el modelo entero sí).
    func testRamasQueNoSeEntiendenNoOfrecenRevisiones() throws {
        try crearModelo()
        try crear(".cache/huggingface/hub/models--org--m/refs/pr/1", "esto no es un commit")
        let els = elementos()
        XCTAssertNil(els.first { $0.nombre.hasPrefix("Revisiones antiguas") })
        XCTAssertNotNil(els.first { $0.nombre == "Modelo de IA: org/m" })
    }

    func testRamaQueNoSePuedeLeerNoOfreceRevisiones() throws {
        try XCTSkipIf(getuid() == 0, "root puede leerlo todo")
        try crearModelo()
        let rama = ruta(".cache/huggingface/hub/models--org--m/refs/main")
        XCTAssertEqual(chmod(rama, 0), 0)
        defer { _ = chmod(rama, 0o644) }
        XCTAssertNil(elementos().first { $0.nombre.hasPrefix("Revisiones antiguas") })
    }

    /// Si ninguna rama apunta a una revisión descargada, «revisiones antiguas» sería el modelo entero: no se ofrece así.
    func testSinRevisionActualNoHayRevisionesAntiguas() throws {
        try crearModelo()
        try crear(".cache/huggingface/hub/models--org--m/refs/main", "c9")
        XCTAssertNil(elementos().first { $0.nombre.hasPrefix("Revisiones antiguas") })
    }

    func testCodigoYConjuntosDeDatos() throws {
        let raiz = ".cache/huggingface"
        try crear("\(raiz)/token", "hf_secreto")
        try crear("\(raiz)/modules/transformers_modules/org/m/modelo.py")
        try crear("\(raiz)/assets/libreria/x.bin")
        try crear("\(raiz)/datasets/downloads/abc123")
        try crear("\(raiz)/datasets/glue/mrpc/1.0.0/hash/dataset_info.json", "{}")
        try crear("\(raiz)/datasets/csv/default-1/0.0.0/hash/dataset_info.json", "{}")
        try crear("\(raiz)/datasets/a_medias/datos.arrow")
        try crear("\(raiz)/datasets/.oculta/datos.arrow")
        let els = elementos()
        XCTAssertTrue(try elemento("Código descargado de modelos de Hugging Face", en: els).seleccionado)
        XCTAssertFalse(try elemento("Archivos auxiliares de librerías de Hugging Face", en: els).seleccionado)
        let descargas = try elemento("Descargas originales de conjuntos de datos", en: els)
        XCTAssertEqual(descargas.rutas.map(\.path), [ruta("\(raiz)/datasets/downloads")])
        XCTAssertFalse(descargas.seleccionado)
        XCTAssertEqual(try elemento("Conjunto de datos preparado: glue", en: els).riesgo, .revisar)
        // Hecho a partir de archivos que pueden ser tuyos (CSV): puede ser la única copia.
        XCTAssertEqual(try elemento("Conjunto de datos preparado: csv", en: els).riesgo, .cuidado)
        XCTAssertFalse(rutas(els).contains { $0.hasSuffix("/a_medias") || $0.contains("/.oculta") })
        comprobarQueNoToca(els)
    }

    func testOtrasCarpetasDeHuggingFace() throws {
        // La que comparten las apps de Pinokio.
        try crearModelo(en: "pinokio/cache/HF_HOME")
        let pinokio = try elemento("Modelo de IA: org/m (Pinokio)", en: elementos())
        XCTAssertEqual(pinokio.dueno, "Pinokio")
        XCTAssertEqual(pinokio.enUso, .app(nombre: "Pinokio", claves: ["computer.pinokio", "Pinokio"]))

        // HF_HOME dentro de tu carpeta (también escrito con «~»).
        try crearModelo(en: "ia/hf")
        let modelo = ruta("ia/hf/hub/models--org--m")
        XCTAssertTrue(rutas(elementos(entorno: ["HF_HOME": ruta("ia/hf")])).contains(modelo))
        XCTAssertTrue(rutas(elementos(entorno: ["HF_HOME": "~/ia/hf"])).contains(modelo))
        XCTAssertFalse(rutas(elementos()).contains(modelo))

        // Ni fuera de tu carpeta ni en carpetas genéricas como Documentos.
        XCTAssertEqual(Escaner.huggingFaceRaices(home: casa, entorno: ["HF_HOME": "/tmp"]).count, 1)
        try crear("Documents/modules/mio.py")
        XCTAssertFalse(rutas(elementos(entorno: ["HF_HOME": ruta("Documents")])).contains(ruta("Documents/modules")))

        // La misma carpeta dos veces cuenta una.
        try crearModelo()
        XCTAssertEqual(Escaner.huggingFaceRaices(home: casa, entorno: ["HF_HOME": ruta(".cache/huggingface")]).count, 2)
    }

    func testRutasYNombres() {
        XCTAssertEqual(Escaner.huggingFaceSinPuntos("../../blobs/a", desde: "/r/hub/m/snapshots/c1"), "/r/hub/m/blobs/a")
        XCTAssertEqual(Escaner.huggingFaceSinPuntos("/a/./b/../c"), "/a/c")
        XCTAssertEqual(Escaner.huggingFaceNombreRepo("datasets--org--d").nombre, "org/d")
        XCTAssertEqual(Escaner.huggingFaceNombreRepo("datasets--org--d").tipo, "Conjunto de datos")
        XCTAssertEqual(Escaner.huggingFaceNombreRepo("models--gpt2").nombre, "gpt2")
    }

    // MARK: swift-transformers

    func testModelosDeAppsSoloConLaMarca() throws {
        let m = "Documents/huggingface/models"
        try crear("\(m)/org/descargado/config.json", "{}")
        try crear("\(m)/org/descargado/onnx/modelo.onnx")
        try crear("\(m)/org/descargado/.cache/huggingface/download/config.json.metadata", "c1")
        try crear("\(m)/org/descargado/.cache/huggingface/download/onnx/modelo.onnx.metadata", "c1")
        // Sin la marca de la descarga: podría ser tuya.
        try crear("\(m)/org/sin-marca/config.json", "{}")
        // Con un archivo que no vino de la descarga.
        try crear("\(m)/org/con-algo-tuyo/config.json", "{}")
        try crear("\(m)/org/con-algo-tuyo/.cache/huggingface/download/config.json.metadata", "c1")
        try crear("\(m)/org/con-algo-tuyo/mis-pesos.safetensors")
        // Un repo sin organización.
        try crear("\(m)/gpt2/config.json", "{}")
        try crear("\(m)/gpt2/.cache/huggingface/download/config.json.metadata", "c1")

        let els = elementos()
        let descargado = try elemento("Modelo descargado por una app: org/descargado", en: els)
        XCTAssertEqual(descargado.rutas.map(\.path), [ruta("\(m)/org/descargado")])
        XCTAssertEqual(descargado.riesgo, .revisar)
        XCTAssertFalse(descargado.seleccionado)
        XCTAssertNotNil(els.first { $0.nombre == "Modelo descargado por una app: gpt2" })
        XCTAssertFalse(rutas(els).contains { $0.contains("sin-marca") || $0.contains("con-algo-tuyo") })
        // Si no se sabe qué tienen abierto los programas, no se ofrece.
        XCTAssertTrue(elementos(abiertos: ArchivosAbiertos(rutas: [], disponible: false)).isEmpty)
    }

    func testModeloDeAppEnSuContenedor() throws {
        let repo = "Library/Containers/com.ejemplo.app/Data/Documents/huggingface/models/org/repo"
        try crear("\(repo)/modelo.bin")
        try crear("\(repo)/.cache/huggingface/download/modelo.bin.metadata", "c1")
        var apps = AppsInstaladas()
        apps.agregarBundleID("com.ejemplo.app", nombre: "Ejemplo")
        let nombre = "Modelo descargado por una app: org/repo"
        // Sin Acceso total al disco no se mira dentro de los contenedores.
        XCTAssertNil(elementos(apps: apps).first { $0.nombre == nombre })
        let el = try elemento(nombre, en: elementos(apps: apps, accesoTotal: true))
        XCTAssertEqual(el.rutas.map(\.path), [ruta(repo)])
        XCTAssertEqual(el.enUso, .app(nombre: "Ejemplo", claves: ["com.ejemplo.app"]))
        // Si la app ya no está, todo su contenedor sale en «Restos de apps borradas».
        XCTAssertNil(elementos(accesoTotal: true).first { $0.nombre == nombre })
    }

    // MARK: TensorFlow Datasets

    func testTensorFlowDatasets() throws {
        let t = "tensorflow_datasets"
        try crear("\(t)/mnist/3.0.1/dataset_info.json", "{}")
        try crear("\(t)/downloads/mnist-archivo.gz")
        try crear("\(t)/downloads/mnist-archivo.gz.INFO", #"{"dataset_names": ["mnist"], "urls": ["https://ejemplo"]}"#)
        // Su conjunto no está preparado (solo hay una preparación a medias): no sale.
        try crear("\(t)/downloads/cifar.zip")
        try crear("\(t)/downloads/cifar.zip.INFO", #"{"dataset_names": ["cifar10"]}"#)
        try crear("\(t)/cifar10/3.0.2.incomplete7a8b/dataset_info.json", "{}")
        // Un .INFO que no se entiende: no sale.
        try crear("\(t)/downloads/raro.bin")
        try crear("\(t)/downloads/raro.bin.INFO", "esto no es JSON")
        // Lo que pusiste tú a mano y lo que se está descargando, nunca.
        try crear("\(t)/downloads/manual/imagenet.tar")
        try crear("\(t)/downloads/manual.INFO", #"{"dataset_names": ["mnist"]}"#)
        try crear("\(t)/downloads/bajando.tmp.1234/parte")

        let els = elementos()
        let descargas = try elemento("Descargas de TensorFlow Datasets ya preparadas", en: els)
        XCTAssertEqual(Set(descargas.rutas.map(\.path)),
                       [ruta("\(t)/downloads/mnist-archivo.gz"), ruta("\(t)/downloads/mnist-archivo.gz.INFO")])
        XCTAssertFalse(descargas.seleccionado)
        XCTAssertEqual(try elemento("Conjunto de TensorFlow Datasets: mnist", en: els).riesgo, .revisar)
        XCTAssertFalse(rutas(els).contains {
            $0.contains("cifar") || $0.contains("raro") || $0.contains("/manual") || $0.contains(".tmp")
        })
    }
}
