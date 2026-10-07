import XCTest
@testable import LimpiadorMac

/// Cachés que el análisis general se salta (las de los contenedores de Apple y el resto de ~/.cache), sobre una
/// carpeta personal de prueba.
final class DetectoresACachesSinDuenoTests: XCTestCase {
    private var casa: URL!

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("CasaCachesSinDueno-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: casa)
    }

    // MARK: Ayudas

    private func ruta(_ rel: String) -> String { casa.appendingPathComponent(rel).path }

    /// Un archivo con contenido real (2 MB por defecto, para que el índice registre su carpeta) que, como todas las
    /// carpetas que lo contienen, lleva `dias` sin cambios.
    private func crear(_ rel: String, bytes: Int = 2_000_000, dias: Double = 3) throws {
        let url = casa.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var datos = Data(count: bytes)
        datos.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        try datos.write(to: url)
        // Que ocupe bloques reales en el disco antes de indexar.
        let h = try FileHandle(forUpdating: url)
        try h.synchronize()
        try h.close()
        let fecha = Date().addingTimeInterval(-dias * 86_400)
        var p = url.path
        while p.count > casa.path.count {
            try FileManager.default.setAttributes([.modificationDate: fecha], ofItemAtPath: p)
            p = (p as NSString).deletingLastPathComponent
        }
    }

    private func contexto(accesoTotal: Bool = true, apps: AppsInstaladas = AppsInstaladas(),
                          procesos: Procesos = Procesos()) -> Contexto {
        let indice = Indice.construir(accesoTotal: accesoTotal, home: casa.path, extras: [], progreso: { _ in })
        return Contexto(indice: indice, apps: apps, procesos: procesos, accesoTotal: accesoTotal)
    }

    /// Por defecto se sabe qué tienen abierto los programas (lsof respondió) y no es nada de la carpeta de prueba.
    private func elementos(_ c: Contexto,
                           abiertos: ArchivosAbiertos = ArchivosAbiertos(rutas: [], disponible: true)) -> [Elemento] {
        Escaner.cachesSinDuenoElementos(c, home: casa, abiertos: abiertos, ahora: Date())
    }

    private func rutas(_ els: [Elemento]) -> [String] { els.flatMap { $0.rutas.map(\.path) } }

    private func elemento(_ nombre: String, en els: [Elemento]) throws -> Elemento {
        try XCTUnwrap(els.first { $0.nombre == nombre }, "No está «\(nombre)»: \(els.map(\.nombre))")
    }

    // MARK: ~/.cache

    func testRestoDeCache() throws {
        try crear(".cache/herramienta/blob.bin")
        // Con una sesión guardada dentro: nunca.
        try crear(".cache/otra/blob.bin")
        try crear(".cache/otra/token", bytes: 40)
        // Ya la analiza otra parte (cachés de desarrollo) o el catálogo (darktable): aquí no.
        try crear(".cache/pip/http/blob.bin")
        try crear(".cache/darktable/mipmaps-1.d/blob.bin")
        // Con cambios de hoy: puede estar en uso.
        try crear(".cache/reciente/blob.bin", dias: 0)
        try crear(".cache/.oculta/blob.bin")

        let els = elementos(contexto())
        let el = try elemento("~/.cache/herramienta", en: els)
        XCTAssertEqual(el.rutas.map(\.path), [ruta(".cache/herramienta")])
        XCTAssertEqual(el.categoria, .herramientas)
        XCTAssertEqual(el.riesgo, .revisar)
        XCTAssertFalse(el.seleccionado)
        XCTAssertEqual(el.accion, .borrar)
        XCTAssertEqual(el.dueno, "herramienta")
        XCTAssertEqual(el.enUso, .proceso(nombre: "herramienta", patron: "/.cache/herramienta"))
        XCTAssertTrue(el.detalle.contains("sin cambios desde hace 3 días"), el.detalle)
        XCTAssertEqual(rutas(els), [ruta(".cache/herramienta")], "Solo la carpeta vieja, sin dueño y sin nada delicado")
    }

