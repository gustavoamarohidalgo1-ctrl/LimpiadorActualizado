import Foundation

/// Android y simuladores de iOS, lo que `emuladores(_:)` no ve: copias repetidas de paquetes del SDK de Android y
/// versiones viejas de cmdline-tools, entradas de Device Manager de emuladores que ya no existen, y las cachés de las
/// apps de los simuladores de iOS apagados (aparte de «vaciar simulador», que lo borra todo).
extension Escaner {
    func detectoresA_AndroidYSimuladores(_ c: Contexto) -> [Elemento] {
        let home = Rutas.home
        var r: [Elemento] = []
        if let sdk = Self.androidYSimuladoresRutaSDK(home: home, entorno: ProcessInfo.processInfo.environment) {
            r += Self.androidYSimuladoresDuplicadosSDK(sdk, home: home, procesos: c.procesos)
        }
        r += Self.androidYSimuladoresRestosDeEmuladores(home: home, procesos: c.procesos)
        // Con Simulator abierto no se ofrece nada de los simuladores: ni se pregunta a simctl, que tarda.
        if c.procesos.appAbierta(Self.androidYSimuladoresClavesSimulator) == nil {
            let lista = Shell.ejecutar("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"], limite: 60)
            if lista.estado == 0 {
                r += Self.androidYSimuladoresCachesDeSimuladores(json: lista.salida, home: home, procesos: c.procesos)
            }
        }
        return r
    }

    static let androidYSimuladoresClavesSimulator = ["com.apple.iphonesimulator"]
    private static let androidYSimuladoresStudio = EnUso.app(nombre: "Android Studio", claves: ["com.google.android.studio"])

    // MARK: SDK de Android

    /// «emulator-2», «latest-3»: donde instala el SDK Manager cuando no puede usar la carpeta de siempre.
    private static let androidYSimuladoresPatronCopia = try! NSRegularExpression(pattern: #"^(.+)-(\d+)$"#)
    /// «9.0», «11.0»: una versión concreta de cmdline-tools.
    private static let androidYSimuladoresPatronVersion = try! NSRegularExpression(pattern: #"^\d+(\.\d+)*$"#)
    /// `<localPackage path="emulator" …>` en el package.xml: qué paquete del SDK hay en esa carpeta.
    private static let androidYSimuladoresPatronPaquete =
        try! NSRegularExpression(pattern: #"<localPackage\b[^>]*?\bpath\s*=\s*["']([^"']+)["']"#)
    /// La ruta del SDK en options/other.xml de Android Studio: `<option name="android.sdk.path" value="…"`,
    /// `<property name="android.sdk.path" value="…"` o `"android.sdk.path": "…"` (el formato nuevo, en JSON).
    private static let androidYSimuladoresPatronSDKDeStudio =
        try! NSRegularExpression(pattern: #"(?:^|")android\.sdk\.path"\s*(?:value\s*=\s*|:\s*)"([^"]*)""#)
    /// Carpetas de la raíz del SDK que agrupan paquetes (o que `emuladores(_:)` ya trata por versión):
    /// una «build-tools-2» no es la copia de ningún paquete.
    private static let androidYSimuladoresContenedoresSDK: Set<String> = [
        "add-ons", "build-tools", "cmake", "cmdline-tools", "extras", "licenses", "ndk", "patcher", "platforms",
        "samples", "skins", "sources", "system-images", "temp",
    ]

    /// La carpeta del SDK de Android, en este orden: ANDROID_HOME, ANDROID_SDK_ROOT, la que tiene configurada Android
    /// Studio (su versión más alta) y la de siempre. Vale la primera que está dentro de `home`, sin enlaces, y tiene
    /// alguna imagen del sistema (así se sabe que es un SDK de verdad); si ninguna, `nil`.
    static func androidYSimuladoresRutaSDK(home: URL, entorno: [String: String]) -> URL? {
        var candidatas: [String] = []
        for variable in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let valor = entorno[variable]?.trimmingCharacters(in: .whitespacesAndNewlines), !valor.isEmpty {
                candidatas.append(valor)
            }
        }
        if let deStudio = androidYSimuladoresSDKDeAndroidStudio(home: home) { candidatas.append(deStudio) }
        candidatas.append(home.appendingPathComponent("Library/Android/sdk").path)
        for ruta in candidatas where ruta.hasPrefix("/") {
            let sdk = URL(fileURLWithPath: ruta).standardizedFileURL
            if androidYSimuladoresSinEnlaces(sdk, desde: home), Rutas.esCarpeta(sdk), androidYSimuladoresTieneImagenes(sdk) {
                return sdk
            }
        }
        return nil
    }

    /// La ruta del SDK que tiene configurada Android Studio en options/other.xml (el de su versión más alta), con
    /// `$USER_HOME$` ya cambiado por la carpeta personal. `nil` si no hay o no se entiende.
    static func androidYSimuladoresSDKDeAndroidStudio(home: URL) -> String? {
        let google = home.appendingPathComponent("Library/Application Support/Google")
        // «AndroidStudio2024.2», «AndroidStudioPreview2024.3»: se compara solo la versión.
        func version(_ n: String) -> String {
            n.replacingOccurrences(of: "AndroidStudioPreview", with: "").replacingOccurrences(of: "AndroidStudio", with: "")
        }
        let carpetas = (androidYSimuladoresNombres(google) ?? []).filter { $0.hasPrefix("AndroidStudio") }
        guard let ultima = carpetas.max(by: { version($0).compare(version($1), options: .numeric) == .orderedAscending }),
              let xml = try? String(contentsOf: google.appendingPathComponent(ultima).appendingPathComponent("options/other.xml"),
                                    encoding: .utf8),
              let valor = androidYSimuladoresGrupos(androidYSimuladoresPatronSDKDeStudio, en: xml)?[1], !valor.isEmpty else {
            return nil
        }
        return valor.replacingOccurrences(of: "$USER_HOME$", with: home.path).replacingOccurrences(of: "\\/", with: "/")
    }

    /// ¿Hay al menos una imagen del sistema (system-images/<versión>/<tipo>/<abi>)?
    static func androidYSimuladoresTieneImagenes(_ sdk: URL) -> Bool {
        let imagenes = sdk.appendingPathComponent("system-images")
        for version in androidYSimuladoresNombres(imagenes) ?? [] {
            let v = imagenes.appendingPathComponent(version)
            for tipo in androidYSimuladoresNombres(v) ?? [] {
                let t = v.appendingPathComponent(tipo)
                if (androidYSimuladoresNombres(t) ?? []).contains(where: { Rutas.esCarpeta(t.appendingPathComponent($0)) }) {
                    return true
                }
            }
        }
        return false
    }

    /// 1. Lo que sobra en el SDK: copias «-N» de un paquete (en la raíz y en cmdline-tools) y versiones de cmdline-tools
    /// más viejas que «latest». build-tools, ndk y platforms no se miran aquí: los trata `emuladores(_:)` por versión.
    /// Si algún package.xml mirado no se puede leer o no dice qué paquete es, no se ofrece nada.
    static func androidYSimuladoresDuplicadosSDK(_ sdk: URL, home: URL, procesos: Procesos) -> [Elemento] {
        // El SDK Manager está instalando o actualizando: el SDK está a medio cambiar.
        guard !procesos.lineas.contains(where: { $0.contains("sdkmanager") }),
              let enRaiz = androidYSimuladoresNombres(sdk) else { return [] }
        let herramientas = sdk.appendingPathComponent("cmdline-tools")
        var enHerramientas: [String] = []
        if Rutas.esCarpeta(herramientas) {
            guard let nombres = androidYSimuladoresNombres(herramientas) else { return [] }
            enHerramientas = nombres
        }

        // a) «emulator-2» junto a «emulator»: si las dos dicen ser el mismo paquete, la del número sobra.
        var copias: [(url: URL, nombre: String)] = []
        for (carpeta, nombres, prefijo) in [(sdk, enRaiz, ""), (herramientas, enHerramientas, "cmdline-tools/")] {
            for nombre in nombres.sorted() where !nombre.hasPrefix(".") {
                guard let g = androidYSimuladoresGrupos(androidYSimuladoresPatronCopia, en: nombre),
                      !(prefijo.isEmpty && androidYSimuladoresContenedoresSDK.contains(g[1])) else { continue }
                let copia = carpeta.appendingPathComponent(nombre)
                let original = carpeta.appendingPathComponent(g[1])
                // Si la de siempre es un enlace (quizá a la propia copia), no se toca.
                guard Rutas.esCarpeta(copia), Rutas.esCarpeta(original),
                      androidYSimuladoresSinEnlaces(original, desde: home) else { continue }
                guard let a = androidYSimuladoresPaquete(en: copia),
                      let b = androidYSimuladoresPaquete(en: original) else { return [] }
                if a.ruta == b.ruta { copias.append((copia, prefijo + nombre)) }
            }
        }

        // b) Versiones de cmdline-tools más viejas que «latest», que es la que usa Android Studio.
        guard let viejas = androidYSimuladoresCmdlineViejas(herramientas, nombres: enHerramientas, home: home) else {
            return []
        }

        var r: [Elemento] = []
        let copiasOfrecidas = copias.filter { androidYSimuladoresOfrecible($0.url, home: home) }
        if !copiasOfrecidas.isEmpty {
            r.append(Elemento(
                nombre: "Copias duplicadas de paquetes del SDK de Android",
                detalle: "Carpetas repetidas del SDK: \(Formato.listaCorta(copiasOfrecidas.map(\.nombre), maximo: 4)).",
                consecuencia: "Android Studio usa la copia sin número; estas quedaron de actualizaciones que no terminaron bien.",
                rutas: copiasOfrecidas.map(\.url), categoria: .emuladores, riesgo: .revisar, seleccionado: false,
                motivos: [.info("square.on.square", "Paquete repetido",
                                "Cada una dice ser el mismo paquete que la carpeta sin número que tiene al lado, que es la que usa Android Studio.")],
                enUso: androidYSimuladoresStudio, dueno: "Android Studio"))
        }
        let viejasOfrecidas = viejas.filter { androidYSimuladoresOfrecible($0.url, home: home) }
        if !viejasOfrecidas.isEmpty {
            r.append(Elemento(
                nombre: "Versiones viejas de cmdline-tools",
                detalle: "Herramientas de línea de comandos del SDK de Android en versiones anteriores a «latest»: \(Formato.listaCorta(viejasOfrecidas.map(\.version), maximo: 4)).",
                consecuencia: "Nada: Android Studio usa «latest». Si algún día necesitas una de estas, el SDK Manager la descarga.",
                rutas: viejasOfrecidas.map(\.url), categoria: .emuladores, riesgo: .seguro, seleccionado: false,
                motivos: [.bien("clock.arrow.circlepath", "Versiones anteriores",
                                "En «latest» tienes una versión más nueva de estas herramientas.")],
                enUso: androidYSimuladoresStudio, dueno: "Android Studio"))
        }
        return r
    }

    /// Las versiones de cmdline-tools («9.0»…) más viejas que «latest». Vacío si no hay un «latest» de verdad (su propia
    /// carpeta, con sdkmanager y una revisión que se entiende) o si alguna revisión no se entiende; `nil` si algún
    /// package.xml no se puede leer o no dice qué paquete es.
    static func androidYSimuladoresCmdlineViejas(_ herramientas: URL, nombres: [String],
                                                 home: URL) -> [(url: URL, version: String)]? {
        let latest = herramientas.appendingPathComponent("latest")
        guard Rutas.esCarpeta(latest) else { return [] }
        guard let actual = androidYSimuladoresPaquete(en: latest) else { return nil }
        guard actual.ruta == "cmdline-tools;latest", let revisionActual = actual.revision,
              androidYSimuladoresSinEnlaces(latest, desde: home),
              Rutas.existe(latest.appendingPathComponent("bin/sdkmanager")) else { return [] }
        var r: [(url: URL, version: String)] = []
        for nombre in nombres where androidYSimuladoresGrupos(androidYSimuladoresPatronVersion, en: nombre) != nil {
            let carpeta = herramientas.appendingPathComponent(nombre)
            guard Rutas.esCarpeta(carpeta) else { continue }
            guard let paquete = androidYSimuladoresPaquete(en: carpeta) else { return nil }
            guard paquete.ruta.hasPrefix("cmdline-tools;") else { continue }
            guard let revision = paquete.revision else { return [] }
            if revision < revisionActual { r.append((carpeta, nombre)) }
        }
        return r.sorted { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
    }

    /// El paquete del SDK que hay en una carpeta, según su package.xml: su ruta («emulator», «cmdline-tools;latest»)
    /// y su revisión, si se entiende. `nil` si no hay package.xml legible o no dice qué paquete es.
    static func androidYSimuladoresPaquete(en carpeta: URL) -> (ruta: String, revision: (Int, Int, Int)?)? {
        guard let xml = try? String(contentsOf: carpeta.appendingPathComponent("package.xml"), encoding: .utf8) else {
            return nil
        }
        return androidYSimuladoresPaquete(xml: xml)
    }

    static func androidYSimuladoresPaquete(xml: String) -> (ruta: String, revision: (Int, Int, Int)?)? {
        guard let ruta = androidYSimuladoresGrupos(androidYSimuladoresPatronPaquete, en: xml)?[1], !ruta.isEmpty else {
            return nil
        }
        return (ruta, androidYSimuladoresRevision(xml: xml))
    }

    /// La `<revision>` de `<localPackage>`: major, minor y micro (las dos últimas, si faltan, cuentan como 0).
    /// `nil` si no hay revisión, no tiene major o algún número no se entiende.
    static func androidYSimuladoresRevision(xml: String) -> (Int, Int, Int)? {
        guard let paquete = xml.range(of: "<localPackage"),
              let cierre = xml.range(of: "</localPackage>", range: paquete.upperBound..<xml.endIndex),
              let inicio = xml.range(of: "<revision>", range: paquete.upperBound..<cierre.lowerBound),
              let fin = xml.range(of: "</revision>", range: inicio.upperBound..<cierre.lowerBound) else { return nil }
        let revision = String(xml[inicio.upperBound..<fin.lowerBound])
        guard revision.contains("<major>"),
              let major = androidYSimuladoresNumero("major", en: revision),
              let minor = androidYSimuladoresNumero("minor", en: revision),
              let micro = androidYSimuladoresNumero("micro", en: revision) else { return nil }
        return (major, minor, micro)
    }

    /// El número que hay en `<etiqueta>…</etiqueta>`: 0 si la etiqueta no está, `nil` si está y no es un número.
    private static func androidYSimuladoresNumero(_ etiqueta: String, en texto: String) -> Int? {
        guard let inicio = texto.range(of: "<\(etiqueta)>") else { return 0 }
        guard let fin = texto.range(of: "</\(etiqueta)>", range: inicio.upperBound..<texto.endIndex) else { return nil }
        return Int(texto[inicio.upperBound..<fin.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Emuladores de Android

    /// 2. Entradas de Device Manager (`~/.android/avd/<nombre>.ini`) de emuladores que ya no existen: su `path=` apunta a
    /// una carpeta que no está, dentro de una que sí está (si tampoco está la de encima, puede ser un disco que no está
    /// conectado), y tampoco está `<nombre>.avd` al lado ni la de `path.rel`. Los `.avd` sin `.ini` ya los ofrece
    /// `emuladores(_:)`. Si algún .ini no se puede leer o no dice dónde está su emulador, no se ofrece nada.
    static func androidYSimuladoresRestosDeEmuladores(home: URL, procesos: Procesos) -> [Elemento] {
        let android = home.appendingPathComponent(".android")
        let avd = android.appendingPathComponent("avd")
        guard Rutas.esCarpeta(avd), let nombres = androidYSimuladoresNombres(avd) else { return [] }
        var restos: [(url: URL, nombre: String)] = []
        for nombre in nombres.sorted() where nombre.hasSuffix(".ini") && !nombre.hasPrefix(".") {
            let ini = avd.appendingPathComponent(nombre)
            guard androidYSimuladoresEsArchivo(ini) else { continue }
            guard let texto = try? String(contentsOf: ini, encoding: .utf8) else { return [] }
            let claves = androidYSimuladoresClaves(texto)
            guard let destino = claves["path"], destino.hasPrefix("/") else { return [] }
            let base = String(nombre.dropLast(4))
            let carpeta = URL(fileURLWithPath: destino).standardizedFileURL
            guard !procesos.avds.contains(base), !Rutas.existeSinSeguir(carpeta.path),
                  Rutas.esCarpeta(carpeta.deletingLastPathComponent()),
                  !Rutas.existeSinSeguir(avd.appendingPathComponent(base + ".avd").path) else { continue }
            if let rel = claves["path.rel"], !rel.isEmpty, Rutas.existeSinSeguir(android.appendingPathComponent(rel).path) {
                continue
            }
            restos.append((ini, base.replacingOccurrences(of: "_", with: " ")))
        }
        let ofrecidos = restos.filter { androidYSimuladoresOfrecible($0.url, home: home) }
        guard !ofrecidos.isEmpty else { return [] }
        let emuladores = ofrecidos.map(\.nombre)
        return [Elemento(
            nombre: "Restos de emuladores borrados",
            detalle: emuladores.count == 1
                ? "La entrada de \(emuladores[0]) en Device Manager: el emulador ya no está en el disco."
                : "Entradas de Device Manager de \(emuladores.count) emuladores que ya no están en el disco: \(Formato.listaCorta(emuladores, maximo: 4)).",
            consecuencia: "Nada: el emulador ya no existe; solo deja una entrada rota en Device Manager.",
            rutas: ofrecidos.map(\.url), categoria: .emuladores, riesgo: .seguro, seleccionado: false,
            motivos: [.bien("xmark.circle.fill", "Emulador inexistente",
                            "Cada archivo apunta a la carpeta de un emulador que ya no está, y no hay otra copia al lado.")],
            enUso: androidYSimuladoresStudio, dueno: "Android Studio", sinMinimo: true)]
    }

    /// «clave=valor», una por línea (los .ini y el config.ini de los emuladores). Si una clave se repite, vale la primera.
    static func androidYSimuladoresClaves(_ texto: String) -> [String: String] {
        var r: [String: String] = [:]
        for linea in texto.split(whereSeparator: \.isNewline) {
            let kv = linea.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, !kv[0].isEmpty, r[kv[0]] == nil else { continue }
            r[kv[0]] = kv[1]
        }
        return r
    }

    /// ¿Es un Mac con Apple silicon? (También lo es si la app corre con Rosetta.)
    static var androidYSimuladoresEsAppleSilicon: Bool {
        var v: Int32 = 0
        var tam = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &v, &tam, nil, 0) == 0 && v == 1
    }

    /// ¿Es un emulador para procesadores Intel (x86 o x86_64), que un Mac con Apple silicon no puede arrancar?
    /// Se decide con su config.ini (`abi.type` y `hw.cpu.arch`), para avisarlo en «Emulador Android: …».
    static func androidYSimuladoresNoArranca(configIni: String, appleSilicon: Bool) -> Bool {
        guard appleSilicon else { return false }
        let claves = androidYSimuladoresClaves(configIni)
        let intel: Set<String> = ["x86", "x86_64"]
        return intel.contains(claves["abi.type"] ?? "") || intel.contains(claves["hw.cpu.arch"] ?? "")
    }

    // MARK: Simuladores de iOS

    /// 3. Cachés y temporales de las apps de los simuladores de iOS apagados, según `xcrun simctl list devices -j`.
    /// Nada si la lista no se entiende, si Simulator está abierto o si algún simulador se está creando, arrancando,
    /// apagando o borrando (CoreSimulator está trabajando). Solo simuladores disponibles, apagados y en tu carpeta.
    static func androidYSimuladoresCachesDeSimuladores(json: String, home: URL, procesos: Procesos) -> [Elemento] {
        guard procesos.appAbierta(androidYSimuladoresClavesSimulator) == nil,
              let datos = json.data(using: .utf8),
              let raiz = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let porRuntime = raiz["devices"] as? [String: [[String: Any]]] else { return [] }
        let dispositivos = porRuntime.values.flatMap { $0 }
        guard dispositivos.allSatisfy({ d in
            let estado = d["state"] as? String
            return estado == "Shutdown" || estado == "Booted"
        }) else { return [] }
        let carpetaDispositivos = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices").standardizedFileURL.path
        var rutas: [URL] = []
        var simuladores = 0
        for d in dispositivos {
            guard (d["isAvailable"] as? Bool) == true, (d["state"] as? String) == "Shutdown",
                  let udid = d["udid"] as? String, !procesos.simuladores.contains(udid),
                  let dataPath = d["dataPath"] as? String, dataPath.hasPrefix("/") else { continue }
            let data = URL(fileURLWithPath: dataPath).standardizedFileURL
            guard data.path.hasPrefix(carpetaDispositivos + "/"), androidYSimuladoresSinEnlaces(data, desde: home),
                  Rutas.esCarpeta(data) else { continue }
            let deEste = androidYSimuladoresRutasDeCaches(dataPath: data.path).filter { androidYSimuladoresOfrecible($0, home: home) }
            guard !deEste.isEmpty else { continue }
            rutas += deEste
            simuladores += 1
        }
        guard !rutas.isEmpty else { return [] }
        return [Elemento(
            nombre: "Cachés de apps en simuladores de iOS",
            detalle: simuladores == 1 ? "Cachés y temporales de las apps de un simulador apagado."
                                      : "Cachés y temporales de las apps de \(simuladores) simuladores apagados.",
            consecuencia: "Las apps de los simuladores los vuelven a crear. Tus simuladores, sus apps y sus datos se quedan.",
            rutas: rutas, categoria: .emuladores, riesgo: .seguro, seleccionado: true,
            motivos: [.bien("arrow.triangle.2.circlepath", "Se regenera",
                            "Solo se vacían las carpetas de caché y temporales de cada app: los datos y ajustes de las apps no se tocan.")],
            enUso: .app(nombre: "Simulator", claves: androidYSimuladoresClavesSimulator), dueno: "Xcode")]
    }

    /// Lo que hay dentro de las carpetas de caché y temporales de un simulador: tmp y Library/Logs del dispositivo,
    /// Library/Caches y tmp de cada app, y Library/Caches de cada grupo de apps. Se ofrece el contenido y no las
    /// carpetas, porque hay apps que escriben en ellas sin crearlas antes. Nunca Library/Caches del dispositivo
    /// (cachés de los servicios del iOS simulado: borrarlas puede dejar apps invisibles), ni Documents, Preferences
    /// o Application Support; y nada a través de un enlace.
    static func androidYSimuladoresRutasDeCaches(dataPath: String) -> [URL] {
        let data = URL(fileURLWithPath: dataPath).standardizedFileURL
        var carpetas = [data.appendingPathComponent("tmp"), data.appendingPathComponent("Library/Logs")]
        let apps = data.appendingPathComponent("Containers/Data/Application")
        for app in (androidYSimuladoresNombres(apps) ?? []).sorted() where !app.hasPrefix(".") {
            carpetas.append(apps.appendingPathComponent(app).appendingPathComponent("Library/Caches"))
            carpetas.append(apps.appendingPathComponent(app).appendingPathComponent("tmp"))
        }
        let grupos = data.appendingPathComponent("Containers/Shared/AppGroup")
        for grupo in (androidYSimuladoresNombres(grupos) ?? []).sorted() where !grupo.hasPrefix(".") {
            carpetas.append(grupos.appendingPathComponent(grupo).appendingPathComponent("Library/Caches"))
        }
        var r: [URL] = []
        for carpeta in carpetas where androidYSimuladoresSinEnlaces(carpeta, desde: data) {
            for nombre in (androidYSimuladoresNombres(carpeta) ?? []).sorted() {
                let u = carpeta.appendingPathComponent(nombre)
                if androidYSimuladoresSinEnlaces(u, desde: data) { r.append(u) }
            }
        }
        return r
    }

    // MARK: Utilidades

    /// Los nombres de lo que hay en una carpeta, o `nil` si no se puede leer (o no es una carpeta).
    static func androidYSimuladoresNombres(_ carpeta: URL) -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)
    }

    /// Los grupos de la primera coincidencia de `patron` en `texto` (el 0 es la coincidencia entera); `nil` si no hay.
    static func androidYSimuladoresGrupos(_ patron: NSRegularExpression, en texto: String) -> [String]? {
        guard let m = patron.firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: texto).map { String(texto[$0]) } ?? "" }
    }

    /// ¿`u` está dentro de `base`, existe, y ni ella ni ninguna carpeta entre las dos es un enlace?
    /// (Si lo fuera, borrar «aquí» podría borrar algo de otro sitio.)
    static func androidYSimuladoresSinEnlaces(_ u: URL, desde base: URL) -> Bool {
        let b = base.standardizedFileURL.path
        let p = u.standardizedFileURL.path
        guard b.count > 1, p.hasPrefix(b + "/") else { return false }
        var actual = b
        for parte in p.dropFirst(b.count + 1).split(separator: "/") {
            actual += "/" + String(parte)
            var st = stat()
            guard lstat(actual, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK else { return false }
        }
        return true
    }

    /// ¿Es un archivo normal (ni carpeta ni enlace)?
    static func androidYSimuladoresEsArchivo(_ u: URL) -> Bool {
        var st = stat()
        return lstat(u.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG
    }

    /// Lo que se ofrece: existe, está dentro de `home` sin enlaces por medio y se puede mover a la Papelera.
    static func androidYSimuladoresOfrecible(_ u: URL, home: URL) -> Bool {
        androidYSimuladoresSinEnlaces(u, desde: home) && Escaner.sePuedeQuitar(u, admin: false)
    }
}
