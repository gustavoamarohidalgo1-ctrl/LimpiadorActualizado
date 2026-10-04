import XCTest
@testable import LimpiadorMac

final class BasicoTests: XCTestCase {
    func testListaEnEspanol() {
        XCTAssertEqual(Formato.lista([]), "")
        XCTAssertEqual(Formato.lista(["a"]), "a")
        XCTAssertEqual(Formato.lista(["a", "b", "c"]), "a, b y c")
        XCTAssertEqual(Formato.listaCorta(["a", "b", "c", "d", "e"], maximo: 3), "a, b, c y 2 más")
    }

    func testNormalizar() {
        XCTAssertEqual(AppsInstaladas.normalizar("Google Chrome"), "googlechrome")
        XCTAssertEqual(AppsInstaladas.normalizar("com.brave.Browser"), "combravebrowser")
    }

    func testNuncaSeBorraLaCarpetaPersonal() {
        XCTAssertFalse(Seguridad.sePuedeBorrar(Rutas.home))
        XCTAssertFalse(Seguridad.sePuedeBorrar(Rutas.enHome("Library")))
        XCTAssertFalse(Seguridad.sePuedeBorrar(Rutas.enHome(".ssh")))
        XCTAssertFalse(Seguridad.sePuedeBorrar(URL(fileURLWithPath: "/System")))
        XCTAssertTrue(Seguridad.sePuedeBorrar(Rutas.enHome("Library/Caches/com.ejemplo.App")))
    }
}
