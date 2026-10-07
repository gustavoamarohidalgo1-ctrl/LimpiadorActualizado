import XCTest
@testable import LimpiadorMac

/// Android y simuladores de iOS sobre una carpeta personal de prueba: qué se ofrece, qué se conserva siempre
/// y que, si algo no se puede leer o entender, no se ofrece nada.
final class DetectoresAAndroidYSimuladoresTests: XCTestCase {
    private var raiz: URL!
    private var casa: URL!

    override func setUpWithError() throws {
        raiz = FileManager.default.temporaryDirectory.appendingPathComponent("AndroidYSimuladores-\(UUID().uuidString)")
        casa = raiz.appendingPathComponent("casa")
        try FileManager.default.createDirectory(at: casa, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: raiz)
    }

    // MARK: Ayudantes

    @discardableResult
    private func escribir(_ rel: String, _ texto: String = "x", en base: URL? = nil) throws -> URL {
        let url = (base ?? casa).appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texto.utf8).write(to: url)
        return url
    }

    /// La ruta desde la carpeta personal de prueba (sin depender de si delante sale «/private»).
    private func relativa(_ u: URL) -> String {
        let p = u.path
        guard let r = p.range(of: raiz.lastPathComponent + "/casa/") else { return p }
        return String(p[r.upperBound...])
    }

    private func relativas(_ e: Elemento?) -> Set<String> {
        Set((e?.rutas ?? []).map { relativa($0) })
    }

    /// Un package.xml como los que escribe el SDK Manager (aquí con las dependencias antes de la revisión).
    private func paqueteXML(_ ruta: String, major: Int, minor: Int = 0) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <ns2:repository xmlns:ns2="http://schemas.android.com/repository/android/common/02">
        <license id="android-sdk-license" type="text">Términos y condiciones.</license>
        <localPackage path="\(ruta)" obsolete="false">
        <type-details xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="ns5:genericDetailsType"/>
        <dependencies><dependency path="patcher;v4"><min-revision><major>1</major></min-revision></dependency></dependencies>
        <revision><major>\(major)</major><minor>\(minor)</minor></revision>
        <display-name>Paquete de prueba</display-name>
        </localPackage>
        </ns2:repository>
        """
    }

    /// Un SDK con una imagen del sistema, «emulator» y su copia «emulator-2», y cmdline-tools «latest» (12.0) y «9.0».
    @discardableResult
    private func crearSDK() throws -> URL {
        try escribir("Library/Android/sdk/system-images/android-34/google_apis/arm64-v8a/x")
        try escribir("Library/Android/sdk/emulator/package.xml", paqueteXML("emulator", major: 35, minor: 2))
        try escribir("Library/Android/sdk/emulator/emulator")
        try escribir("Library/Android/sdk/emulator-2/package.xml", paqueteXML("emulator", major: 35, minor: 1))
        try escribir("Library/Android/sdk/emulator-2/emulator")
        try escribir("Library/Android/sdk/cmdline-tools/latest/package.xml", paqueteXML("cmdline-tools;latest", major: 12))
        try escribir("Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager")
        try escribir("Library/Android/sdk/cmdline-tools/9.0/package.xml", paqueteXML("cmdline-tools;9.0", major: 9))
        try escribir("Library/Android/sdk/cmdline-tools/9.0/bin/sdkmanager")
        return casa.appendingPathComponent("Library/Android/sdk")
    }

    private func duplicados(_ sdk: URL, _ procesos: Procesos = Procesos()) -> [Elemento] {
        Escaner.androidYSimuladoresDuplicadosSDK(sdk, home: casa, procesos: procesos)
    }

    // MARK: SDK de Android

    func testRutaDelSDK() throws {
        XCTAssertNil(Escaner.androidYSimuladoresRutaSDK(home: casa, entorno: [:]))
        // Sin ninguna imagen del sistema no se sabe si es un SDK de verdad.
        try escribir("Library/Android/sdk/platforms/android-34/android.jar")
        XCTAssertNil(Escaner.androidYSimuladoresRutaSDK(home: casa, entorno: [:]))

        try crearSDK()
        let deSiempre = try XCTUnwrap(Escaner.androidYSimuladoresRutaSDK(home: casa, entorno: [:]))
        XCTAssertEqual(relativa(deSiempre), "Library/Android/sdk")

        // Una variable que apunta fuera de tu carpeta (aunque sea un SDK) o a algo que no existe no cuenta.
        let fuera = raiz.appendingPathComponent("fuera/sdk")
        try escribir("system-images/android-34/google_apis/arm64-v8a/x", en: fuera)
        let conVariables = try XCTUnwrap(Escaner.androidYSimuladoresRutaSDK(
            home: casa, entorno: ["ANDROID_HOME": fuera.path, "ANDROID_SDK_ROOT": "/no/existe"]))
        XCTAssertEqual(relativa(conVariables), "Library/Android/sdk")

        // La que tiene configurada Android Studio, en su versión más alta, va antes que la de siempre.
        try escribir("otro-sdk/system-images/android-35/default/arm64-v8a/x")
        try escribir("Library/Application Support/Google/AndroidStudio2024.2/options/other.xml",
                     #"<application><component name="PropertiesComponent"><option name="android.sdk.path" value="$USER_HOME$/otro-sdk" /></component></application>"#)
        try escribir("Library/Application Support/Google/AndroidStudio2023.1/options/other.xml",
                     #"<application><component name="PropertiesComponent"><option name="android.sdk.path" value="/no/existe" /></component></application>"#)
        let deStudio = try XCTUnwrap(Escaner.androidYSimuladoresRutaSDK(home: casa, entorno: [:]))
        XCTAssertEqual(relativa(deStudio), "otro-sdk")
        // También con el formato nuevo (JSON dentro de other.xml).
        try escribir("Library/Application Support/Google/AndroidStudio2025.1/options/other.xml",
                     #"<application><component name="PropertyService"><![CDATA[{"keyToString": {"android.sdk.path": "$USER_HOME$/otro-sdk"}}]]></component></application>"#)
        XCTAssertEqual(Escaner.androidYSimuladoresSDKDeAndroidStudio(home: casa), casa.path + "/otro-sdk")
    }

    func testLeerPackageXML() throws {
        let p = try XCTUnwrap(Escaner.androidYSimuladoresPaquete(xml: paqueteXML("cmdline-tools;9.0", major: 9, minor: 1)))
        XCTAssertEqual(p.ruta, "cmdline-tools;9.0")
        let revision = try XCTUnwrap(p.revision)
        XCTAssertTrue(revision == (9, 1, 0), "\(revision)")
        let conMicro = #"<localPackage path="emulator"><revision><major>35</major><minor>2</minor><micro>9</micro></revision></localPackage>"#
        let micro = try XCTUnwrap(Escaner.androidYSimuladoresRevision(xml: conMicro))
        XCTAssertTrue(micro == (35, 2, 9), "\(micro)")
        // Sin major, o con un número que no se entiende, no hay revisión.
        XCTAssertNil(Escaner.androidYSimuladoresRevision(xml: #"<localPackage path="x"><revision><minor>1</minor></revision></localPackage>"#))
        XCTAssertNil(Escaner.androidYSimuladoresRevision(xml: #"<localPackage path="x"><revision><major>1</major><minor>uno</minor></revision></localPackage>"#))
        XCTAssertNil(Escaner.androidYSimuladoresPaquete(xml: "<repository><revision><major>1</major></revision></repository>"))
    }

    func testCopiasYVersionesViejasDelSDK() throws {
        let sdk = try crearSDK()
        // Una copia «-N» de otro paquete no es un duplicado; una carpeta que agrupa paquetes no se compara.
        try escribir("Library/Android/sdk/platform-tools/package.xml", paqueteXML("platform-tools", major: 35))
        try escribir("Library/Android/sdk/platform-tools-2/package.xml", paqueteXML("tools", major: 26))
        try escribir("Library/Android/sdk/build-tools/34.0.0/package.xml", paqueteXML("build-tools;34.0.0", major: 34))
        try escribir("Library/Android/sdk/build-tools-2/x")
        // La copia de «latest» sobra; la misma versión que «latest» no.
        try escribir("Library/Android/sdk/cmdline-tools/latest-2/package.xml", paqueteXML("cmdline-tools;latest", major: 11))
        try escribir("Library/Android/sdk/cmdline-tools/12.0/package.xml", paqueteXML("cmdline-tools;12.0", major: 12))
        // Un enlace nunca se ofrece.
        try FileManager.default.createSymbolicLink(at: sdk.appendingPathComponent("emulator-3"),
                                                   withDestinationURL: sdk.appendingPathComponent("emulator"))

        let r = duplicados(sdk)
        XCTAssertEqual(r.count, 2)
        let copias = try XCTUnwrap(r.first { $0.nombre == "Copias duplicadas de paquetes del SDK de Android" })
        XCTAssertEqual(relativas(copias), ["Library/Android/sdk/emulator-2", "Library/Android/sdk/cmdline-tools/latest-2"])
        XCTAssertEqual(copias.riesgo, .revisar)
        XCTAssertFalse(copias.seleccionado)
        XCTAssertEqual(copias.categoria, .emuladores)
        XCTAssertEqual(copias.accion, .borrar)
        XCTAssertEqual(copias.enUso, .app(nombre: "Android Studio", claves: ["com.google.android.studio"]))

        let viejas = try XCTUnwrap(r.first { $0.nombre == "Versiones viejas de cmdline-tools" })
        XCTAssertEqual(relativas(viejas), ["Library/Android/sdk/cmdline-tools/9.0"])
        XCTAssertEqual(viejas.riesgo, .seguro)
        XCTAssertFalse(viejas.seleccionado)
        XCTAssertEqual(viejas.categoria, .emuladores)

        // Lo que usa Android Studio se conserva siempre.
        let todas = Set(r.flatMap { $0.rutas.map { relativa($0) } })
        for rel in ["emulator", "emulator-3", "cmdline-tools/latest", "cmdline-tools/12.0", "platform-tools",
                    "platform-tools-2", "build-tools-2", "system-images"] {
            XCTAssertFalse(todas.contains("Library/Android/sdk/" + rel), rel)
        }

        // Con el SDK Manager trabajando, nada.
        var procesos = Procesos()
        procesos.lineas = ["/users/ana/library/android/sdk/cmdline-tools/latest/bin/sdkmanager --install emulator"]
        XCTAssertTrue(duplicados(sdk, procesos).isEmpty)
    }

    func testSiUnPackageXMLNoSeLeeNoSeOfreceNadaDelSDK() throws {
        let sdk = try crearSDK()
        XCTAssertEqual(duplicados(sdk).count, 2)

        let original = sdk.appendingPathComponent("emulator/package.xml")
        try FileManager.default.removeItem(at: original)
        XCTAssertTrue(duplicados(sdk).isEmpty, "Sin package.xml no se sabe qué hay en «emulator»")
        try escribir("Library/Android/sdk/emulator/package.xml", "<repository></repository>")
        XCTAssertTrue(duplicados(sdk).isEmpty, "Un package.xml que no dice qué paquete es")
        try escribir("Library/Android/sdk/emulator/package.xml", paqueteXML("emulator", major: 35, minor: 2))
        XCTAssertEqual(duplicados(sdk).count, 2)

        // Ilegible (no es texto): tampoco se ofrece la copia de al lado.
        try Data([0xC3, 0x28, 0xA0, 0xA1]).write(to: sdk.appendingPathComponent("cmdline-tools/9.0/package.xml"))
        XCTAssertTrue(duplicados(sdk).isEmpty)
        try escribir("Library/Android/sdk/cmdline-tools/9.0/package.xml", paqueteXML("cmdline-tools;9.0", major: 9))

        // Sin un «latest» de verdad (aquí sin su sdkmanager) no se sabe cuál es la nueva: solo la copia repetida.
        try FileManager.default.removeItem(at: sdk.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager"))
        let r = duplicados(sdk)
        XCTAssertEqual(r.map(\.nombre), ["Copias duplicadas de paquetes del SDK de Android"])
        XCTAssertEqual(relativas(r.first), ["Library/Android/sdk/emulator-2"])
    }

    // MARK: Emuladores de Android

    func testRestosDeEmuladoresBorrados() throws {
        let avd = casa.appendingPathComponent(".android/avd")
        // Su carpeta ya no está y no hay otra al lado: se ofrece la entrada.
        try escribir(".android/avd/Pixel_Viejo.ini",
                     "avd.ini.encoding=UTF-8\npath=\(avd.path)/Pixel_Viejo.avd\npath.rel=avd/Pixel_Viejo.avd\ntarget=android-34\n")
        // Lo que sigue en el disco se conserva siempre: la carpeta de path=, la de al lado o la de path.rel.
        try escribir(".android/avd/vivo.ini", "path=\(avd.path)/vivo.avd\n")
        try escribir(".android/avd/vivo.avd/config.ini", "abi.type=arm64-v8a\n")
        try escribir("AVDs/otro/config.ini", "abi.type=arm64-v8a\n")
        try escribir(".android/avd/alLado.ini", "path=\(casa.path)/AVDs/alLado.avd\n")
        try escribir(".android/avd/alLado.avd/config.ini", "abi.type=arm64-v8a\n")
        try escribir(".android/avd/renombrado.ini", "path=\(casa.path)/AVDs/no-esta.avd\npath.rel=avd/real.avd\n")
        try escribir(".android/avd/real.avd/config.ini", "abi.type=arm64-v8a\n")
        // Si tampoco está la carpeta de encima (un disco desconectado, otra cuenta), no se sabe: no se ofrece.
        try escribir(".android/avd/externo.ini", "path=/Volumes/Disco-\(UUID().uuidString)/externo.avd\n")
        try escribir(".android/avd/nada.ini", "path=/no/existe\n")

        let r = Escaner.androidYSimuladoresRestosDeEmuladores(home: casa, procesos: Procesos())
        XCTAssertEqual(r.count, 1)
        let restos = try XCTUnwrap(r.first)
        XCTAssertEqual(relativas(restos), [".android/avd/Pixel_Viejo.ini"])
        XCTAssertEqual(restos.nombre, "Restos de emuladores borrados")
        XCTAssertTrue(restos.sinMinimo)
        XCTAssertEqual(restos.riesgo, .seguro)
        XCTAssertFalse(restos.seleccionado)
        XCTAssertEqual(restos.categoria, .emuladores)
        XCTAssertEqual(restos.accion, .borrar)

        // Encendido, no.
        var encendido = Procesos()
        encendido.avds = ["Pixel_Viejo"]
        XCTAssertTrue(Escaner.androidYSimuladoresRestosDeEmuladores(home: casa, procesos: encendido).isEmpty)

        // Un .ini que no dice dónde está su emulador, o que no se puede leer: no se ofrece nada.
        let raro = try escribir(".android/avd/raro.ini", "target=android-34\n")
        XCTAssertTrue(Escaner.androidYSimuladoresRestosDeEmuladores(home: casa, procesos: Procesos()).isEmpty)
        try Data([0xC3, 0x28, 0xA0, 0xA1]).write(to: raro)
        XCTAssertTrue(Escaner.androidYSimuladoresRestosDeEmuladores(home: casa, procesos: Procesos()).isEmpty)
    }

    func testEmuladoresParaIntelEnAppleSilicon() {
        XCTAssertTrue(Escaner.androidYSimuladoresNoArranca(configIni: "abi.type=x86_64\nhw.cpu.arch=x86_64\n", appleSilicon: true))
        XCTAssertTrue(Escaner.androidYSimuladoresNoArranca(configIni: "hw.cpu.arch = x86\r\n", appleSilicon: true))
        XCTAssertFalse(Escaner.androidYSimuladoresNoArranca(configIni: "abi.type=arm64-v8a\nhw.cpu.arch=arm64\n", appleSilicon: true))
        XCTAssertFalse(Escaner.androidYSimuladoresNoArranca(configIni: "abi.type=x86_64\n", appleSilicon: false))
        #if arch(arm64)
        XCTAssertTrue(Escaner.androidYSimuladoresEsAppleSilicon)
        #endif
    }

    // MARK: Simuladores de iOS

    func testCachesDeUnSimulador() throws {
        let udid = UUID().uuidString
        let data = casa.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(udid)/data")
        let app = "Containers/Data/Application/\(UUID().uuidString)"
        let grupo = "Containers/Shared/AppGroup/\(UUID().uuidString)"
        let seOfrecen = ["tmp/descarga.tmp", "Library/Logs/CrashReporter", "\(app)/Library/Caches/imagenes",
                         "\(app)/Library/Caches/Cache.db", "\(app)/tmp/subida.bin", "\(grupo)/Library/Caches/compartida.bin"]
        for rel in ["tmp/descarga.tmp", "Library/Logs/CrashReporter/fallo.ips", "\(app)/Library/Caches/imagenes/1.png",
                    "\(app)/Library/Caches/Cache.db", "\(app)/tmp/subida.bin", "\(grupo)/Library/Caches/compartida.bin",
                    // Lo que se conserva siempre.
                    "Library/Caches/com.apple.containermanagerd/cache.plist", "Library/Preferences/com.apple.Preferences.plist",
                    "\(app)/Documents/notas.txt", "\(app)/Library/Preferences/app.plist",
                    "\(app)/Library/Application Support/datos.sqlite", "\(grupo)/File Provider Storage/archivo.pdf"] {
            try escribir(rel, en: data)
        }
        // Ni una caché que en realidad es un enlace a tus documentos, ni un enlace dentro de una caché.
        let importante = try escribir("Documents/importante.txt")
        let otraApp = data.appendingPathComponent("Containers/Data/Application/\(UUID().uuidString)/Library")
        try FileManager.default.createDirectory(at: otraApp, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: otraApp.appendingPathComponent("Caches"),
                                                   withDestinationURL: casa.appendingPathComponent("Documents"))
        try FileManager.default.createSymbolicLink(at: data.appendingPathComponent("\(app)/tmp/enlace"),
                                                   withDestinationURL: importante)

        let rutas = Escaner.androidYSimuladoresRutasDeCaches(dataPath: data.path).map { u -> String in
            guard let r = u.path.range(of: "/\(udid)/data/") else { return u.path }
            return String(u.path[r.upperBound...])
        }
        XCTAssertEqual(Set(rutas), Set(seOfrecen))
        XCTAssertEqual(rutas.count, seOfrecen.count)
    }

    func testCachesDeSimuladoresApagados() throws {
        let udid = UUID().uuidString
        let data = casa.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(udid)/data")
        try escribir("Containers/Data/Application/\(UUID().uuidString)/Library/Caches/c.bin", en: data)
        try escribir("Containers/Data/Application/\(UUID().uuidString)/Documents/notas.txt", en: data)
        func lista(_ dispositivos: [[String: Any]]) throws -> String {
            let d = try JSONSerialization.data(withJSONObject: ["devices": ["com.apple.CoreSimulator.SimRuntime.iOS-18-0": dispositivos]])
            return String(decoding: d, as: UTF8.self)
        }
        func caches(_ json: String, _ procesos: Procesos = Procesos()) -> [Elemento] {
            Escaner.androidYSimuladoresCachesDeSimuladores(json: json, home: casa, procesos: procesos)
        }
        let apagado: [String: Any] = ["udid": udid, "name": "iPhone 16", "state": "Shutdown", "isAvailable": true,
                                      "dataPath": data.path]
        let soloApagado = try lista([apagado])
        let r = caches(soloApagado)
        XCTAssertEqual(r.count, 1)
        let e = try XCTUnwrap(r.first)
        XCTAssertEqual(e.rutas.count, 1)
        XCTAssertEqual(e.rutas.first?.lastPathComponent, "c.bin")
        XCTAssertEqual(e.riesgo, .seguro)
        XCTAssertTrue(e.seleccionado)
        XCTAssertEqual(e.categoria, .emuladores)
        XCTAssertEqual(e.accion, .borrar)
        XCTAssertEqual(e.enUso, .app(nombre: "Simulator", claves: ["com.apple.iphonesimulator"]))

        // Con Simulator abierto, nada.
        var abierto = Procesos()
        abierto.apps = [Procesos.AppAbierta(nombre: "Simulator", bundleID: "com.apple.iphonesimulator")]
        XCTAssertTrue(caches(soloApagado, abierto).isEmpty)
        // Encendido al empezar el análisis (aunque la lista diga apagado), tampoco.
        var arrancado = Procesos()
        arrancado.simuladores = [udid]
        XCTAssertTrue(caches(soloApagado, arrancado).isEmpty)
        // Si otro simulador se está creando o arrancando, nada de ninguno.
        var creando = apagado
        creando["udid"] = UUID().uuidString
        creando["state"] = "Creating"
        let conUnoCreandose = try lista([apagado, creando])
        XCTAssertTrue(caches(conUnoCreandose).isEmpty)
        // Ni uno encendido, ni uno sin sistema, ni uno fuera de tu carpeta, ni una lista que no se entiende.
        var encendido = apagado
        encendido["state"] = "Booted"
        var sinSistema = apagado
        sinSistema["isAvailable"] = false
        var fuera = apagado
        fuera["dataPath"] = raiz.appendingPathComponent("otro/data").path
        for d in [encendido, sinSistema, fuera] {
            let json = try lista([d])
            XCTAssertTrue(caches(json).isEmpty, "\(d)")
        }
        XCTAssertTrue(caches("no es JSON").isEmpty)
        XCTAssertTrue(caches(#"{"devices": []}"#).isEmpty)
    }
}
