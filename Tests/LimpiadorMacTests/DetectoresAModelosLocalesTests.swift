import XCTest
@testable import LimpiadorMac

/// Modelos locales de IA por partes (Ollama, Msty, LM Studio, GPT4All y modelos dentro de apps) sobre una carpeta
/// personal de prueba: qué se ofrece, qué se conserva siempre y que, si algo no se entiende, no se ofrece nada.
final class DetectoresAModelosLocalesTests: XCTestCase {
    private var casa: URL!
    private let modelos = ".ollama/models/"
    private let hexA = String(repeating: "a", count: 64)
    private let hexB = String(repeating: "b", count: 64)
    private let hexC = String(repeating: "c", count: 64)

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("ModelosLocales-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: casa)
    }

    /// Crea un archivo (y sus carpetas) dentro de la carpeta de prueba, modificado hace `haceHoras` horas.
    @discardableResult
    private func crear(_ rel: String, _ texto: String = "x", haceHoras: Double = 0) throws -> URL {
        let url = casa.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texto.utf8).write(to: url)
        if haceHoras > 0 {
            let fecha = Date().addingTimeInterval(-haceHoras * 3600)
            try FileManager.default.setAttributes([.modificationDate: fecha], ofItemAtPath: url.path)
        }
        return url
    }

    private func contexto(apps: AppsInstaladas = AppsInstaladas(), lineas: [String] = ["/sbin/launchd"]) -> Contexto {
        var procesos = Procesos()
        procesos.lineas = lineas
        return Contexto(indice: Indice(), apps: apps, procesos: procesos, accesoTotal: false)
    }

    private func instaladas(_ datos: DatosApp) -> AppsInstaladas {
        var apps = AppsInstaladas()
        apps.agregar(datos, enAplicaciones: true)
        return apps
    }

    /// Un manifiesto de Ollama: la configuración es el primer trozo y las capas, todos.
    private func manifiesto(_ trozos: [String]) -> String {
        let capas = trozos.map { "{\"mediaType\":\"application/vnd.ollama.image.model\",\"digest\":\"sha256:\($0)\",\"size\":1}" }
        return "{\"schemaVersion\":2,\"config\":{\"digest\":\"sha256:\(trozos[0])\",\"size\":1},\"layers\":[\(capas.joined(separator: ","))]}"
    }

    // MARK: Ollama

    func testOllamaPorPartes() throws {
        let m = try crear(modelos + "manifests/registry.ollama.ai/library/m/latest", manifiesto([hexA]))
        try crear(modelos + "manifests/.DS_Store")
        let a = try crear(modelos + "blobs/sha256-\(hexA)", haceHoras: 2)
        let b = try crear(modelos + "blobs/sha256-\(hexB)", haceHoras: 2)
        let parcial = try crear(modelos + "blobs/sha256-\(hexC)-partial", haceHoras: 2)
        // Un enlace con nombre de trozo nunca se ofrece.
        try FileManager.default.createSymbolicLink(
            at: casa.appendingPathComponent(modelos + "blobs/sha256-" + String(repeating: "d", count: 64)), withDestinationURL: b)

        let r = Escaner.modelosLocalesTodos(contexto(), home: casa)
        XCTAssertEqual(r.count, 3)

        let parciales = try XCTUnwrap(r.first { $0.nombre == "Descargas a medias de Ollama" })
        XCTAssertEqual(parciales.rutas.map(\.path), [parcial.path])
        XCTAssertEqual(parciales.riesgo, .seguro)
        XCTAssertTrue(parciales.seleccionado)

        let restos = try XCTUnwrap(r.first { $0.nombre == "Restos de modelos borrados de Ollama" })
        XCTAssertEqual(restos.rutas.map(\.path), [b.path])
        XCTAssertEqual(restos.riesgo, .seguro)
        XCTAssertTrue(restos.seleccionado)

        let modelo = try XCTUnwrap(r.first { $0.nombre == "Modelo de Ollama: m:latest" })
        XCTAssertEqual(modelo.rutas.map(\.path), [m.path, a.path])
        XCTAssertEqual(modelo.riesgo, .revisar)
        XCTAssertFalse(modelo.seleccionado)
        XCTAssertEqual(modelo.enUso, EnUso.proceso(nombre: "Ollama", patron: "ollama"))
        XCTAssertTrue(modelo.consecuencia.contains("ollama pull m:latest"))

        let raiz = casa.appendingPathComponent(".ollama/models").path
        for el in r {
            XCTAssertEqual(el.categoria, .desarrollo)
            XCTAssertEqual(el.accion, .borrar)
            // Con la lista de modelos legible, nunca la carpeta entera.
            XCTAssertFalse(el.rutas.contains { $0.path == raiz })
        }
    }

    /// Un modelo creado con «ollama create» (otro registro) puede ser la única copia: ni él ni sus trozos se ofrecen.
    func testModeloCreadoAManoNoSeOfreceNiSusTrozos() throws {
        try crear(modelos + "manifests/registry.ollama.ai/library/m/latest", manifiesto([hexA]))
        let local = try crear(modelos + "manifests/local/x/y/z", manifiesto([hexB]))
        try crear(modelos + "blobs/sha256-\(hexA)", haceHoras: 2)
        let b = try crear(modelos + "blobs/sha256-\(hexB)", haceHoras: 2)

        let r = Escaner.modelosLocalesTodos(contexto(), home: casa)
        XCTAssertEqual(r.map(\.nombre), ["Modelo de Ollama: m:latest"])
        let rutas = Set(r.flatMap { $0.rutas.map(\.path) })
        XCTAssertFalse(rutas.contains(b.path))
        XCTAssertFalse(rutas.contains(local.path))
    }

    func testNombresYTrozosCompartidos() throws {
        XCTAssertEqual(Escaner.modelosLocalesNombreOllama(["registry.ollama.ai", "library", "llama3", "8b"]), "llama3:8b")
        XCTAssertEqual(Escaner.modelosLocalesNombreOllama(["registry.ollama.ai", "ana", "mio", "latest"]), "ana/mio:latest")
        XCTAssertEqual(Escaner.modelosLocalesNombreOllama(["hf.co", "bartowski", "Qwen-GGUF", "Q4_K_M"]), "hf.co/bartowski/Qwen-GGUF:Q4_K_M")
        XCTAssertNil(Escaner.modelosLocalesNombreOllama(["mi-registro.local", "a", "b", "c"]))
        XCTAssertNil(Escaner.modelosLocalesNombreOllama(["registry.ollama.ai", "library", "m"]))

        // Dos etiquetas del mismo modelo comparten los pesos: cada una se lleva solo lo suyo.
        try crear(modelos + "manifests/registry.ollama.ai/library/m/latest", manifiesto([hexA, hexB]))
        try crear(modelos + "manifests/registry.ollama.ai/library/m/8b", manifiesto([hexA, hexC]))
        for hex in [hexA, hexB, hexC] { try crear(modelos + "blobs/sha256-\(hex)", haceHoras: 2) }
        let r = Escaner.modelosLocalesTodos(contexto(), home: casa)
        XCTAssertEqual(r.first { $0.nombre == "Modelo de Ollama: m:latest" }?.rutas.map(\.lastPathComponent),
                       ["latest", "sha256-\(hexB)"])
        XCTAssertEqual(r.first { $0.nombre == "Modelo de Ollama: m:8b" }?.rutas.map(\.lastPathComponent), ["8b", "sha256-\(hexC)"])
        XCTAssertFalse(r.flatMap(\.rutas).contains { $0.lastPathComponent == "sha256-\(hexA)" })
    }

    /// Si algún manifiesto no se entiende, no se sabe qué trozos usa cada modelo: solo las descargas a medias
    /// y la carpeta entera para revisar, con aviso.
    func testListaIlegible() throws {
        try crear(modelos + "manifests/registry.ollama.ai/library/m/latest", manifiesto([hexA]))
        try crear(modelos + "manifests/registry.ollama.ai/library/roto/latest", "{no es json")
        try crear(modelos + "blobs/sha256-\(hexA)", haceHoras: 2)
        try crear(modelos + "blobs/sha256-\(hexB)", haceHoras: 2)
        let parcial = try crear(modelos + "blobs/sha256-\(hexC)-partial-0", haceHoras: 2)

        let r = Escaner.modelosLocalesTodos(contexto(), home: casa)
        XCTAssertEqual(Set(r.map(\.nombre)), ["Descargas a medias de Ollama", "Modelos de Ollama"])
        XCTAssertEqual(r.first { $0.nombre == "Descargas a medias de Ollama" }?.rutas.map(\.path), [parcial.path])
        let entera = try XCTUnwrap(r.first { $0.nombre == "Modelos de Ollama" })
        XCTAssertEqual(entera.rutas.map(\.path), [casa.appendingPathComponent(".ollama/models").path])
        XCTAssertEqual(entera.riesgo, .revisar)
        XCTAssertFalse(entera.seleccionado)
        XCTAssertTrue(entera.motivos.contains { $0.nivel == .aviso && $0.etiqueta == "Lista ilegible" })
    }

    func testManifiestosQueNoSeEntienden() throws {
        let raros = ["", "[]", "{\"layers\":[]}", "{\"config\":{\"digest\":\"sha256:\(hexA)\"}}",
                     "{\"config\":{\"digest\":\"sha256:\(hexA)\"},\"layers\":[{\"digest\":\"md5:1234\"}]}",
                     "{\"config\":{\"digest\":\"sha256:\(hexA.uppercased())\"},\"layers\":[]}"]
        for (i, texto) in raros.enumerated() {
            try crear("caso\(i)/" + modelos + "manifests/registry.ollama.ai/library/m/latest", texto)
            try crear("caso\(i)/" + modelos + "blobs/sha256-\(hexB)", haceHoras: 2)
            let r = Escaner.modelosLocalesTodos(contexto(), home: casa.appendingPathComponent("caso\(i)"))
            XCTAssertEqual(r.map(\.nombre), ["Modelos de Ollama"], texto)
        }
    }

    /// Un enlace o una carpeta oculta entre los manifiestos: tampoco se sabe qué son.
    func testEnlacesYCarpetasOcultasEntreLosManifiestos() throws {
        for (i, raro) in ["enlace", ".oculta"].enumerated() {
            let m = try crear("caso\(i)/" + modelos + "manifests/registry.ollama.ai/library/m/latest", manifiesto([hexA]))
            try crear("caso\(i)/" + modelos + "blobs/sha256-\(hexA)", haceHoras: 2)
            try crear("caso\(i)/" + modelos + "blobs/sha256-\(hexB)", haceHoras: 2)
            let otro = m.deletingLastPathComponent().appendingPathComponent(raro)
            if raro == "enlace" {
                try FileManager.default.createSymbolicLink(at: otro, withDestinationURL: m)
            } else {
                try FileManager.default.createDirectory(at: otro, withIntermediateDirectories: true)
            }
            let r = Escaner.modelosLocalesTodos(contexto(), home: casa.appendingPathComponent("caso\(i)"))
            XCTAssertEqual(r.map(\.nombre), ["Modelos de Ollama"], raro)
        }
    }

    func testCarpetaDeManifiestosSinPermiso() throws {
        try XCTSkipIf(getuid() == 0, "root puede leer aunque no haya permiso")
        try crear(modelos + "manifests/registry.ollama.ai/library/m/latest", manifiesto([hexA]))
        try crear(modelos + "blobs/sha256-\(hexA)", haceHoras: 2)
        try crear(modelos + "blobs/sha256-\(hexB)", haceHoras: 2)
        let library = casa.appendingPathComponent(modelos + "manifests/registry.ollama.ai/library")
        XCTAssertEqual(chmod(library.path, 0), 0)
        defer { _ = chmod(library.path, 0o755) }
        XCTAssertEqual(Escaner.modelosLocalesTodos(contexto(), home: casa).map(\.nombre), ["Modelos de Ollama"])
    }

    func testNadaConOllamaEnMarchaNiSinListaDeProcesos() throws {
        try crear(modelos + "manifests/registry.ollama.ai/library/m/latest", manifiesto([hexA]))
        try crear(modelos + "blobs/sha256-\(hexA)", haceHoras: 2)
        try crear(modelos + "blobs/sha256-\(hexB)", haceHoras: 2)
        XCTAssertFalse(Escaner.modelosLocalesTodos(contexto(), home: casa).isEmpty)
        let ollama = ["/applications/ollama.app/contents/resources/ollama serve"]
        XCTAssertTrue(Escaner.modelosLocalesTodos(contexto(lineas: ollama), home: casa).isEmpty)
        XCTAssertTrue(Escaner.modelosLocalesTodos(contexto(lineas: []), home: casa).isEmpty)
    }

    func testTrozosYDescargasRecientesNoSeTocan() throws {
        try crear(modelos + "manifests/registry.ollama.ai/library/m/latest", manifiesto([hexA]))
        try crear(modelos + "blobs/sha256-\(hexA)")
        try crear(modelos + "blobs/sha256-\(hexB)")
        try crear(modelos + "blobs/sha256-\(hexC)-partial")
        XCTAssertEqual(Escaner.modelosLocalesTodos(contexto(), home: casa).map(\.nombre), ["Modelo de Ollama: m:latest"])
    }

    func testMsty() throws {
        let raiz = "Library/Application Support/Msty/models/"
        try crear(raiz + "manifests/registry.ollama.ai/library/m/latest", manifiesto([hexA]))
        try crear(raiz + "blobs/sha256-\(hexA)", haceHoras: 2)
        // Sin Msty instalado, nada: lo que dejó sale en «Restos de apps borradas».
        XCTAssertTrue(Escaner.modelosLocalesTodos(contexto(), home: casa).isEmpty)

        let apps = instaladas(DatosApp(visible: "Msty", principal: "app.msty.app", nombres: ["Msty"]))
        let r = Escaner.modelosLocalesTodos(contexto(apps: apps), home: casa)
        XCTAssertEqual(r.map(\.nombre), ["Modelo de Msty: m:latest"])
        XCTAssertEqual(r.first?.enUso, EnUso.app(nombre: "Msty", claves: ["Msty"]))
        let msty = ["/applications/msty.app/contents/macos/msty"]
        XCTAssertTrue(Escaner.modelosLocalesTodos(contexto(apps: apps, lineas: msty), home: casa).isEmpty)

        // Con la lista ilegible, nunca la carpeta entera de Msty.
        try crear(raiz + "manifests/registry.ollama.ai/library/roto/latest", "{")
        XCTAssertTrue(Escaner.modelosLocalesTodos(contexto(apps: apps), home: casa).isEmpty)
    }

    // MARK: LM Studio

    func testMotoresDeLMStudio() throws {
        let backends = casa.appendingPathComponent(".lmstudio/extensions/backends")
        let llama = "llama.cpp-mac-arm64-apple-metal-advsimd-"
        for n in [llama + "1.9.0", llama + "1.10.0", llama + "1.2.3", "mlx-llm-mac-arm64-apple-metal-advsimd-0.16.1",
                  "vendor", "sin-version", ".oculto-1.0.0"] {
            try crear(".lmstudio/extensions/backends/\(n)/backend-manifest.json")
        }
        // Un enlace con forma de versión no cuenta.
        try FileManager.default.createSymbolicLink(at: backends.appendingPathComponent("mlx-llm-mac-arm64-apple-metal-advsimd-0.1.0"),
                                                   withDestinationURL: backends.appendingPathComponent("vendor"))
        XCTAssertEqual(Escaner.modelosLocalesMotoresSobrantes(en: backends).map(\.lastPathComponent), [llama + "1.2.3", llama + "1.9.0"])
        XCTAssertEqual(Escaner.modelosLocalesMotoresSobrantes(en: casa.appendingPathComponent("no-existe")), [])
    }

    func testHogarDeLMStudio() throws {
        let lmstudio = casa.appendingPathComponent(".lmstudio")
        let cache = casa.appendingPathComponent(".cache/lm-studio")
        // Sin puntero: ~/.cache/lm-studio si existe; si no, ~/.lmstudio.
        XCTAssertEqual(Escaner.modelosLocalesHogarLMStudio(home: casa)?.path, lmstudio.path)
        try crear(".cache/lm-studio/settings.json", "{}")
        XCTAssertEqual(Escaner.modelosLocalesHogarLMStudio(home: casa)?.path, cache.path)
        // Con puntero manda el puntero, si lleva a una carpeta que existe dentro de tu carpeta personal.
        try crear(".lmstudio/settings.json", "{}")
        try crear(".lmstudio-home-pointer", lmstudio.path + "\n")
        XCTAssertEqual(Escaner.modelosLocalesHogarLMStudio(home: casa)?.path, lmstudio.path)
        try crear(".lmstudio-home-pointer", "/Volumes/Externo/lmstudio")
        XCTAssertNil(Escaner.modelosLocalesHogarLMStudio(home: casa))
        try crear(".lmstudio-home-pointer", casa.appendingPathComponent("no-existe").path)
        XCTAssertNil(Escaner.modelosLocalesHogarLMStudio(home: casa))
    }

    func testInstalacionAnteriorDeLMStudio() throws {
        let activo = casa.appendingPathComponent(".lmstudio")
        try crear(".lmstudio/settings.json", "{}")
        try crear(".cache/lm-studio/extensions/backends/llama.cpp-1.0.0/lib.dylib")
        try crear(".cache/lm-studio/models/autor/modelo/modelo.gguf")
        try crear(".cache/lm-studio/conversations/chat.json")
        let extensiones = casa.appendingPathComponent(".cache/lm-studio/extensions").path
        // Solo sus extensiones: nunca los modelos ni las conversaciones.
        XCTAssertEqual(Escaner.modelosLocalesExtensionesAnteriores(activo: activo, home: casa).map(\.path), [extensiones])
        // La carpeta que se usa nunca es «la anterior».
        XCTAssertEqual(Escaner.modelosLocalesExtensionesAnteriores(activo: casa.appendingPathComponent(".cache/lm-studio"), home: casa), [])

        // Si los modelos se descargan en la carpeta anterior, no se toca nada.
        let descargas = casa.appendingPathComponent(".cache/lm-studio/models").path
        try crear(".lmstudio/settings.json", "{\"downloadsFolder\":\"\(descargas)\"}")
        XCTAssertEqual(Escaner.modelosLocalesExtensionesAnteriores(activo: activo, home: casa), [])
        // Si los ajustes no se entienden, tampoco.
        try crear(".lmstudio/settings.json", "{roto")
        XCTAssertEqual(Escaner.modelosLocalesExtensionesAnteriores(activo: activo, home: casa), [])
        // Con los modelos en otra parte, sí.
        try crear(".lmstudio/settings.json", "{\"downloadsFolder\":\"/Volumes/Externo/modelos\"}")
        XCTAssertEqual(Escaner.modelosLocalesExtensionesAnteriores(activo: activo, home: casa).map(\.path), [extensiones])
    }

    /// Un enlace a la carpeta que se usa no es «otra» carpeta: nunca se ofrecen sus extensiones.
    func testEnlaceEntreLasCarpetasDeLMStudio() throws {
        try crear(".cache/lm-studio/extensions/backends/llama.cpp-1.0.0/lib.dylib")
        try FileManager.default.createSymbolicLink(at: casa.appendingPathComponent(".lmstudio"),
                                                   withDestinationURL: casa.appendingPathComponent(".cache/lm-studio"))
        XCTAssertEqual(Escaner.modelosLocalesExtensionesAnteriores(activo: casa.appendingPathComponent(".lmstudio"), home: casa), [])
    }

    func testLMStudioSoloInstaladoYCerrado() throws {
        for v in ["1.0.0", "1.1.0"] { try crear(".lmstudio/extensions/backends/llama.cpp-mac-arm64-\(v)/lib.dylib") }
        try crear(".lmstudio/models/autor/modelo/modelo.gguf")
        XCTAssertTrue(Escaner.modelosLocalesTodos(contexto(), home: casa).isEmpty, "sin LM Studio instalado, nada")

        let apps = instaladas(DatosApp(visible: "LM Studio", principal: "ai.elementlabs.lmstudio", nombres: ["LM Studio"]))
        let r = Escaner.modelosLocalesTodos(contexto(apps: apps), home: casa)
        XCTAssertEqual(r.map(\.nombre), ["Versiones anteriores de los motores de LM Studio"])
        XCTAssertEqual(r.first?.rutas.map(\.lastPathComponent), ["llama.cpp-mac-arm64-1.0.0"])
        XCTAssertEqual(r.first?.riesgo, Riesgo.revisar)
        XCTAssertEqual(r.first?.seleccionado, false)
        XCTAssertFalse(r.flatMap(\.rutas).contains { $0.path.contains("/models/") })
        // Con el comando «lms» en marcha, nada.
        let lms = ["/users/ana/.lmstudio/bin/lms server start"]
        XCTAssertTrue(Escaner.modelosLocalesTodos(contexto(apps: apps, lineas: lms), home: casa).isEmpty)
    }

    // MARK: GPT4All

    func testRestosDeGPT4All() throws {
        let base = "Library/Application Support/nomic.ai/GPT4All/"
        let carpeta = casa.appendingPathComponent(base)
        let viejo = try crear(base + "incomplete-modelo.gguf", haceHoras: 72)
        try crear(base + "incomplete-otro.gguf")   // todavía se está descargando
        try crear(base + "modelo.gguf", haceHoras: 72)
        try crear(base + "gpt4all-1234.chat", haceHoras: 72)
        let v2 = try crear(base + "localdocs_v2.db")
        let wal = try crear(base + "localdocs_v2.db-wal")

        var restos = Escaner.modelosLocalesRestosGPT4All(en: carpeta)
        XCTAssertEqual(restos.incompletos.map(\.path), [viejo.path])
        XCTAssertEqual(restos.indices, [], "sin el índice nuevo, el anterior es el que se usa")

        try crear(base + "localdocs_v3.db")
        try crear(base + "localdocs_v3.db-wal")
        restos = Escaner.modelosLocalesRestosGPT4All(en: carpeta)
        XCTAssertEqual(restos.indices.map(\.path), [v2.path, wal.path])

        let nada = Escaner.modelosLocalesRestosGPT4All(en: casa.appendingPathComponent("no-existe"))
        XCTAssertTrue(nada.incompletos.isEmpty && nada.indices.isEmpty)
    }

    func testCarpetaDeGPT4All() throws {
        XCTAssertEqual(Escaner.modelosLocalesCarpetaGPT4All(home: casa)?.path,
                       casa.appendingPathComponent("Library/Application Support/nomic.ai/GPT4All").path)
        let propia = casa.appendingPathComponent("Modelos IA")
        try crear(".config/nomic.ai/GPT4All.ini", "[General]\nmodelPath=\(propia.path)/\n")
        XCTAssertEqual(Escaner.modelosLocalesCarpetaGPT4All(home: casa)?.path, propia.path)
        try crear(".config/nomic.ai/GPT4All.ini", "[General]\nmodelPath=/Volumes/Externo/modelos\n")
        XCTAssertNil(Escaner.modelosLocalesCarpetaGPT4All(home: casa), "fuera de tu carpeta personal, nada")
    }

    func testGPT4AllSoloInstaladoYCerrado() throws {
        let base = "Library/Application Support/nomic.ai/GPT4All/"
        let incompleto = try crear(base + "incomplete-modelo.gguf", haceHoras: 72)
        try crear(base + "localdocs_v3.db")
        let v1 = try crear(base + "localdocs_v1.db")
        try crear(base + "gpt4all-1234.chat", haceHoras: 72)
        XCTAssertTrue(Escaner.modelosLocalesTodos(contexto(), home: casa).isEmpty, "sin GPT4All instalado, nada")

        let apps = instaladas(DatosApp(visible: "GPT4All", principal: "io.gpt4all.gpt4all", nombres: ["GPT4All"]))
        let r = Escaner.modelosLocalesTodos(contexto(apps: apps), home: casa)
        let descargas = try XCTUnwrap(r.first { $0.nombre == "Descargas a medias de GPT4All" })
        XCTAssertEqual(descargas.rutas.map(\.path), [incompleto.path])
        XCTAssertTrue(descargas.seleccionado)
        let indices = try XCTUnwrap(r.first { $0.nombre == "Índices antiguos de LocalDocs" })
        XCTAssertEqual(indices.rutas.map(\.path), [v1.path])
        XCTAssertEqual(indices.riesgo, .seguro)
        XCTAssertFalse(indices.seleccionado)
        // Nunca las conversaciones ni el índice actual.
        XCTAssertFalse(r.flatMap(\.rutas).contains { $0.pathExtension == "chat" || $0.lastPathComponent.hasPrefix("localdocs_v3") })
    }

    // MARK: Modelos dentro de apps

    func testModelosDentroDeApps() throws {
        let gb: Int64 = 1_000_000_000
        let soporte = "Library/Application Support/"
        let whisper = try crear(soporte + "MacWhisper/models/ggml-large-v3.bin")
        let gguf = try crear(soporte + "Ejemplo/modelos/llama.gguf")
        let pesos = try crear(soporte + "Ejemplo/Vision.mlmodelc/weights/weight.bin")
        let mlmodelc = casa.appendingPathComponent(soporte + "Ejemplo/Vision.mlmodelc")
        let contenedor = try crear("Library/Containers/com.ejemplo.app/Data/Documents/modelo.gguf")
        // Nunca: .bin que no parecen modelos, lo que puede ser tuyo, lo de Apple, lo que se trata aparte, lo que ya se
        // ofrece por otro lado (catálogo, cachés, Hugging Face), lo de Windows dentro de Wine y lo que está fuera de los
        // datos de las apps.
        let nunca = try [
            crear(soporte + "Ejemplo/otro/datos.bin"),
            crear(soporte + "Ejemplo/LoRA/estilo.safetensors"),
            crear(soporte + "Ejemplo/user/mio.ckpt"),
            crear(soporte + "Ejemplo/Fine-Tuned/mio.gguf"),
            crear(soporte + "Jan/data/models/x.gguf"),
            crear(soporte + "com.apple.algo/modelo.onnx"),
            crear(soporte + "Cubierta/models/x.gguf"),
            crear(soporte + "CrossOver/Bottles/b/drive_c/Programa/modelo.onnx"),
            crear("Library/Caches/com.ejemplo.app/modelo.gguf"),
            crear("Library/Containers/com.ejemplo.app/Data/Library/Caches/modelo.gguf"),
            crear("Library/Containers/com.ejemplo.app/Data/Documents/huggingface/models/org/repo/model.safetensors"),
            crear("Documents/modelo.gguf"),
        ]
        var archivos = ([whisper, gguf, pesos, contenedor] + nunca).map { (ruta: $0.path, bytes: gb) }
        // Ni los pequeños ni lo que ya no existe.
        let pequeno = try crear(soporte + "Ejemplo/modelos/pequeno.gguf")
        archivos.append((ruta: pequeno.path, bytes: 10_000_000))
        let borrado = casa.appendingPathComponent(soporte + "Ejemplo/modelos/borrado.gguf")
        archivos.append((ruta: borrado.path, bytes: gb))
        let carpetas = [(ruta: mlmodelc.path, bytes: gb)]
        let cubiertas: Set<String> = [casa.appendingPathComponent(soporte + "Cubierta").path]

        let r = Escaner.modelosLocalesModelosEnApps(archivos: archivos, carpetas: carpetas, home: casa, accesoTotal: false,
                                                    cubiertas: cubiertas)
        XCTAssertEqual(Set(r.keys), ["MacWhisper", "Ejemplo"])
        XCTAssertEqual(r["MacWhisper"]?.map(\.path), [whisper.path])
        // Los pesos de dentro del .mlmodelc van con él.
        XCTAssertEqual(Set(r["Ejemplo"]?.map(\.path) ?? []), [gguf.path, mlmodelc.path])

        // Con Acceso total, también los contenedores (pero nunca lo demás).
        let conAcceso = Escaner.modelosLocalesModelosEnApps(archivos: archivos, carpetas: carpetas, home: casa, accesoTotal: true,
                                                            cubiertas: cubiertas)
        XCTAssertEqual(conAcceso["com.ejemplo.app"]?.map(\.path), [contenedor.path])
        let ofrecidas = Set(conAcceso.values.joined().map(\.path))
        for u in nunca + [pesos, pequeno, borrado] { XCTAssertFalse(ofrecidas.contains(u.path), u.path) }
    }

    func testCarpetaDeLaApp() {
        XCTAssertEqual(Escaner.modelosLocalesCarpetaDeApp(["Library", "Application Support", "X", "m.gguf"], accesoTotal: false), "X")
        XCTAssertNil(Escaner.modelosLocalesCarpetaDeApp(["Library", "Application Support", "m.gguf"], accesoTotal: true))
        let contenedor = ["Library", "Containers", "com.x", "Data", "Library", "Application Support", "m.gguf"]
        XCTAssertNil(Escaner.modelosLocalesCarpetaDeApp(contenedor, accesoTotal: false))
        XCTAssertEqual(Escaner.modelosLocalesCarpetaDeApp(contenedor, accesoTotal: true), "com.x")
        // La caché del contenedor y lo de swift-transformers ya salen por otro lado.
        for otro in [["Library", "Containers", "com.x", "Data", "Library", "Caches", "m.gguf"],
                     ["Library", "Containers", "com.x", "Data", "Documents", "huggingface", "models", "m.gguf"],
                     ["Library", "Containers", "com.x", "Data", "tmp", "m.gguf"]] {
            XCTAssertNil(Escaner.modelosLocalesCarpetaDeApp(otro, accesoTotal: true), otro.joined(separator: "/"))
        }
        XCTAssertEqual(Escaner.modelosLocalesCarpetaDeApp(["Library", "Group Containers", "group.com.x", "m.gguf"], accesoTotal: true),
                       "group.com.x")
        XCTAssertTrue(Escaner.modelosLocalesAppExcluida("group.com.apple.algo"))
        XCTAssertTrue(Escaner.modelosLocalesAppExcluida("LM Studio"))
        XCTAssertFalse(Escaner.modelosLocalesAppExcluida("MacWhisper"))
    }
}