    /// Nada que pueda ser tuyo o que algo esté usando: claves, sesiones, bases de datos, historial, código con git,
    /// entornos de Python, documentos…
    func testNadaDelicadoDentro() throws {
        let trampas = ["token", "credentials.json", "auth-github.json", "clave.pem", "privada.key", "datos.db",
                       "historial.sqlite", "cache.sqlite3", "Cookies", "zsh_history", "access_token", "pyvenv.cfg",
                       "informe.pdf"]
        for (i, n) in trampas.enumerated() {
            try crear(".cache/trampa\(i)/blob.bin")
            try crear(".cache/trampa\(i)/dentro/\(n)", bytes: 100)
        }
        try crear(".cache/repo/blob.bin")
        try crear(".cache/repo/plugin/.git/HEAD", bytes: 100)
        // Los archivos de los modelos de IA no son claves aunque se llamen «token…».
        try crear(".cache/limpia/blob.bin")
        try crear(".cache/limpia/modelo/tokenizer.json", bytes: 100)
        try crear(".cache/limpia/modelo/special_tokens_map.json", bytes: 100)

        let els = elementos(contexto())
        XCTAssertEqual(rutas(els), [ruta(".cache/limpia")], "\(els.map(\.nombre))")
    }

    /// Si no se sabe qué tienen abierto los programas, nada; lo que alguno tiene abierto, tampoco.
    func testAbiertoOSinSaber() throws {
        let preview = "Library/Containers/com.apple.Preview/Data/Library/Caches"
        try crear(".cache/herramienta/blob.bin")
        try crear("\(preview)/x/blob.bin")
        let c = contexto()
        XCTAssertEqual(elementos(c).count, 2)
        XCTAssertTrue(elementos(c, abiertos: ArchivosAbiertos(rutas: [], disponible: false)).isEmpty)
        let abiertos = ArchivosAbiertos(rutas: [Seguridad.normalizada(ruta(".cache/herramienta/blob.bin")),
                                                Seguridad.normalizada(ruta("\(preview)/x/blob.bin"))],
                                        disponible: true)
        XCTAssertTrue(elementos(c, abiertos: abiertos).isEmpty)
    }

    /// Si una parte no se puede leer, no se sabe qué hay dentro: no se ofrece.
    func testCarpetaQueNoSePuedeLeerNoSeOfrece() throws {
        try XCTSkipIf(getuid() == 0, "root puede leerlo todo")
        try crear(".cache/cerrada/cajon/blob.bin")
        try crear(".cache/cerrada/blob.bin")
        let cajon = ruta(".cache/cerrada/cajon")
        XCTAssertEqual(chmod(cajon, 0), 0)
        defer { _ = chmod(cajon, 0o755) }
        XCTAssertTrue(elementos(contexto()).isEmpty)
    }

