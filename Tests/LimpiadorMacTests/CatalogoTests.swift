import XCTest
@testable import LimpiadorMac

/// El motor que aplica las reglas del catálogo, sobre carpetas de prueba.
final class CatalogoTests: XCTestCase {
    private var raiz: URL!

    override func setUpWithError() throws {
        raiz = FileManager.default.temporaryDirectory.appendingPathComponent("Catalogo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: raiz)
    }

    private func crear(_ rel: String) throws {
        let url = raiz.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    private func contexto() -> Contexto {
        let indice = Indice.construir(accesoTotal: false, home: raiz.path, extras: [], progreso: { _ in })
        return Contexto(indice: indice, apps: AppsInstaladas(), procesos: Procesos(), accesoTotal: false)
    }

    private func regla(_ patron: String) -> Regla {
        Regla("prueba", raiz.path + "/" + patron, nombre: "Prueba", detalle: "Detalle.", consecuencia: "Nada.")
    }

    func testComodinesPorNivel() throws {
        try crear("juegos/a/shadercache/1.bin")
        try crear("juegos/b/shadercache/2.bin")
        try crear("juegos/c/otra/3.bin")
        let rutas = Escaner.expandir(raiz.path + "/juegos/*/shadercache").map(\.lastPathComponent)
        XCTAssertEqual(rutas.count, 2)
        XCTAssertEqual(Escaner.expandir(raiz.path + "/juegos/*/no-existe"), [])
        XCTAssertEqual(Escaner.expandir(raiz.path + "/cmake-*"), [])
        try crear("cmake-build-debug/x.o")
        XCTAssertEqual(Escaner.expandir(raiz.path + "/cmake-*").map(\.lastPathComponent), ["cmake-build-debug"])
    }

    func testHijosConservandoLaVersionMasAlta() throws {
        try crear("versiones/1.9.0/x")
        try crear("versiones/1.10.0/x")
        try crear("versiones/1.2.0/x")
        let r = regla("versiones").hijos(conservar: .versionMasAlta)
        let nombres = Set(Escaner.aplicar(r, contexto()).map(\.lastPathComponent))
        XCTAssertEqual(nombres, ["1.9.0", "1.2.0"], "Se conserva la 1.10.0, que es la más alta")
    }

    func testArchivosPorExtension() throws {
        try crear("registros/a.log")
        try crear("registros/viejos/b.log.gz")
        try crear("registros/c.txt")
        let r = regla("registros").archivos("log", "log.gz")
        let nombres = Set(Escaner.aplicar(r, contexto()).map(\.lastPathComponent))
        XCTAssertEqual(nombres, ["a.log", "b.log.gz"])
    }

    func testEdadMinima() throws {
        try crear("viejo/a.bin")
        try crear("nuevo/b.bin")
        let hace = Date().addingTimeInterval(-40 * 86400)
        for rel in ["viejo/a.bin", "viejo"] {
            try FileManager.default.setAttributes([.modificationDate: hace], ofItemAtPath: raiz.appendingPathComponent(rel).path)
        }
        let r = regla("*").edad(dias: 30)
        let nombres = Set(Escaner.aplicar(r, contexto()).map(\.lastPathComponent))
        XCTAssertTrue(nombres.contains("viejo"))
        XCTAssertFalse(nombres.contains("nuevo"))
    }

    func testElementoDeUnaRegla() {
        let r = Regla("x", "~/a", nombre: "Caché de X", detalle: "Detalle.", consecuencia: "Se regenera.")
            .en(.desarrollo).revisar().app("X", "com.ejemplo.x")
        let e = Escaner.elemento(r, [URL(fileURLWithPath: "/tmp/a")])
        XCTAssertEqual(e.categoria, .desarrollo)
        XCTAssertEqual(e.riesgo, .revisar)
        XCTAssertFalse(e.seleccionado)
        XCTAssertEqual(e.accion, .borrar)
        XCTAssertEqual(e.enUso, .app(nombre: "X", claves: ["com.ejemplo.x", "X"]))

        let sistema = Regla("y", "/Library/Caches/com.ejemplo", nombre: "Y", detalle: "D.", consecuencia: "C.").admin()
        let es = Escaner.elemento(sistema, [URL(fileURLWithPath: "/Library/Caches/com.ejemplo")])
        XCTAssertEqual(es.accion, .borrarComoAdmin)
        XCTAssertEqual(es.categoria, .sistema)
        XCTAssertFalse(es.accion.sePuedeDeshacer)
    }

    /// Fuera de la carpeta personal solo se puede borrar lo que describe una regla, con su misma forma.
    func testCoberturaDelCatalogo() {
        let reglas = [
            Regla("a", "/Library/Caches/com.ejemplo.updater", nombre: "A", detalle: "D.", consecuencia: "C.").admin(),
            Regla("b", "/private/var/log/*", nombre: "B", detalle: "D.", consecuencia: "C.").admin().archivos("gz"),
            Regla("c", "/private/var/tmp/_bazel_*", nombre: "C", detalle: "D.", consecuencia: "C.").en(.desarrollo),
        ]
        XCTAssertTrue(Catalogo.cubre("/Library/Caches/com.ejemplo.updater", admin: true, lista: reglas))
        XCTAssertFalse(Catalogo.cubre("/Library/Caches/com.ejemplo.updater", admin: false, lista: reglas))
        XCTAssertFalse(Catalogo.cubre("/Library/Caches/otra", admin: true, lista: reglas))
        XCTAssertFalse(Catalogo.cubre("/Library/Caches", admin: true, lista: reglas))
        XCTAssertTrue(Catalogo.cubre("/var/log/asl/viejo.gz", admin: true, lista: reglas))
        XCTAssertTrue(Catalogo.cubre("/var/tmp/_bazel_ana", admin: false, lista: reglas))
        XCTAssertFalse(Catalogo.cubre("/var/tmp/otra", admin: false, lista: reglas))
    }

    func testZonasProhibidasParaAdministrador() {
        for ruta in ["/", "/System/Library/Caches", "/usr/bin/ls", "/Library", "/Library/Caches", "/private/var/db/x",
                     "/Users/ana/Documents", "/Library/Keychains/System.keychain"] {
            XCTAssertFalse(Seguridad.sePuedeBorrarComoAdmin(URL(fileURLWithPath: ruta)), ruta)
        }
    }

    func testComillasParaLaOrdenDeAdministrador() {
        XCTAssertEqual(Administrador.comillasShell("/a b/it's"), "'/a b/it'\\''s'")
        XCTAssertEqual(Administrador.textoAppleScript(#"rm "x" \y"#), #""rm \"x\" \\y""#)
    }

    func testArtefactosDelCatalogo() throws {
        try crear("ProyectoUnity/ProjectSettings/ProjectVersion.txt")
        try crear("ProyectoUnity/Library/cache.bin")
        let i = try XCTUnwrap(Catalogo.artefacto(nombre: "Library", padre: raiz.appendingPathComponent("ProyectoUnity").path))
        XCTAssertEqual(Catalogo.artefactos[i].carpeta, "Library")
        // Una carpeta «Library» sin proyecto de Unity al lado no es un artefacto.
        XCTAssertNil(Catalogo.artefacto(nombre: "Library", padre: raiz.path))

        try crear("App/App.csproj")
        XCTAssertNotNil(Catalogo.artefacto(nombre: "obj", padre: raiz.appendingPathComponent("App").path))
        try crear("Nativo/CMakeLists.txt")
        XCTAssertNotNil(Catalogo.artefacto(nombre: "cmake-build-debug", padre: raiz.appendingPathComponent("Nativo").path))
        XCTAssertNil(Catalogo.artefacto(nombre: "cmake-build-debug", padre: raiz.appendingPathComponent("App").path))
    }

    /// Ninguna regla apunta a algo demasiado amplio y lo del sistema nunca se marca solo.
    func testCatalogoBienFormado() {
        var ids = Set<String>()
        let prefijos = ["~/", "/", "$TEMPORAL/", "$CACHES/"]
        for r in Catalogo.reglas {
            XCTAssertTrue(ids.insert(r.id).inserted, "id repetido: \(r.id)")
            XCTAssertTrue(prefijos.contains { r.patron.hasPrefix($0) }, r.id)
            XCTAssertFalse(r.nombre.isEmpty || r.detalle.isEmpty || r.consecuencia.isEmpty, r.id)
            XCTAssertFalse(["~", "~/", "~/Library", "~/Documents", "~/Desktop", "~/Downloads", "/", "/Library",
                            "/System", "/Applications"].contains(r.patron) && r.modo == .carpeta, r.id)
            if r.requiereAdmin {
                XCTAssertTrue(r.patron.hasPrefix("/"), r.id)
                XCTAssertFalse(r.preseleccionar, "Lo del sistema nunca se marca solo: \(r.id)")
                XCTAssertEqual(r.categoria, .sistema, r.id)
            }
            if r.riesgo != .seguro { XCTAssertFalse(r.preseleccionar, r.id) }
        }
        for a in Catalogo.artefactos {
            XCTAssertFalse(a.marcadores.isEmpty, a.carpeta)
            XCTAssertFalse(a.descripcion.isEmpty || a.consecuencia.isEmpty, a.carpeta)
        }
    }
}
