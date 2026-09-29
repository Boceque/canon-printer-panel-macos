import CUPS
import Foundation

/// Tek bir IPP değeri. libcups'tan gelen ham değer Swift türüne çevrilir.
enum IPPDeger: Hashable, Sendable {
    case metin(String)
    case tamsayi(Int)
    case mantiksal(Bool)
    case aralik(Int, Int)
    case cozunurluk(Int, Int)
    case tarih(Date)
    case bilinmeyen(String)

    var metin: String {
        switch self {
        case .metin(let s), .bilinmeyen(let s): return s
        case .tamsayi(let i): return String(i)
        case .mantiksal(let b): return b ? "true" : "false"
        case .aralik(let a, let b): return "\(a)-\(b)"
        case .cozunurluk(let x, let y): return x == y ? "\(x)dpi" : "\(x)x\(y)dpi"
        case .tarih(let d): return ISO8601DateFormatter().string(from: d)
        }
    }

    var tamsayi: Int? {
        switch self {
        case .tamsayi(let i): return i
        case .metin(let s): return Int(s)
        case .mantiksal(let b): return b ? 1 : 0
        default: return nil
        }
    }
}

/// Bir yazıcının ya da bir işin öznitelikleri (ad → değerler).
struct IPPOznitelikler: Sendable {
    var degerler: [String: [IPPDeger]] = [:]

    subscript(_ ad: String) -> [IPPDeger]? { degerler[ad] }

    func metin(_ ad: String) -> String? { degerler[ad]?.first?.metin }
    func metinler(_ ad: String) -> [String] { degerler[ad]?.map(\.metin) ?? [] }
    func tamsayi(_ ad: String) -> Int? { degerler[ad]?.first?.tamsayi }
    func tamsayilar(_ ad: String) -> [Int] { degerler[ad]?.compactMap(\.tamsayi) ?? [] }

    func mantiksal(_ ad: String) -> Bool? {
        guard let d = degerler[ad]?.first else { return nil }
        if case .mantiksal(let b) = d { return b }
        return d.tamsayi.map { $0 != 0 }
    }

    func tarih(_ ad: String) -> Date? {
        guard let d = degerler[ad]?.first else { return nil }
        if case .tarih(let t) = d { return t }
        return nil
    }

    /// CUPS'un "time-at-…" gibi epoch saniyesi tutan tamsayı öznitelikleri için.
    func epochTarih(_ ad: String) -> Date? {
        guard let s = tamsayi(ad), s > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(s))
    }

    var bosMu: Bool { degerler.isEmpty }
}

enum IPPCozucu {
    /// Yanıttaki öznitelikleri gruplarına göre ayırır. Get-Jobs gibi çok kayıtlı yanıtlarda
    /// her kayıt boş adlı ayraçla ayrılır; `grup` verilirse yalnız o gruptakiler alınır.
    static func kayitlar(_ ipp: OpaquePointer, grup: ipp_tag_t) -> [IPPOznitelikler] {
        var sonuc: [IPPOznitelikler] = []
        var gecerli = IPPOznitelikler()
        var attr = ippFirstAttribute(ipp)
        while let a = attr {
            if let adC = ippGetName(a) {
                if ippGetGroupTag(a) == grup {
                    let ad = String(cString: adC)
                    gecerli.degerler[ad] = degerler(a)
                }
            } else if !gecerli.bosMu {
                sonuc.append(gecerli)
                gecerli = IPPOznitelikler()
            }
            attr = ippNextAttribute(ipp)
        }
        if !gecerli.bosMu { sonuc.append(gecerli) }
        return sonuc
    }

    /// Yanıttaki tüm öznitelikleri tek sözlükte toplar (işlem grubu hariç).
    static func tumu(_ ipp: OpaquePointer) -> IPPOznitelikler {
        var o = IPPOznitelikler()
        var attr = ippFirstAttribute(ipp)
        while let a = attr {
            if let adC = ippGetName(a), ippGetGroupTag(a) != IPP_TAG_OPERATION {
                o.degerler[String(cString: adC)] = degerler(a)
            }
            attr = ippNextAttribute(ipp)
        }
        return o
    }

    static func degerler(_ a: OpaquePointer) -> [IPPDeger] {
        let adet = Int(ippGetCount(a))
        let etiket = ippGetValueTag(a)
        var liste: [IPPDeger] = []
        liste.reserveCapacity(adet)
        for i in 0..<adet {
            let e = Int32(i)
            switch etiket {
            case IPP_TAG_INTEGER, IPP_TAG_ENUM:
                liste.append(.tamsayi(Int(ippGetInteger(a, e))))
            case IPP_TAG_BOOLEAN:
                liste.append(.mantiksal(ippGetBoolean(a, e) != 0))
            case IPP_TAG_RANGE:
                var ust: Int32 = 0
                let alt = ippGetRange(a, e, &ust)
                liste.append(.aralik(Int(alt), Int(ust)))
            case IPP_TAG_RESOLUTION:
                var y: Int32 = 0
                var birim = IPP_RES_PER_INCH
                let x = ippGetResolution(a, e, &y, &birim)
                liste.append(.cozunurluk(Int(x), Int(y)))
            case IPP_TAG_DATE:
                if let t = ippGetDate(a, e) {
                    liste.append(.tarih(Date(timeIntervalSince1970: TimeInterval(ippDateToTime(t)))))
                }
            case IPP_TAG_STRING:
                var uzunluk: Int32 = 0
                if let p = ippGetOctetString(a, e, &uzunluk), uzunluk > 0 {
                    let veri = Data(bytes: p, count: Int(uzunluk))
                    liste.append(.metin(String(decoding: veri, as: UTF8.self)))
                } else {
                    liste.append(.metin(""))
                }
            case IPP_TAG_TEXT, IPP_TAG_NAME, IPP_TAG_KEYWORD, IPP_TAG_URI, IPP_TAG_URISCHEME,
                 IPP_TAG_CHARSET, IPP_TAG_LANGUAGE, IPP_TAG_MIMETYPE, IPP_TAG_TEXTLANG, IPP_TAG_NAMELANG:
                if let s = ippGetString(a, e, nil) {
                    liste.append(.metin(String(cString: s)))
                } else {
                    liste.append(.metin(""))
                }
            case IPP_TAG_NOVALUE, IPP_TAG_NOTSETTABLE, IPP_TAG_DELETEATTR, IPP_TAG_ADMINDEFINE, IPP_TAG_UNKNOWN:
                break
            default:
                var tampon = [CChar](repeating: 0, count: 2048)
                ippAttributeString(a, &tampon, tampon.count)
                liste.append(.bilinmeyen(String(cString: tampon)))
            }
        }
        return liste
    }
}

/// C dizge dizisi gerektiren libcups çağrıları için yardımcı.
func cDizgeleriyle<T>(_ dizgeler: [String], _ govde: (UnsafePointer<UnsafePointer<CChar>?>) -> T) -> T {
    let kopyalar = dizgeler.map { strdup($0) }
    defer { kopyalar.forEach { free($0) } }
    let isaretciler: [UnsafePointer<CChar>?] = kopyalar.map { $0.map { UnsafePointer($0) } }
    return isaretciler.withUnsafeBufferPointer { govde($0.baseAddress!) }
}
