import XCTest
@testable import LimpiadorMac

/// Versiones viejas de IDEs (JetBrains Toolbox), agentes de IA de terminal, JDKs y copias de Xcode: qué se ofrece, qué
/// se conserva siempre (la versión activa y la más alta) y que, si algo no se puede leer o saber, no se ofrece nada.
final class DetectoresAVersionesIDEsYAgentesTests: XCTestCase {
    private var raiz: URL!
    private var casa: URL!

    override func setUpWithError() throws {
        raiz = FileManager.default.temporaryDirectory.appendingPathComponent("Versiones-\(UUID().uuidString)")
        casa = raiz.appendingPathComponent("casa")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: raiz)
    }

    // MARK: Ayudas

    private func url(_ rel: String) -> URL { casa.appendingPathComponent(rel) }

    private func crear(_ rel: String, _ texto: String = "x") throws {
        try crear(url(rel), Data(texto.utf8))
    }

    private func crear(_ u: URL, _ datos: Data) throws {
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try datos.write(to: u)
    }

    /// Un enlace simbólico en `rel` que apunta (con ruta absoluta) a `destino`.
    private func enlazar(_ rel: String, a destino: URL) throws {
        let u = url(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: u, withDestinationURL: destino)
    }

    /// Pone la fecha de modificación de algo (y de todo lo que tiene dentro) `dias` atrás.
    private func envejecer(_ rel: String, dias: Double) throws {
        let fecha = Date().addingTimeInterval(-dias * 86400)
        let ruta = url(rel).path
        for sub in FileManager.default.subpaths(atPath: ruta) ?? [] {
            try FileManager.default.setAttributes([.modificationDate: fecha], ofItemAtPath: ruta + "/" + sub)
        }
        try FileManager.default.setAttributes([.modificationDate: fecha], ofItemAtPath: ruta)
    }

    private func contexto(apps: AppsInstaladas = AppsInstaladas(), lineas: [String] = [],
                          abiertas: [Procesos.AppAbierta] = []) -> Contexto {
        let indice = Indice.construir(accesoTotal: false, home: casa.path, extras: [], progreso: { _ in })
        return Contexto(indice: indice, apps: apps, procesos: Procesos(apps: abiertas, lineas: lineas), accesoTotal: false)
    }

    private func agentes(_ c: Contexto, abierto: (String) -> Bool = { _ in false }) -> [Elemento] {
        Escaner.versionesIDEsYAgentesAgentes(c, home: casa, abierto: abierto)
    }

    private func jdks(_ c: Contexto) -> [Elemento] {
        Escaner.versionesIDEsYAgentesJDKs(c, home: casa, abierto: { _ in false })
    }

    /// Lo ofrecido: la última parte de cada ruta.
    private func nombres(_ els: [Elemento]) -> Set<String> {
        Set(els.flatMap { $0.rutas }.map { $0.lastPathComponent })
    }

    private func claudeCode(_ versiones: [String] = ["2.0.0", "2.0.1", "2.0.3"]) throws {
        for v in versiones { try crear(".local/share/claude/versions/\(v)", "binario") }
    }

    // MARK: Claude Code, Cursor Agent y Copilot

    /// Se conservan la versión activa (la del enlace) y la más alta; lo que no tiene nombre de versión nunca sale.
    func testClaudeCodeConservaLaActivaYLaMasAlta() throws {
        try claudeCode()
        try crear(".local/share/claude/versions/.lock", "")
        try crear(".local/share/claude/versions/2.0.4.lock", "")
        // Sin el enlace no se sabe cuál es la activa: no se ofrece nada.
        XCTAssertTrue(agentes(contexto()).isEmpty)

        try enlazar(".local/bin/claude", a: url(".local/share/claude/versions/2.0.1"))
        let els = agentes(contexto())
        XCTAssertEqual(els.map { $0.nombre }, ["Versiones anteriores de Claude Code"])
        XCTAssertEqual(nombres(els), ["2.0.0"])
        let el = try XCTUnwrap(els.first)
        XCTAssertEqual(el.categoria, .desarrollo)
        XCTAssertEqual(el.riesgo, .seguro)
        XCTAssertFalse(el.seleccionado)
        XCTAssertEqual(el.accion, .borrar)
        XCTAssertNil(el.enUso)
        XCTAssertTrue(el.consecuencia.contains("2.0.1"), el.consecuencia)
    }

    /// Un enlace roto no dice cuál es la activa.
    func testClaudeCodeConEnlaceRotoNoOfreceNada() throws {
        try claudeCode()
        try enlazar(".local/bin/claude", a: url(".local/share/claude/versions/2.0.9"))
        XCTAssertTrue(agentes(contexto()).isEmpty)
    }

    /// Lo que está en marcha (sale en la lista de procesos) o algún programa tiene abierto no se ofrece.
    func testVersionEnMarchaOAbiertaNoSeOfrece() throws {
        try claudeCode()
        try enlazar(".local/bin/claude", a: url(".local/share/claude/versions/2.0.1"))
        let vieja = url(".local/share/claude/versions/2.0.0").path.lowercased()
        XCTAssertTrue(agentes(contexto(lineas: [vieja + " --resume"])).isEmpty)
        XCTAssertTrue(agentes(contexto(), abierto: { $0.hasSuffix("/versions/2.0.0") }).isEmpty)
    }

    /// Una versión con su «.lock» (al lado o en ~/.local/state/claude/locks) la está usando o instalando algo: se queda.
    func testVersionConBloqueoNoSeOfrece() throws {
        try claudeCode(["2.0.0", "2.0.1", "2.0.2", "2.0.3"])
        try enlazar(".local/bin/claude", a: url(".local/share/claude/versions/2.0.1"))
        try crear(".local/share/claude/versions/2.0.0.lock", "")
        try crear(".local/state/claude/locks/2.0.2.lock", "12345")
        XCTAssertTrue(agentes(contexto()).isEmpty)
    }

    /// Nada fuera de tu carpeta: si la carpeta de versiones es un enlace a otro sitio, no se ofrece nada.
    func testNadaFueraDeTuCarpeta() throws {
        let fuera = raiz.appendingPathComponent("fuera")
        for v in ["2.0.0", "2.0.1", "2.0.3"] { try crear(fuera.appendingPathComponent(v), Data("binario".utf8)) }
        try enlazar(".local/share/claude/versions", a: fuera)
        try enlazar(".local/bin/claude", a: url(".local/share/claude/versions/2.0.1"))
        XCTAssertTrue(agentes(contexto()).isEmpty)
    }

    /// Cursor Agent: si no hay «cursor-agent», la activa la dice «agent». Sus versiones son carpetas.
    func testCursorAgentConEnlaceAgent() throws {
        for v in ["2025.08.01-aaa1111", "2025.08.25-bbb2222", "2025.09.04-ccc3333"] {
            try crear(".local/share/cursor-agent/versions/\(v)/cursor-agent", "binario")
        }
        try enlazar(".local/bin/agent", a: url(".local/share/cursor-agent/versions/2025.08.25-bbb2222/cursor-agent"))
        let els = agentes(contexto())
        XCTAssertEqual(els.map { $0.nombre }, ["Versiones anteriores de Cursor Agent"])
        XCTAssertEqual(nombres(els), ["2025.08.01-aaa1111"])
    }

    /// Copilot: cada plataforma por su lado; se conservan la más alta y, si hay enlace, la suya.
    func testCopilotPorPlataforma() throws {
        for v in ["0.0.330", "0.0.338", "0.0.339"] { try crear(".copilot/pkg/universal/\(v)/index.js") }
        try crear(".copilot/pkg/darwin-arm64/0.0.300/index.js")
        XCTAssertEqual(nombres(agentes(contexto())), ["0.0.330", "0.0.338"])

        try enlazar(".local/bin/copilot", a: url(".copilot/pkg/universal/0.0.330/index.js"))
        let els = agentes(contexto())
        XCTAssertEqual(els.map { $0.nombre }, ["Versiones anteriores de GitHub Copilot CLI"])
        XCTAssertEqual(nombres(els), ["0.0.338"])
    }

    /// El Claude Code de la app Claude: solo con la app instalada y cerrada. Se conservan la más alta, la usada por
    /// última vez y la que pide la app en «.sdk-version».
    func testClaudeCodeDeLaApp() throws {
        let base = "Library/Application Support/Claude/claude-code"
        for (v, dias) in [("1.0.0", 30.0), ("1.0.2", 20.0), ("1.0.5", 1.0), ("1.0.9", 10.0)] {
            try crear("\(base)/\(v)/claude", "binario")
            try envejecer("\(base)/\(v)", dias: dias)
        }
        // Sin la app instalada no se ofrece nada (lo de una app borrada sale en «Restos de apps borradas»).
        XCTAssertTrue(agentes(contexto()).isEmpty)

        var apps = AppsInstaladas()
        apps.agregarBundleID("com.anthropic.claudefordesktop", nombre: "Claude")
        let els = agentes(contexto(apps: apps))
        XCTAssertEqual(els.map { $0.nombre }, ["Versiones anteriores de Claude Code (app Claude)"])
        XCTAssertEqual(nombres(els), ["1.0.0", "1.0.2"])
        XCTAssertEqual(els.first?.enUso, .app(nombre: "Claude", claves: ["com.anthropic.claudefordesktop", "Claude"]))

        try crear("\(base)/.sdk-version", "1.0.2\n")
        XCTAssertEqual(nombres(agentes(contexto(apps: apps))), ["1.0.0"])

        // Con la app abierta, nada.
        let abierta = Procesos.AppAbierta(nombre: "Claude", bundleID: "com.anthropic.claudefordesktop")
        XCTAssertTrue(agentes(contexto(apps: apps, abiertas: [abierta])).isEmpty)
    }

    func testNombresDeVersion() {
        for n in ["2.0.1", "0.0.339", "2025.08.25-896bbe1", "17.0.8.1", "1.0.0-beta.2", "1.2.3+build.5"] {
            XCTAssertTrue(Escaner.versionesIDEsYAgentesEsVersion(n), n)
        }
        for n in [".lock", ".sdk-version", "2.0.1.lock", "2.0.1.tmp", "latest", "current", "2.0", "v2.0.1"] {
            XCTAssertFalse(Escaner.versionesIDEsYAgentesEsVersion(n), n)
        }
    }

    // MARK: JetBrains Toolbox

    private let canal = "Library/Application Support/JetBrains/Toolbox/apps/IDEA-U/ch-0"

    private func toolbox(historial: String? = nil) throws {
        for b in ["231.9011.34", "232.8660.185", "233.11799.241"] {
            try crear("\(canal)/\(b)/IntelliJ IDEA.app/Contents/Info.plist", "<plist/>")
            try crear("\(canal)/\(b).plugins/plugin.jar")
        }
        if let historial { try crear("\(canal)/.history.json", historial) }
    }

    private func sobrantesDeToolbox(procesos: [String] = [],
                                    fecha: (URL) -> Date? = { Fechas.modificacion($0) }) -> (activa: String, builds: [String], rutas: [URL])? {
        Escaner.versionesIDEsYAgentesToolboxCanal(url(canal), home: casa, procesos: procesos, abierto: { _ in false },
                                                  fecha: fecha)
    }

    /// La activa según el historial (aquí se volvió a la 232) y la más alta (233) se conservan; la 231 sale con sus plugins.
    func testToolboxConservaLaActivaYLaMasAlta() throws {
        try toolbox(historial: #"{"history":[{"item":{"build":"233.11799.241"}},{"item":{"build":"232.8660.185"}}]}"#)
        let r = try XCTUnwrap(sobrantesDeToolbox())
        XCTAssertEqual(r.activa, "232.8660.185")
        XCTAssertEqual(r.builds, ["231.9011.34"])
        XCTAssertEqual(Set(r.rutas.map { $0.lastPathComponent }), ["231.9011.34", "231.9011.34.plugins"])

        // Con el IDE de la 231 abierto, no se ofrece.
        let ide = url("\(canal)/231.9011.34").path.lowercased() + "/intellij idea.app/contents/macos/idea"
        XCTAssertNil(sobrantesDeToolbox(procesos: [ide]))

        // El enlace «current» también protege la build a la que apunta.
        try enlazar("\(canal)/current", a: url("\(canal)/231.9011.34"))
        XCTAssertNil(sobrantesDeToolbox())
    }

    /// Sin historial, la activa es la que se usó por última vez; si alguna fecha no se puede leer, no se sabe: nada.
    func testToolboxSinHistorial() throws {
        try toolbox()
        try envejecer("\(canal)/231.9011.34", dias: 30)
        try envejecer("\(canal)/232.8660.185", dias: 1)
        try envejecer("\(canal)/233.11799.241", dias: 10)
        let r = try XCTUnwrap(sobrantesDeToolbox())
        XCTAssertEqual(r.activa, "232.8660.185")
        XCTAssertEqual(r.builds, ["231.9011.34"])
        XCTAssertNil(sobrantesDeToolbox(fecha: { _ in nil }))
    }

    /// Solo si JetBrains sigue instalado: si no, «Restos de apps borradas» ofrece la carpeta entera.
    func testToolboxSoloConJetBrainsInstalado() throws {
        try toolbox(historial: #"{"history":[{"item":{"build":"232.8660.185"}}]}"#)
        XCTAssertTrue(Escaner.versionesIDEsYAgentesToolbox(contexto(), home: casa, abierto: { _ in false }).isEmpty)

        var apps = AppsInstaladas()
        apps.agregarBundleID("com.jetbrains.toolbox", nombre: "JetBrains Toolbox")
        let els = Escaner.versionesIDEsYAgentesToolbox(contexto(apps: apps), home: casa, abierto: { _ in false })
        XCTAssertEqual(els.map { $0.nombre }, ["Versiones anteriores de IDEA-U (Toolbox)"])
        XCTAssertEqual(nombres(els), ["231.9011.34", "231.9011.34.plugins"])
        XCTAssertEqual(els.first?.seleccionado, false)
        XCTAssertEqual(els.first?.riesgo, .seguro)
    }

    // MARK: JDKs

    private func jdk(_ carpeta: String, _ release: String) throws {
        let home = "Library/Java/JavaVirtualMachines/\(carpeta)/Contents/Home"
        try crear("\(home)/release", release)
        try crear("\(home)/bin/java", "binario")
    }

    private func temurin(_ version: String) throws {
        try jdk("temurin-\(version)", """
        IMPLEMENTOR="Eclipse Adoptium"
        IMPLEMENTOR_VERSION="Temurin-\(version)+7"
        JAVA_VERSION="\(version)"
        OS_ARCH="aarch64"
        """)
    }

    /// Del mismo proveedor y versión mayor se conserva el más nuevo; el viejo no sale si está en marcha o lo nombra un ajuste.
    func testJDKRepetido() throws {
        try temurin("17.0.8")
        try temurin("17.0.10")
        try temurin("21.0.1")
        let els = jdks(contexto())
        XCTAssertEqual(nombres(els), ["temurin-17.0.8"])
        let el = try XCTUnwrap(els.first)
        XCTAssertEqual(el.nombre, "Java 17.0.8 (Eclipse Adoptium) repetido")
        XCTAssertEqual(el.riesgo, .revisar)
        XCTAssertFalse(el.seleccionado)
        let patron = url("Library/Java/JavaVirtualMachines/temurin-17.0.8").path.lowercased() + "/"
        XCTAssertEqual(el.enUso, .proceso(nombre: "Java 17.0.8", patron: patron))

        XCTAssertTrue(jdks(contexto(lineas: [patron + "contents/home/bin/java -jar servidor.jar"])).isEmpty)
        try crear(".zshrc", "export JAVA_HOME=$HOME/Library/Java/JavaVirtualMachines/temurin-17.0.8/Contents/Home\n")
        XCTAssertTrue(jdks(contexto()).isEmpty)
    }

    /// «java_home -v 17.0.8» también nombra la versión exacta.
    func testJDKNombradoPorSuVersion() throws {
        try temurin("17.0.8")
        try temurin("17.0.10")
        try crear(".zprofile", "export JAVA_HOME=$(/usr/libexec/java_home -v 17.0.8)\n")
        XCTAssertTrue(jdks(contexto()).isEmpty)
    }

    /// Si un ajuste existe y no se puede leer como texto, no se sabe qué JDK usa: no se ofrece ninguno.
    func testJDKConAjusteIlegible() throws {
        try temurin("17.0.8")
        try temurin("17.0.10")
        try crear(url(".bashrc"), Data([0xC3, 0x28, 0xFF]))
        XCTAssertTrue(jdks(contexto()).isEmpty)
    }

    /// GraalVM y el OpenJDK de Oracle tienen el mismo proveedor, pero uno no sustituye al otro.
    func testJDKDeDistribucionesDistintas() throws {
        try jdk("openjdk-17.0.2", "IMPLEMENTOR=\"Oracle Corporation\"\nJAVA_VERSION=\"17.0.2\"\nOS_ARCH=\"aarch64\"\n")
        try jdk("graalvm-jdk-17.0.9",
                "IMPLEMENTOR=\"Oracle Corporation\"\nJAVA_VERSION=\"17.0.9\"\nOS_ARCH=\"aarch64\"\nGRAALVM_VERSION=\"23.0.1\"\n")
        XCTAssertTrue(jdks(contexto()).isEmpty)
    }

    /// Sin archivo «release», la versión y el proveedor salen del Info.plist del JDK.
    func testJDKSinReleaseUsaElInfoPlist() throws {
        for v in ["11.0.20", "11.0.21"] {
            let base = "Library/Java/JavaVirtualMachines/zulu-\(v).jdk/Contents"
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["JavaVM": ["JVMVersion": v, "JVMVendor": "Azul Systems, Inc."]], format: .xml, options: 0)
            try crear(url("\(base)/Info.plist"), plist)
            try crear("\(base)/Home/bin/java", "binario")
        }
        XCTAssertEqual(nombres(jdks(contexto())), ["zulu-11.0.20.jdk"])
    }

    func testVersionMayorDeJava() {
        XCTAssertEqual(Escaner.versionesIDEsYAgentesMayor("17.0.8"), 17)
        XCTAssertEqual(Escaner.versionesIDEsYAgentesMayor("1.8.0_392"), 8)
        XCTAssertEqual(Escaner.versionesIDEsYAgentesMayor("21"), 21)
        XCTAssertNil(Escaner.versionesIDEsYAgentesMayor("abc"))
    }

    // MARK: Xcode

    /// Solo copias de ~/Applications, y nunca la activa, ni la más alta (con empate, ninguna), ni una en marcha.
    func testCopiasDeXcode() {
        let personal = url("Applications")
        func copia(_ nombre: String, _ version: String) -> (app: URL, real: String, version: String) {
            let app = personal.appendingPathComponent(nombre)
            return (app: app, real: app.path, version: version)
        }
        let xcodes: [(app: URL, real: String, version: String)] = [
            (app: URL(fileURLWithPath: "/Applications/Xcode.app"), real: "/Applications/Xcode.app", version: "16.0"),
            (app: URL(fileURLWithPath: "/Applications/Xcode-14.app"), real: "/Applications/Xcode-14.app", version: "14.3"),
            copia("Xcode-15.4.app", "15.4"), copia("Xcode-15.2.app", "15.2"), copia("Xcode-beta.app", "16.0"),
        ]
        let activa = personal.appendingPathComponent("Xcode-15.4.app").path
        let r = Escaner.versionesIDEsYAgentesXcodesSobrantes(xcodes, activa: activa, carpeta: personal, procesos: [])
        XCTAssertEqual(r.map { $0.app.lastPathComponent }, ["Xcode-15.2.app"])

        let enMarcha = [personal.appendingPathComponent("Xcode-15.2.app").path.lowercased() + "/contents/macos/xcode"]
        XCTAssertTrue(Escaner.versionesIDEsYAgentesXcodesSobrantes(xcodes, activa: activa, carpeta: personal,
                                                                    procesos: enMarcha).isEmpty)
    }

    // MARK: El grupo entero

    /// La entrada del grupo, con lo que tienen abierto los programas de verdad (lsof), sobre la carpeta de prueba.
    func testGrupoEntero() throws {
        try claudeCode()
        try enlazar(".local/bin/claude", a: url(".local/share/claude/versions/2.0.1"))
        let els = Escaner.versionesIDEsYAgentesElementos(contexto(), home: casa)
        XCTAssertEqual(els.map { $0.nombre }, ["Versiones anteriores de Claude Code"])
        XCTAssertEqual(nombres(els), ["2.0.0"])
        XCTAssertTrue(els.allSatisfy { !$0.seleccionado && $0.categoria == .desarrollo && $0.accion == .borrar })
    }
}
