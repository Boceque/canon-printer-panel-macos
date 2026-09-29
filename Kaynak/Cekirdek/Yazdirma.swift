import Foundation
import PDFKit

enum SayfaYonu: String, CaseIterable, Codable, Sendable, Identifiable {
    case otomatik, dikey, yatay
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .otomatik: return "Otomatik"
        case .dikey: return "Dikey"
        case .yatay: return "Yatay"
        }
    }
}

enum SayfaKumesi: String, CaseIterable, Codable, Sendable, Identifiable {
    case tumu, tek, cift
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .tumu: return "Tüm sayfalar"
        case .tek: return "Yalnız tek sayfalar"
        case .cift: return "Yalnız çift sayfalar"
        }
    }
}

enum CikisSirasi: String, CaseIterable, Codable, Sendable, Identifiable {
    case yazici, normal, ters
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .yazici: return "Yazıcı varsayılanı"
        case .normal: return "İlk sayfa önce"
        case .ters: return "Son sayfa önce"
        }
    }
}

/// Dosya yazdırırken işe özel seçenekler (baskı kalitesi vb. `BaskiAyarSeti`'nden gelir).
struct YazdirmaSecenekleri: Codable, Hashable, Sendable {
    var kopya = 1
    var harmanla = true
    var sayfaAraligi = ""
    var yon: SayfaYonu = .otomatik
    var sigdir = true
    var yaprakBasinaSayfa = 1
    var sayfaKumesi: SayfaKumesi = .tumu
    var cikisSirasi: CikisSirasi = .yazici

    static let yaprakSecenekleri = [1, 2, 4, 6, 9, 16]

    /// Sayfa aralığı geçerli mi? ("1-3,5,8-10")
    static func aralikGecerli(_ metin: String) -> Bool {
        let t = metin.replacingOccurrences(of: " ", with: "")
        if t.isEmpty { return true }
        guard t.range(of: #"^\d+(-\d+)?(,\d+(-\d+)?)*$"#, options: .regularExpression) != nil else { return false }
        // CUPS yalnız artan ve çakışmasız aralıkları kabul eder: "1-3,5" olur, "3-1" ya da "5,2" olmaz.
        var onceki = 0
        for parca in t.split(separator: ",") {
            let s = parca.split(separator: "-").compactMap { Int($0) }
            guard let alt = s.first, let ust = s.last, alt >= 1, alt <= ust, alt > onceki else { return false }
            onceki = ust
        }
        return true
    }

    func cupsSecenekleri() -> [String: String] {
        var s: [String: String] = [:]
        if kopya > 1 {
            s["copies"] = String(kopya)
            s["multiple-document-handling"] = harmanla ? "separate-documents-collated-copies"
                                                       : "separate-documents-uncollated-copies"
        }
        let aralik = sayfaAraligi.replacingOccurrences(of: " ", with: "")
        if !aralik.isEmpty, YazdirmaSecenekleri.aralikGecerli(aralik) { s["page-ranges"] = aralik }
        switch yon {
        case .otomatik: break
        case .dikey: s["orientation-requested"] = "3"
        case .yatay: s["orientation-requested"] = "4"
        }
        if sigdir {
            s["fit-to-page"] = "true"
            s["print-scaling"] = "fit"
        }
        if yaprakBasinaSayfa > 1 { s["number-up"] = String(yaprakBasinaSayfa) }
        switch sayfaKumesi {
        case .tumu: break
        case .tek: s["page-set"] = "odd"
        case .cift: s["page-set"] = "even"
        }
        switch cikisSirasi {
        case .yazici: break
        case .normal: s["outputorder"] = "normal"
        case .ters: s["outputorder"] = "reverse"
        }
        return s
    }
}

/// G3010 otomatik çift taraf basamaz. Elle çift taraf: önce tek sayfalar, kağıt çevrilir, sonra çiftler.
enum ElleCiftTaraf {
    struct Hazirlik: Sendable {
        let dosya: URL
        let sayfaSayisi: Int
        let bosSayfaEklendi: Bool
    }

    static func sayfaSayisi(_ url: URL) -> Int? {
        guard url.pathExtension.lowercased() == "pdf", let belge = PDFDocument(url: url) else { return nil }
        return belge.pageCount
    }

