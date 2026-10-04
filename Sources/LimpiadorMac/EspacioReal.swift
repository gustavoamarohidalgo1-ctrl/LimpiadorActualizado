import Darwin
import Foundation

/// Cuánto espacio se libera de verdad al borrar algo.
///
/// El tamaño en disco no siempre es lo que se recupera:
/// - Un clon de APFS (una copia hecha con el Finder, o lo que instalan pnpm y bun) comparte bloques con el original.
/// - Lo que guarda una instantánea local de Time Machine no se libera hasta que la instantánea desaparece.
/// - Un archivo con varios enlaces duros solo se libera si se borran todos sus nombres.
///
/// APFS dice para cada archivo cuántos bytes son solo suyos (`ATTR_CMNEXT_PRIVATESIZE`).
/// Si se borran todos los clones de un archivo a la vez, se libera algo más de lo calculado:
/// el resultado es «como mínimo».
enum EspacioReal {
    struct Resultado: Sendable {
        /// Lo que se libera al borrarlo todo.
        var liberable: Int64 = 0
        /// Lo que ocupa según el tamaño en disco (lo que muestra el análisis).
        var aparente: Int64 = 0
        var archivos = 0

        /// Lo que se queda ocupado porque lo comparten clones, instantáneas o enlaces que no se borran.
        var compartido: Int64 { max(0, aparente - liberable) }
    }

    private struct Enlace {
        var total: Int
        var vistos = 0
        var privado: Int64
    }

    static func calcular(_ rutas: [String]) -> Resultado {
        // Lo que está dentro de otra ruta de la lista se cuenta una sola vez.
        let todas = Set(rutas)
        let raices = Array(todas.filter { !Rutas.estaDentro($0, de: todas) })

        final class Total: @unchecked Sendable {
            let candado = NSLock()
            var resultado = Resultado()
            var enlaces: [String: Enlace] = [:]
        }
        let total = Total()
        DispatchQueue.concurrentPerform(iterations: raices.count) { i in
            let (r, enlaces) = recorrer(raices[i])
            total.candado.lock()
            total.resultado.liberable += r.liberable
            total.resultado.aparente += r.aparente
            total.resultado.archivos += r.archivos
            for (clave, e) in enlaces {
                if var previo = total.enlaces[clave] {
                    previo.vistos += e.vistos
                    total.enlaces[clave] = previo
                } else {
                    total.enlaces[clave] = e
                }
            }
            total.candado.unlock()
        }
        var r = total.resultado
        // Un archivo con enlaces duros se libera solo si se borran todos sus nombres.
        for e in total.enlaces.values where e.vistos >= e.total { r.liberable += e.privado }
        return r
    }

    private static func recorrer(_ raiz: String) -> (Resultado, [String: Enlace]) {
        var r = Resultado()
        var enlaces: [String: Enlace] = [:]
        guard let raizC = strdup(raiz) else { return (r, enlaces) }
        defer { free(raizC) }
        var argumentos: [UnsafeMutablePointer<CChar>?] = [raizC, nil]
        guard let fts = fts_open(&argumentos, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return (r, enlaces) }
        defer { fts_close(fts) }

        while let e = fts_read(fts) {
            switch Int32(e.pointee.fts_info) {
            case FTS_F:
                let st = e.pointee.fts_statp.pointee
                let bloques = Int64(st.st_blocks) * 512
                let privado = bloques > 0 ? min(bloques, tamanoPrivado(e.pointee.fts_path) ?? bloques) : 0
                r.archivos += 1
                if st.st_nlink > 1 {
                    // Igual que el análisis: cada nombre cuenta su parte.
                    r.aparente += bloques / Int64(st.st_nlink)
                    let clave = "\(st.st_dev):\(st.st_ino)"
                    var en = enlaces[clave] ?? Enlace(total: Int(st.st_nlink), privado: privado)
                    en.vistos += 1
                    enlaces[clave] = en
                } else {
                    r.aparente += bloques
                    r.liberable += privado
                }
            case FTS_DP, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                let b = Int64(e.pointee.fts_statp.pointee.st_blocks) * 512
                r.aparente += b
                r.liberable += b
            default:
                break
            }
        }
        return (r, enlaces)
    }

    /// Bytes del archivo que no comparte con ningún clon ni instantánea. `nil` si el disco no lo sabe (no es APFS).
    static func tamanoPrivado(_ ruta: UnsafePointer<CChar>) -> Int64? {
        var lista = attrlist()
        lista.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        lista.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        // Con FSOPT_ATTR_CMN_EXTENDED, «forkattr» pide atributos comunes extendidos.
        lista.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        // u_int32_t longitud · attribute_set_t devueltos (5 × u_int32_t) · off_t tamaño privado
        var buffer: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0, 0, 0)
        let opciones = UInt32(FSOPT_NOFOLLOW | FSOPT_ATTR_CMN_EXTENDED)
        let estado = withUnsafeMutableBytes(of: &buffer) { b in
            getattrlist(ruta, &lista, b.baseAddress, b.count, opciones)
        }
        guard estado == 0 else { return nil }
        return withUnsafeBytes(of: &buffer) { b -> Int64? in
            let longitud = b.load(fromByteOffset: 0, as: UInt32.self)
            let devueltos = b.load(fromByteOffset: 4 + 16, as: UInt32.self)
            guard longitud >= 32, devueltos & UInt32(ATTR_CMNEXT_PRIVATESIZE) != 0 else { return nil }
            return max(0, b.load(fromByteOffset: 24, as: Int64.self))
        }
    }

    static func tamanoPrivado(de ruta: String) -> Int64? {
        ruta.withCString { tamanoPrivado($0) }
    }
}
