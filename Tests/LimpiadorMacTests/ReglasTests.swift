import XCTest
@testable import LimpiadorMac

final class ReglasTests: XCTestCase {
    // MARK: Rutas protegidas

    func testCarpetasDeSistemaDelUsuario() throws {
        let temporal = try XCTUnwrap(Sistema.temporal)
        let caches = try XCTUnwrap(Sistema.caches)
        XCTAssertTrue(temporal.contains("/T"), temporal)
        XCTAssertTrue(caches.contains("/C"), caches)
        // Lo de dentro sí; las carpetas en sí, nunca.
        XCTAssertTrue(Seguridad.sePuedeBorrar(URL(fileURLWithPath: temporal + "/com.ejemplo.temporal")))
        XCTAssertTrue(Seguridad.sePuedeBorrar(URL(fileURLWithPath: caches + "/clang")))
        XCTAssertFalse(Seguridad.sePuedeBorrar(URL(fileURLWithPath: temporal)))
        XCTAssertFalse(Seguridad.sePuedeBorrar(URL(fileURLWithPath: caches)))
        XCTAssertFalse(Seguridad.sePuedeBorrar(URL(fileURLWithPath: "/private/var/folders")))
    }

    func testHomebrewYMacOS() {
        XCTAssertTrue(Seguridad.esVersionDeHomebrew("/opt/homebrew/Cellar/node/20.1.0"))
        XCTAssertFalse(Seguridad.esVersionDeHomebrew("/opt/homebrew/Cellar/node"))
        XCTAssertFalse(Seguridad.esVersionDeHomebrew("/opt/homebrew/Cellar/node/20.1.0/bin"))
        XCTAssertFalse(Seguridad.esVersionDeHomebrew("/opt/homebrew/bin/node"))
        XCTAssertTrue(Seguridad.esInstaladorDeMacOS("/Applications/Install macOS Sonoma.app"))
        XCTAssertFalse(Seguridad.esInstaladorDeMacOS("/Applications/Install macOS Sonoma.app/Contents"))
        XCTAssertFalse(Seguridad.esInstaladorDeMacOS("/Applications/Safari.app"))
    }

    func testNuncaLlavesNiGit() {
        XCTAssertFalse(Seguridad.sePuedeBorrar(Rutas.enHome("Proyectos/app/firma.jks")))
        XCTAssertFalse(Seguridad.sePuedeBorrar(Rutas.enHome("Proyectos/app/.git")))
        XCTAssertFalse(Seguridad.sePuedeBorrar(Rutas.enHome("Proyectos/app/.git/objects")))
        XCTAssertFalse(Seguridad.sePuedeBorrar(Rutas.enHome(".vscode/extensions")))
        XCTAssertTrue(Seguridad.sePuedeBorrar(Rutas.enHome(".vscode/extensions/ejemplo.extension-1.0.0")))
        XCTAssertTrue(Seguridad.sePuedeBorrar(Rutas.enHome("Proyectos/app/.github")))
    }

    func testEstaDentro() {
        let conjunto: Set<String> = ["/a/b", "/x"]
        XCTAssertTrue(Rutas.estaDentro("/a/b/c", de: conjunto))
        XCTAssertTrue(Rutas.estaDentro("/x/y/z", de: conjunto))
        XCTAssertFalse(Rutas.estaDentro("/a/bc", de: conjunto))
        XCTAssertFalse(Rutas.estaDentro("/a/b", de: conjunto))
    }

    // MARK: Archivos abiertos

    func testHijosEnUso() {
        let abiertos = ArchivosAbiertos(rutas: ["/var/folders/x/T/com.app/archivo", "/var/folders/x/T/otra",
                                                "/var/folders/x/C/nada"], disponible: true)
        XCTAssertEqual(abiertos.hijosEnUso(de: "/var/folders/x/T"), ["com.app", "otra"])
    }

    // MARK: SDK de Android

    func testUsoDelSDK() {
        var u = UsoSDK()
        u.analizar("""
        android {
            compileSdk = 34
            buildToolsVersion "34.0.0"
            ndkVersion = "25.1.8937393"
        }
        """)
        u.analizar("android { compileSdkVersion 33 }")
        u.analizar("[versions]\nandroid-compileSdk = \"35\"")
        XCTAssertEqual(u.plataformas, [33, 34, 35])
        XCTAssertEqual(u.buildTools, ["34.0.0"])
        XCTAssertEqual(u.ndk, ["25.1.8937393"])
        XCTAssertFalse(u.plataformaIncierta)
        XCTAssertFalse(u.ndkIncierto)

        // Flutter elige la versión con variables: no se puede saber cuál.
        var flutter = UsoSDK()
        flutter.analizar("""
        android {
            compileSdk = flutter.compileSdkVersion
            ndkVersion = flutter.ndkVersion
        }
        """)
        XCTAssertTrue(flutter.plataformaIncierta)
        XCTAssertTrue(flutter.ndkIncierto)
        XCTAssertTrue(flutter.plataformas.isEmpty)
    }

    func testNumeroDePlataforma() {
        XCTAssertEqual(UsoSDK.numeroPlataforma("android-34"), 34)
        XCTAssertEqual(UsoSDK.numeroPlataforma("android-34-ext10"), 34)
        XCTAssertNil(UsoSDK.numeroPlataforma("android-UpsideDownCake"))
    }

    // MARK: Historial

    /// Las limpiezas guardadas por la versión anterior no tenían identificador.
    func testHistorialDeLaVersionAnterior() throws {
        let json = #"{"fecha":"2026-01-01T10:00:00Z","movimientos":[{"original":"/a","enPapelera":"/b","nombre":"x","bytes":5}]}"#
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let l = try d.decode(LimpiezaGuardada.self, from: Data(json.utf8))
        XCTAssertEqual(l.movimientos.count, 1)
        XCTAssertEqual(l.bytes, 5)
    }

    // MARK: Acciones

    func testSoloBorrarPasaPorLaPapelera() {
        XCTAssertTrue(AccionLimpieza.borrar.sePuedeDeshacer)
        XCTAssertFalse(AccionLimpieza.vaciarPapelera.sePuedeDeshacer)
        XCTAssertFalse(AccionLimpieza.vaciarSimulador(udid: "x").sePuedeDeshacer)
        XCTAssertFalse(AccionLimpieza.eliminarRuntime(id: "x").sePuedeDeshacer)
    }
}