    /// Basılı yüz sayısı tekse sona boş sayfa(lar) ekler; böylece iki geçişte yaprak sayısı eşit olur.
    /// `yaprakBasinaSayfa` > 1 ise bir yüze birden çok sayfa düştüğü hesaba katılır.
    static func hazirla(_ url: URL, yaprakBasinaSayfa nup: Int = 1) throws -> Hazirlik {
        guard let belge = PDFDocument(url: url) else {
            throw Komut.Hata(aciklama: "PDF açılamadı: \(url.lastPathComponent)")
        }
        let n = belge.pageCount
        let grup = max(1, nup)
        let yuz = (n + grup - 1) / grup
        guard yuz % 2 == 1, let son = belge.page(at: n - 1) else {
            return Hazirlik(dosya: url, sayfaSayisi: n, bosSayfaEklendi: false)
        }
        let eklenecek = grup * yuz + 1 - n
        for i in 0..<eklenecek {
            let bos = PDFPage()
            bos.setBounds(son.bounds(for: .mediaBox), for: .mediaBox)
            belge.insert(bos, at: n + i)
        }
        let hedef = FileManager.default.temporaryDirectory
            .appendingPathComponent("yazici-paneli-\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)")
        guard belge.write(to: hedef) else { throw Komut.Hata(aciklama: "Geçici PDF yazılamadı") }
        return Hazirlik(dosya: hedef, sayfaSayisi: belge.pageCount, bosSayfaEklendi: true)
    }
}

/// Elle çift tarafta 1. adımdan 2. adıma kadar saklanan durum (aynı ayarlarla devam etmek için).
struct ElleCiftTarafOturumu: Sendable {
    let hazirlik: ElleCiftTaraf.Hazirlik
    let ad: String
    let ayarlar: BaskiAyarSeti
    let secenekler: YazdirmaSecenekleri

    static let talimatlar = [
        "Baskı bitince basılan sayfaları çıkış tepsisinden sırasını bozmadan alın.",
        "Desteyi bir kitap sayfası çevirir gibi yan kenarından çevirin: boş yüzler size baksın, sayfaların üst kenarı yine yukarıda kalsın.",
        "Arka tepsiye yerleştirin ve 2. adıma geçin.",
    ]
}

// MARK: - Hazır ayarlar

struct HazirAyar: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var ad: String
    var simge: String
    var aciklama: String
    var ayarlar: BaskiAyarSeti
    var yerlesik: Bool

    static let yerlesikler: [HazirAyar] = [
        HazirAyar(id: UUID(uuidString: "6E6F7461-0000-4000-8000-000000000001")!, ad: "Taslak · Siyah-beyaz",
                  simge: "doc.plaintext", aciklama: "Test ve not çıktıları için en ekonomik günlük ayar.",
                  ayarlar: BaskiAyarSeti(kalite: .taslak, griTon: true, ortam: "0"), yerlesik: true),
        HazirAyar(id: UUID(uuidString: "6E6F7461-0000-4000-8000-000000000002")!, ad: "Taslak · Renkli",
                  simge: "paintpalette", aciklama: "Renkli ama tasarruflu.",
                  ayarlar: BaskiAyarSeti(kalite: .taslak, griTon: false, ortam: "0"), yerlesik: true),
        HazirAyar(id: UUID(uuidString: "6E6F7461-0000-4000-8000-000000000003")!, ad: "Ekstra taslak",
                  simge: "hare", aciklama: "En az mürekkep. Soluk ama okunur; deneme çıktıları için.",
                  ayarlar: BaskiAyarSeti(kalite: .ekstraTaslak, griTon: true, ortam: "0"), yerlesik: true),
        HazirAyar(id: UUID(uuidString: "6E6F7461-0000-4000-8000-000000000004")!, ad: "Standart",
                  simge: "doc.text", aciklama: "Canon'un varsayılanı: renkli, standart kalite.",
                  ayarlar: BaskiAyarSeti(kalite: .standart, griTon: false, ortam: "0"), yerlesik: true),
        HazirAyar(id: UUID(uuidString: "6E6F7461-0000-4000-8000-000000000005")!, ad: "Fotoğraf kağıdı",
                  simge: "photo", aciklama: "Photo Paper Plus Glossy II. Kaliteyi Canon kağıda göre belirler.",
                  ayarlar: BaskiAyarSeti(griTon: false, ortam: "50"), yerlesik: true),
    ]
}

enum HazirAyarDeposu {
    static let dosyaAdi = "hazir-ayarlar.json"

    static func ozeller() -> [HazirAyar] { Depo.oku([HazirAyar].self, dosyaAdi) ?? [] }
    static func kaydet(_ liste: [HazirAyar]) throws { try Depo.yaz(liste.filter { !$0.yerlesik }, dosyaAdi) }
    static func hepsi() -> [HazirAyar] { HazirAyar.yerlesikler + ozeller() }
}
