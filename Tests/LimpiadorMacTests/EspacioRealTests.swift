import Darwin
import XCTest
@testable import LimpiadorMac

/// Comprueba en un disco APFS real que el espacio «liberable» descuenta clones y enlaces duros.
final class EspacioRealTests: XCTestCase {
    private var carpeta: URL!

    override func setUpWithError() throws {
        carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("EspacioReal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: carpeta)
    }

    /// Escribe `megas` MB aleatorios (no comprimibles) y los fuerza al disco para que ocupen bloques reales.
    private func archivo(_ nombre: String, megas: Int) throws -> URL {
        let url = carpeta.appendingPathComponent(nombre)
        var datos = Data(count: megas * 1_048_576)
        datos.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        try datos.write(to: url)
        let h = try FileHandle(forUpdating: url)
        try h.synchronize()
        try h.close()
        return url
    }

    func testArchivoNormalSeLiberaEntero() throws {
        let a = try archivo("normal.bin", megas: 2)
        let r = EspacioReal.calcular([a.path])
        XCTAssertGreaterThanOrEqual(r.aparente, 2_000_000)
        XCTAssertGreaterThanOrEqual(r.liberable, 2_000_000)
        XCTAssertLessThan(r.compartido, 100_000)
        XCTAssertNotNil(EspacioReal.tamanoPrivado(de: a.path), "APFS debería decir el tamaño privado")
    }

    /// Un clon de APFS comparte todos sus bloques: borrarlo no libera casi nada.
    func testClonNoLiberaEspacio() throws {
        let original = try archivo("original.bin", megas: 4)
        let clon = carpeta.appendingPathComponent("clon.bin")
        guard clonefile(original.path, clon.path, 0) == 0 else {
            throw XCTSkip("Este disco no permite clones (no es APFS)")
        }
        let r = EspacioReal.calcular([clon.path])
        XCTAssertGreaterThanOrEqual(r.aparente, 4_000_000, "El análisis ve 4 MB")
        XCTAssertLessThan(r.liberable, 512 * 1024, "Pero borrar el clon no libera casi nada")
        XCTAssertGreaterThanOrEqual(r.compartido, 3_500_000)
    }

    /// Un archivo con dos nombres (enlace duro) solo se libera si se borran los dos.
    func testEnlaceDuroSoloSiSeBorranTodos() throws {
        let a = try archivo("a.bin", megas: 2)
        let b = carpeta.appendingPathComponent("b.bin")
        XCTAssertEqual(link(a.path, b.path), 0)

        let uno = EspacioReal.calcular([a.path])
        XCTAssertLessThan(uno.liberable, 100_000, "Queda el otro nombre: no se libera")

        let ambos = EspacioReal.calcular([a.path, b.path])
        XCTAssertGreaterThanOrEqual(ambos.liberable, 2_000_000)
    }

    /// Una carpeta y algo de dentro no se cuentan dos veces.
    func testRutasAnidadasUnaVez() throws {
        let a = try archivo("a.bin", megas: 1)
        let solo = EspacioReal.calcular([a.path])
        let anidado = EspacioReal.calcular([carpeta.path, a.path])
        XCTAssertGreaterThanOrEqual(anidado.liberable, solo.liberable)
        XCTAssertLessThan(anidado.liberable, solo.liberable * 2)
    }
}
