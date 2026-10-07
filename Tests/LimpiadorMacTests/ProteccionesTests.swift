import XCTest
@testable import LimpiadorMac

/// Lo que nunca se ofrece ni se borra, aunque esté dentro de algo que sí se puede limpiar.
final class ProteccionesTests: XCTestCase {
    private func enHome(_ rel: String) -> URL { Rutas.enHome(rel) }

    func testNubeYDatosDeMacOS() {
        for rel in ["Library/Mobile Documents/com~apple~CloudDocs/foto.jpg", "Library/CloudStorage/Dropbox/a.pdf",
                    "Library/Application Support/FileProvider/x", "Library/Caches/com.apple.bird/x",
                    "Library/Messages/chat.db", ".dropbox/instance1", ".pcloud/Cache/123", ".gemini/tmp/sesion",
                    ".cache/huggingface/token", ".kaggle/kaggle.json", "Library/Caches/com.apple.Safari.SafeBrowsing/x",
                    "Library/Caches/x/com.apple.e5rt.e5bundlecache", "Pictures/Fotos.photoslibrary/database/Photos.sqlite"] {
            XCTAssertFalse(Seguridad.sePuedeBorrar(enHome(rel)), rel)
        }
        // Lo de al lado sí se puede.
        for rel in ["Library/Caches/com.ejemplo.app", ".cache/huggingface/hub/models--x", ".gemini/antigravity-browser-profile",
                    "Library/Messages/Caches/Previews/Attachments/a", "Library/Caches/com.apple.Safari"] {
            XCTAssertTrue(Seguridad.sePuedeBorrar(enHome(rel)), rel)
        }
        XCTAssertFalse(Seguridad.sePuedeBorrarComoAdmin(URL(fileURLWithPath: "/Library/Caches/com.apple.containermanagerd")))
    }

    func testCarpetasSincronizadas() {
        XCTAssertTrue(Evaluador.enCarpetaSincronizada(enHome("Dropbox/informe.pdf").path))
        XCTAssertTrue(Evaluador.enCarpetaSincronizada(enHome("Google Drive/a/b.txt").path))
        XCTAssertFalse(Evaluador.enCarpetaSincronizada(enHome("Dropbox").path))
        XCTAssertFalse(Evaluador.enCarpetaSincronizada(enHome("Proyectos/Dropbox/x").path))
    }

    func testFondosEnUsoDentroDePlistsAnidados() throws {
        let interno = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": "a1b2c3d4-0000-1111-2222-333344445555"], format: .binary, options: 0)
        var r = Set<String>()
        FondosEnUso.recoger(["Displays": ["Main": ["Configuration": interno]]], en: &r, nivel: 0)
        XCTAssertEqual(r, ["A1B2C3D4-0000-1111-2222-333344445555"])
    }

    func testOfrecerSoloLoQueSePuedeQuitar() throws {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("Quitar-\(UUID().uuidString)")
        let archivo = raiz.appendingPathComponent("a.tmp")
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        defer {
            _ = chflags(archivo.path, 0)
            try? FileManager.default.removeItem(at: raiz)
        }
        try Data("x".utf8).write(to: archivo)
        XCTAssertTrue(Escaner.sePuedeQuitar(archivo, admin: false))
        // Bloqueado (uchg): ni siquiera se ofrece.
        XCTAssertEqual(chflags(archivo.path, UInt32(UF_IMMUTABLE)), 0)
        XCTAssertFalse(Escaner.sePuedeQuitar(archivo, admin: false))
    }

    func testCoberturaDeAdministradorMiraLaExtension() {
        let reglas = [Regla("a", "/private/var/log", nombre: "A", detalle: "D.", consecuencia: "C.").admin().archivos("gz")]
        XCTAssertTrue(Catalogo.cubre("/var/log/asl/viejo.gz", admin: true, lista: reglas))
        XCTAssertFalse(Catalogo.cubre("/var/log/system.log", admin: true, lista: reglas))
        XCTAssertFalse(Catalogo.cubre("/var/log/a/b/c/d/e/f.gz", admin: true, lista: reglas))
    }

    func testCarpetasDeRestos() {
        XCTAssertTrue(Escaner.enCarpetaDeRestos("~/Library/Application Support/Telegram Desktop/tdata"))
        XCTAssertTrue(Escaner.enCarpetaDeRestos("~/Library/Group Containers/X.y/cache"))
        XCTAssertFalse(Escaner.enCarpetaDeRestos("~/Movies/*.fcpbundle/*/Render Files"))
        XCTAssertFalse(Escaner.enCarpetaDeRestos("~/.npm/_cacache"))
    }
}
