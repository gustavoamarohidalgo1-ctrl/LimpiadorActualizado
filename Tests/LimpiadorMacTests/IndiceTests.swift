import XCTest
@testable import LimpiadorMac

/// Indexa una carpeta personal de prueba y comprueba lo que encuentra.
final class IndiceTests: XCTestCase {
    private var casa: URL!

    override func setUpWithError() throws {
        casa = FileManager.default.temporaryDirectory.appendingPathComponent("Casa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: casa)
    }

    private func crear(_ rel: String, bytes: Int = 0, texto: String? = nil) throws {
        let url = casa.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let texto {
            try Data(texto.utf8).write(to: url)
        } else {
            var datos = Data(count: bytes)
            datos.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
            try datos.write(to: url)
            // Que ocupe bloques reales en el disco antes de medir.
            let h = try FileHandle(forUpdating: url)
            try h.synchronize()
            try h.close()
        }
    }

    private func indexar() -> Indice {
        Indice.construir(accesoTotal: false, home: casa.path, extras: [], progreso: { _ in })
    }

    func testArtefactosYRecursosDeElectron() throws {
        try crear("Proyectos/web/package.json", texto: "{}")
        try crear("Proyectos/web/node_modules/lib/index.js", bytes: 1_500_000)
        try crear("Proyectos/web/build/app.js", bytes: 1_500_000)
        // electron-builder: build/ tiene íconos hechos a mano.
        try crear("Proyectos/escritorio/package.json", texto: "{}")
        try crear("Proyectos/escritorio/build/icon.icns", bytes: 1_500_000)

        let indice = indexar()
        let rutas = Set(indice.artefactos.map(\.ruta))
        let web = casa.appendingPathComponent("Proyectos/web").path
        XCTAssertTrue(rutas.contains(web + "/node_modules"))
        XCTAssertTrue(rutas.contains(web + "/build"))
        XCTAssertFalse(rutas.contains(casa.appendingPathComponent("Proyectos/escritorio/build").path),
                       "El build/ de electron-builder son recursos, no compilación")
        XCTAssertGreaterThanOrEqual(indice.bytes(de: URL(fileURLWithPath: web + "/node_modules")), 1_500_000)
    }

    func testArchivosDeGradleYKeystores() throws {
        try crear("Android/MiApp/app/build.gradle", texto: "android { compileSdk 34 }")
        try crear("Android/MiApp/gradle/libs.versions.toml", texto: "compileSdk = \"35\"")
        try crear("Android/MiApp/app/build.gradle.kts", texto: "android { compileSdk = 33 }")
        try crear("Android/MiApp/app/firma.jks", bytes: 2_000)

        let indice = indexar()
        let gradle = Set(indice.archivosGradle.map { ($0 as NSString).lastPathComponent })
        XCTAssertEqual(gradle, ["build.gradle", "libs.versions.toml", "build.gradle.kts"])
        XCTAssertTrue(indice.sensibles.contains { $0.tipo == .keystore })

        let uso = UsoSDK.leer(indice.archivosGradle)
        XCTAssertEqual(uso.plataformas, [33, 34, 35])
    }

    func testCarpetaPersonalProtegidaAunqueSeaDePrueba() {
        XCTAssertFalse(Seguridad.sePuedeBorrar(Rutas.home))
    }
}
