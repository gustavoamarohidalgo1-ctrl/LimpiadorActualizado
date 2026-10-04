import XCTest
@testable import LimpiadorMac

/// Saber a qué app pertenece cada carpeta es lo que evita ofrecer datos de apps instaladas como «restos».
final class AppsInstaladasTests: XCTestCase {
    private func apps(_ lista: [DatosApp]) -> AppsInstaladas {
        var a = AppsInstaladas()
        for d in lista { a.agregar(d, enAplicaciones: true) }
        return a
    }

    func testTeamID() {
        let equipo = AppsInstaladas.separarEquipo("UBF8T346G9.Office")
        XCTAssertEqual(equipo?.equipo, "UBF8T346G9")
        XCTAssertEqual(equipo?.resto, "Office")
        XCTAssertNil(AppsInstaladas.separarEquipo("com.apple.Safari"))
        XCTAssertNil(AppsInstaladas.separarEquipo("ABCDEFGHIJ.sinNumeros"))
        XCTAssertNil(AppsInstaladas.separarEquipo("1234567890.sinLetras"))
        XCTAssertEqual(AppsInstaladas.sinPrefijoDeGrupo("group.net.whatsapp.WhatsApp.shared"), "net.whatsapp.WhatsApp.shared")
        XCTAssertEqual(AppsInstaladas.sinPrefijoDeGrupo("2BUA8C4S2C.com.1password"), "com.1password")
    }

    /// Outlook guarda el correo en «UBF8T346G9.Office»: si Word u Outlook están instalados, no es un resto.
    func testContenedorDeMicrosoftConOfficeInstalado() {
        let word = DatosApp(visible: "Microsoft Word", principal: "com.microsoft.word", nombres: ["Microsoft Word"],
                            equipos: ["UBF8T346G9"])
        XCTAssertTrue(apps([word]).estaInstalado(carpeta: "UBF8T346G9.Office"))
        XCTAssertTrue(apps([word]).estaInstalado(carpeta: "UBF8T346G9.Office.plist"))
        XCTAssertEqual(apps([word]).nombreApp(para: "UBF8T346G9.Office"), "Microsoft Word")
        // Sin ninguna app de Microsoft, sí es un resto.
        XCTAssertFalse(apps([]).estaInstalado(carpeta: "UBF8T346G9.Office"))
    }

    /// WhatsApp guarda los chats en «group.net.whatsapp.WhatsApp.shared».
    func testContenedorConPrefijoGroup() {
        let whatsapp = DatosApp(visible: "WhatsApp", principal: "net.whatsapp.whatsapp", nombres: ["WhatsApp"])
        let a = apps([whatsapp])
        XCTAssertTrue(a.estaInstalado(carpeta: "group.net.whatsapp.WhatsApp.shared"))
        XCTAssertEqual(a.nombreApp(para: "group.net.whatsapp.WhatsApp.shared"), "WhatsApp")
        XCTAssertFalse(apps([]).estaInstalado(carpeta: "group.net.whatsapp.WhatsApp.shared"))
    }

    /// Los App Groups de la firma reconocen contenedores que no se parecen al nombre de la app.
    func testAppGroupsDeLaFirma() {
        let app = DatosApp(visible: "Ejemplo", principal: "com.ejemplo.app", grupos: ["group.com.otra-cosa.compartido"])
        XCTAssertTrue(apps([app]).estaInstalado(carpeta: "group.com.otra-cosa.compartido"))
        XCTAssertEqual(apps([app]).nombreApp(para: "group.com.otra-cosa.compartido"), "Ejemplo")
    }

    /// Las extensiones y ayudantes tienen su propio contenedor en Library/Containers.
    func testExtensionesEmbebidas() {
        let app = DatosApp(visible: "Ejemplo", principal: "com.ejemplo.app", embebidos: ["io.otro.ejemplo-share"])
        XCTAssertTrue(apps([app]).estaInstalado(carpeta: "io.otro.ejemplo-share"))
        XCTAssertEqual(apps([app]).nombreApp(para: "io.otro.ejemplo-share"), "Ejemplo")
    }

    /// «Google Earth Pro» no es Google Chrome aunque empiecen igual.
    func testInstaladoresPorNombreCompleto() {
        let chrome = DatosApp(visible: "Google Chrome", principal: "com.google.chrome",
                              nombres: ["Chrome", "Google Chrome"], version: "120.0")
        let docker = DatosApp(visible: "Docker", principal: "com.docker.docker", nombres: ["Docker"], version: "4.30.0")
        let zoom = DatosApp(visible: "zoom.us", principal: "us.zoom.xos", nombres: ["zoom.us"], version: "6.0")
        let a = apps([chrome, docker, zoom])

        XCTAssertNil(a.appParaInstalador(Escaner.nombreBase("Google Earth Pro 7.3.6 (arm64)")))
        XCTAssertNil(a.appParaInstalador(Escaner.nombreBase("Microsoft Teams")))
        XCTAssertEqual(a.appParaInstalador(Escaner.nombreBase("googlechrome"))?.nombre, "Google Chrome")
        XCTAssertEqual(a.appParaInstalador(Escaner.nombreBase("googlechrome"))?.version, "120.0")
        XCTAssertEqual(a.appParaInstalador(Escaner.nombreBase("Docker Desktop 4.30"))?.nombre, "Docker")
        XCTAssertEqual(a.appParaInstalador(Escaner.nombreBase("zoomusInstallerFull"))?.nombre, "zoom.us")
    }

    func testNombreBaseDeInstaladores() {
        XCTAssertEqual(Escaner.nombreBase("Google Earth Pro 7.3.6 (arm64)"), "googleearthpro")
        XCTAssertEqual(Escaner.nombreBase("Cline_0.0.36_universal"), "cline")
        XCTAssertEqual(Escaner.nombreBase("zoomusInstallerFull"), "zoomus")
        XCTAssertEqual(Escaner.nombreBase("1Password-8.10.36"), "1password")
        XCTAssertEqual(Escaner.nombreBase("android-studio-2024.2.1.11-mac_arm"), "androidstudio")
        XCTAssertEqual(Escaner.nombreBase("Firefox 131.0"), "firefox")
        XCTAssertEqual(Escaner.nombreBase("Instalador-1.2"), "")
    }
}