    /// Ni enlaces (llevarían fuera) ni una carpeta tan grande que no se pueda revisar entera.
    func testEnlacesYCarpetasDemasiadoGrandes() throws {
        try crear("fuera/cache/blob.bin")
        try FileManager.default.createDirectory(at: casa.appendingPathComponent(".cache"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: ruta(".cache/enlace"), withDestinationPath: ruta("fuera/cache"))
        XCTAssertTrue(elementos(contexto()).isEmpty)

        for i in 0..<5 { try crear(".cache/muchos/\(i).bin", bytes: 10) }
        let muchos = casa.appendingPathComponent(".cache/muchos")
        XCTAssertTrue(Escaner.cachesSinDuenoSinNadaDelicado(muchos))
        XCTAssertFalse(Escaner.cachesSinDuenoSinNadaDelicado(muchos, maximo: 3))
    }

    func testCacheCubiertaPorOtraParte() {
        let patrones = ["~/.cache/zig", "~/.cache/*-updater", "~/.cache/darktable/mipmaps-*.d", "~/.config/otra"]
        for n in ["zig", "app-updater", "darktable", "pip", "huggingface", "LM-Studio", "R"] {
            XCTAssertTrue(Escaner.cachesSinDuenoCacheCubierta(n, patrones: patrones), n)
        }
        for n in ["herramienta", "otra", "updater"] {
            XCTAssertFalse(Escaner.cachesSinDuenoCacheCubierta(n, patrones: patrones), n)
        }
        // Con el catálogo de verdad: cada carpeta de sus reglas «~/.cache/…» cuenta como cubierta.
        let catalogo = Catalogo.reglas.map(\.patron)
        for p in catalogo where p.hasPrefix("~/.cache/") {
            guard let primero = p.dropFirst("~/.cache/".count).split(separator: "/").first else { continue }
            let ejemplo = String(primero).replacingOccurrences(of: "[0-9]", with: "1").replacingOccurrences(of: "*", with: "x")
            XCTAssertTrue(Escaner.cachesSinDuenoCacheCubierta(ejemplo, patrones: catalogo), p)
        }
    }

    func testNombresDelicados() {
        for n in ["token", "TOKEN", "stored_tokens", "credentials", "credentials.json", "auth.json", "x.pem", "x.key",
                  "a.db", "b.sqlite", "c.sqlite3", "d.db-wal", "Cookies", "cookies.sqlite", "Login Data", ".zsh_history",
                  "History", "access_token.json", "github_token", "client_secret.json", "sessions", "conversations",
                  ".git", "pyvenv.cfg"] {
            XCTAssertTrue(Escaner.cachesSinDuenoNombreDelicado(n), n)
        }
        for n in ["blob.bin", "tokenizer.json", "tokenizer_config.json", "special_tokens_map.json", "added_tokens.json",
                  "modelo.safetensors", "index.json", "lsp.log", "mipmaps-1.d"] {
            XCTAssertFalse(Escaner.cachesSinDuenoNombreDelicado(n), n)
        }
    }

    // MARK: Contenedores de Apple

    func testCachesDeAppsDeApple() throws {
        let preview = "Library/Containers/com.apple.Preview/Data/Library/Caches"
        try crear("\(preview)/x/blob.bin")
        try crear("\(preview)/com.apple.Preview/fsCachedData/blob.bin")
        try crear("\(preview)/suelto.plist", bytes: 100)
        // Nunca: lo que macOS no deja tocar, documentos que se importan, guardados a medias, mapas sin conexión,
        // el estado de iCloud ni una base de datos suelta (sin su diario se estropearía).
        try crear("\(preview)/com.apple.e5rt.e5bundlecache/blob.bin")
        try crear("\(preview)/Inbox/libro.epub")
        try crear("\(preview)/TemporaryItems/blob.bin")
        try crear("\(preview)/MapasOffline/blob.bin")
        try crear("\(preview)/CloudKit/blob.bin")
        try crear("\(preview)/Cache.db", bytes: 100)
        try crear("\(preview)/Cache.db-wal", bytes: 100)
        // Con cambios de hoy.
        try crear("\(preview)/reciente/blob.bin", dias: 0)
        // Mail guarda cosas que importan; Safari y Pages ya tienen sus reglas en el catálogo; lo de iCloud nunca;
        // y lo que no es de Apple no es de este grupo.
        try crear("Library/Containers/com.apple.mail/Data/Library/Caches/y/blob.bin")
        try crear("Library/Containers/com.apple.Safari/Data/Library/Caches/z/blob.bin")
        try crear("Library/Containers/com.apple.iWork.Pages/Data/Library/Caches/w/blob.bin")
        try crear("Library/Containers/com.apple.cloudphotod/Data/Library/Caches/v/blob.bin")
        try crear("Library/Containers/com.ejemplo.app/Data/Library/Caches/u/blob.bin")

        let els = elementos(contexto())
        let el = try elemento("Caché de com.apple.Preview (Apple)", en: els)
        XCTAssertEqual(Set(el.rutas.map(\.path)),
                       [ruta("\(preview)/x"), ruta("\(preview)/com.apple.Preview"), ruta("\(preview)/suelto.plist")])
        XCTAssertEqual(el.categoria, .cachesApps)
        XCTAssertEqual(el.riesgo, .seguro)
        XCTAssertFalse(el.seleccionado)
        XCTAssertEqual(el.accion, .borrar)
        XCTAssertEqual(el.enUso, .app(nombre: "com.apple.Preview", claves: ["com.apple.Preview", "com.apple.Preview"]))
        XCTAssertEqual(rutas(els).count, 3, "\(rutas(els))")
        XCTAssertFalse(rutas(els).contains(ruta(preview)), "Nunca la carpeta Caches entera")
    }

    func testSinAccesoTotalNoSeMiraEnLosContenedores() throws {
        try crear("Library/Containers/com.apple.Preview/Data/Library/Caches/x/blob.bin")
        XCTAssertTrue(elementos(contexto(accesoTotal: false)).isEmpty)
    }

    /// Con la app abierta, sus cachés están en uso: no se ofrecen. Cerrada, sí, con su nombre.
    func testAppAbierta() throws {
        try crear("Library/Containers/com.apple.Preview/Data/Library/Caches/x/blob.bin")
        var apps = AppsInstaladas()
        apps.agregar(DatosApp(visible: "Vista Previa", principal: "com.apple.preview"), enAplicaciones: true)
        var procesos = Procesos()
        procesos.apps = [Procesos.AppAbierta(nombre: "Vista Previa", bundleID: "com.apple.preview")]
        XCTAssertTrue(elementos(contexto(apps: apps, procesos: procesos)).isEmpty)

        let el = try elemento("Caché de Vista Previa (Apple)", en: elementos(contexto(apps: apps)))
        XCTAssertEqual(el.enUso, .app(nombre: "Vista Previa", claves: ["com.apple.Preview", "Vista Previa"]))
        XCTAssertEqual(el.dueno, "Vista Previa")
    }

    func testContenedorCubiertoPorElCatalogo() {
        let patrones = ["~/Library/Containers/com.apple.iWork.*/Data/Library/Caches",
                        "~/Library/Containers/com.apple.mail/Data/Library/Caches/*",
                        "~/Library/Containers/com.apple.podcasts/Data/tmp",
                        "~/Library/Caches/com.apple.Preview"]
        XCTAssertTrue(Escaner.cachesSinDuenoContenedorCubierto("com.apple.iWork.Pages", patrones: patrones))
        XCTAssertTrue(Escaner.cachesSinDuenoContenedorCubierto("com.apple.mail", patrones: patrones))
        XCTAssertFalse(Escaner.cachesSinDuenoContenedorCubierto("com.apple.podcasts", patrones: patrones), "Solo cuenta su caché")
        XCTAssertFalse(Escaner.cachesSinDuenoContenedorCubierto("com.apple.Preview", patrones: patrones))
        // Con el catálogo de verdad.
        let catalogo = Catalogo.reglas.map(\.patron)
        for x in ["com.apple.Safari", "com.apple.iWork.Keynote", "com.apple.mail", "com.apple.Maps",
                  "com.apple.ScreenSaver.Engine.legacyScreenSaver-x86_64"] {
            XCTAssertTrue(Escaner.cachesSinDuenoContenedorCubierto(x, patrones: catalogo), x)
        }
    }

    func testContenedoresYCachesQueNoSeTocan() {
        for x in ["com.apple.mail", "com.apple.MobileSMS", "com.apple.iBooksX", "com.apple.Maps", "com.apple.geod",
                  "com.apple.CloudDocs.MobileDocumentsFileProvider", "com.apple.cloudphotod", "com.apple.Passwords",
                  "com.apple.BKAgentService"] {
            XCTAssertTrue(Escaner.cachesSinDuenoAppleExcluido(x), x)
        }
        XCTAssertFalse(Escaner.cachesSinDuenoAppleExcluido("com.apple.Preview"))
        for n in ["com.apple.e5rt.e5bundlecache", "Inbox", "TemporaryItems", "MapasOffline", "CloudKit", ".DS_Store"] {
            XCTAssertTrue(Escaner.cachesSinDuenoAppleHijoExcluido(n), n)
        }
        XCTAssertFalse(Escaner.cachesSinDuenoAppleHijoExcluido("com.apple.Preview"))
    }
}
