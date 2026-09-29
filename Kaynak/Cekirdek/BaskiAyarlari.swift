import Foundation

/// Baskı kalitesi. Değerler Canon'un kendi yazdırma penceresinin gönderdikleriyle eşlenir:
/// pencerede "Taslak" seçilince giden iş CNIJPrintQuality=15 + 300 dpi taşır (kanıtlı);
/// 20 ise "Özel" kaydırıcının en solu.
enum Kalite: String, CaseIterable, Codable, Sendable, Identifiable {
    case ekstraTaslak, taslak, standart, yuksek, enYuksek

    var id: String { rawValue }

    init?(pq: String) {
        switch pq {
        case "20": self = .ekstraTaslak
        case "15": self = .taslak
        case "10": self = .standart
        case "5": self = .yuksek
        case "0": self = .enYuksek
        default: return nil
        }
    }

    var ad: String {
        switch self {
        case .ekstraTaslak: return "Ekstra taslak"
        case .taslak: return "Taslak"
        case .standart: return "Standart"
        case .yuksek: return "Yüksek"
        case .enYuksek: return "En yüksek"
        }
    }

    var aciklama: String {
        switch self {
        case .ekstraTaslak: return "En az mürekkep, en hızlı. Yazılar okunur, gri alanlar soluk çıkar."
        case .taslak: return "Canon'un \"Taslak\" ayarı. Test, not ve deneme baskıları için; mürekkep tasarrufu."
        case .standart: return "Canon'un varsayılanı. Günlük belgeler için."
        case .yuksek: return "Daha keskin, daha yavaş, daha çok mürekkep."
        case .enYuksek: return "En keskin baskı. Çok yavaş, en çok mürekkep."
        }
    }

    /// Canon penceresindeki karşılığı.
    var canonKarsiligi: String {
        switch self {
        case .ekstraTaslak: return "Özel → kaydırıcı en solda (Taslak)"
        case .taslak: return "Baskı Kalitesi: Taslak"
        case .standart: return "Baskı Kalitesi: Standart"
        case .yuksek: return "Özel → İnce"
        case .enYuksek: return "Özel → Süper İnce"
        }
    }

    var pq: String {
        switch self {
        case .ekstraTaslak: return "20"
        case .taslak: return "15"
        case .standart: return "10"
        case .yuksek: return "5"
        case .enYuksek: return "0"
        }
    }

    /// Canon penceresinin "Baskı Kalitesi" radyo düğmesi (5 = Özel).
    var baskiModu: String {
        switch self {
        case .ekstraTaslak: return "5"
        case .taslak: return "3"
        case .standart: return "2"
        case .yuksek: return "5"
        case .enYuksek: return "5"
        }
    }

    var kaydirici: String {
        switch self {
        case .ekstraTaslak: return "1"
        case .taslak: return "2"
        case .standart: return "3"
        case .yuksek: return "4"
        case .enYuksek: return "5"
        }
    }

    var dpi: Int { self == .ekstraTaslak || self == .taslak ? 300 : 600 }

    /// 0…1 arası göreli mürekkep kullanımı (arayüzde çubuk için).
    var murekkepOrani: Double {
        switch self {
        case .ekstraTaslak: return 0.2
        case .taslak: return 0.4
        case .standart: return 0.6
        case .yuksek: return 0.8
        case .enYuksek: return 1.0
        }
    }

    var simge: String {
        switch self {
        case .ekstraTaslak: return "hare"
        case .taslak: return "doc.plaintext"
        case .standart: return "doc.text"
        case .yuksek: return "doc.richtext"
        case .enYuksek: return "sparkles"
        }
    }
}

enum YariTon: String, CaseIterable, Codable, Sendable, Identifiable {
    case dagilma, titreme
    var id: String { rawValue }

    var ad: String { self == .dagilma ? "Dağılma" : "Titreme" }
    var aciklama: String {
        self == .dagilma ? "Canon'un varsayılanı; fotoğraf ve geçişlerde yumuşak sonuç."
                         : "Düzenli nokta deseni; grafik ve çizimlerde daha net kenar."
    }
    var desen: String { self == .dagilma ? "2595" : "2560" }
    var radyo: String { self == .dagilma ? "2" : "1" }
}

enum Parlaklik: String, CaseIterable, Codable, Sendable, Identifiable {
    case acik = "14", normal = "18", koyu = "22"
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .acik: return "Açık"
        case .normal: return "Normal"
        case .koyu: return "Koyu"
        }
    }
}

/// Anlamsal baskı ayarları. `nil` alan = "bu ayara dokunma".
struct BaskiAyarSeti: Codable, Hashable, Sendable {
    var kalite: Kalite?
    var griTon: Bool?
    var ortam: String?       // CNIJMediaType kodu ("0" = düz kağıt)
    var kagit: String?       // PageSize kodu ("A4", "A4.FullBleed"…)
    var parlaklik: Parlaklik?
    var yariTon: YariTon?

    init(kalite: Kalite? = nil, griTon: Bool? = nil, ortam: String? = nil, kagit: String? = nil,
         parlaklik: Parlaklik? = nil, yariTon: YariTon? = nil) {
        self.kalite = kalite
        self.griTon = griTon
        self.ortam = ortam
        self.kagit = kagit
        self.parlaklik = parlaklik
        self.yariTon = yariTon
    }

    var bos: Bool { kalite == nil && griTon == nil && ortam == nil && kagit == nil && parlaklik == nil && yariTon == nil }

    /// Sabitlemenin dokunabileceği tüm PPD anahtarları (yedekleme ve geri yükleme için).
    static let tumPPDAnahtarlari = [
        "CNIJPrintQuality", "CNIJPrintMode2", "CNIJPQualitySlider", "Resolution",
        "CNIJGrayScale", "CNIJGrayScaleCheckBox", "CNIJMediaType", "PageSize", "PageRegion",
        "CNIJGamma2", "CNIJDitherPattern", "CNIJHalfToneRadio",
    ]
    /// Yalnız yazdırma penceresinin (Canon paneli) sakladığı ek anahtarlar.
    static let pencereEkAnahtarlari = ["CNIJPrintMode"]
    static let kaliteAnahtarlari: Set<String> = ["CNIJPrintQuality", "CNIJPrintMode2", "CNIJPQualitySlider",
                                                 "CNIJPrintMode", "Resolution", "printer-resolution"]

    /// Dolu alanların dokunduğu PPD anahtarları (kalite uygulanabilir olsun ya da olmasın).
    var ppdAnahtarlari: Set<String> {
        var s = Set<String>()
        if kalite != nil { s.formUnion(["CNIJPrintQuality", "CNIJPrintMode2", "CNIJPQualitySlider", "Resolution"]) }
        if griTon != nil { s.formUnion(["CNIJGrayScale", "CNIJGrayScaleCheckBox"]) }
        if ortam != nil { s.insert("CNIJMediaType") }
        if kagit != nil { s.formUnion(["PageSize", "PageRegion"]) }
        if parlaklik != nil { s.insert("CNIJGamma2") }
        if yariTon != nil { s.formUnion(["CNIJDitherPattern", "CNIJHalfToneRadio"]) }
        return s
    }

    /// Yazdırma penceresinde dokunulan anahtarlar (Canon panelinin ek "CNIJPrintMode" anahtarı dahil).
    var pencereAnahtarlari: Set<String> {
        var s = ppdAnahtarlari
        if kalite != nil { s.insert("CNIJPrintMode") }
        return s
    }

    /// Düz kağıt dışındaki ortamlarda kaliteyi Canon penceresi belirler; geçersiz kombinasyon
    /// yazıcıda 4103 hatası verir. Bu yüzden kalite yalnız düz kağıtta (ya da ortam belirsizken) yazılır.
    var kaliteUygulanabilir: Bool { kalite != nil && (ortam == nil || ortam == "0") }

    /// PPD varsayılanlarına yazılacak anahtar/değerler. `katalog` verilirse PPD'de olmayanlar atılır.
    func ppdSecenekleri(katalog: PPDKatalogu? = nil) -> [String: String] {
        var s: [String: String] = [:]
        if let kalite, kaliteUygulanabilir {
            s["CNIJPrintQuality"] = kalite.pq
            s["CNIJPrintMode2"] = kalite.baskiModu
            s["CNIJPQualitySlider"] = kalite.kaydirici
            s["Resolution"] = "\(kalite.dpi)x\(kalite.dpi)dpi"
        }
        if let griTon {
            s["CNIJGrayScale"] = griTon ? "1" : "0"
            s["CNIJGrayScaleCheckBox"] = griTon ? "1" : "0"
        }
        if let ortam { s["CNIJMediaType"] = ortam }
        if let kagit {
            s["PageSize"] = kagit
            s["PageRegion"] = kagit
        }
        if let parlaklik { s["CNIJGamma2"] = parlaklik.rawValue }
        if let yariTon {
            s["CNIJDitherPattern"] = yariTon.desen
            s["CNIJHalfToneRadio"] = yariTon.radyo
        }
        if let katalog {
            s = s.filter { anahtar, deger in
                guard let secenek = katalog[anahtar] else { return false }
                return secenek.secim(deger) != nil
            }
        }
        return s
    }

    /// macOS yazdırma penceresinin "Son Kullanılan Ayarlar"ına yazılacaklar.
    func pencereSecenekleri(katalog: PPDKatalogu? = nil) -> [String: String] {
        var s = ppdSecenekleri(katalog: katalog)
        if let m = s["CNIJPrintMode2"] { s["CNIJPrintMode"] = m }
        return s
    }

    /// Tek bir işe (Set-Job-Attributes / lp -o) uygulanacaklar.
    func isSecenekleri(katalog: PPDKatalogu? = nil) -> [String: String] {
        var s = ppdSecenekleri(katalog: katalog)
        if let kalite, kaliteUygulanabilir { s["printer-resolution"] = "\(kalite.dpi)dpi" }
        s.removeValue(forKey: "PageRegion")
        return s
    }

    /// Diğer setin dolu alanlarını bunun üstüne yazar.
    func birlestir(_ ust: BaskiAyarSeti) -> BaskiAyarSeti {
        BaskiAyarSeti(kalite: ust.kalite ?? kalite, griTon: ust.griTon ?? griTon, ortam: ust.ortam ?? ortam,
                      kagit: ust.kagit ?? kagit, parlaklik: ust.parlaklik ?? parlaklik, yariTon: ust.yariTon ?? yariTon)
    }

    /// PPD varsayılanlarından (yazıcının şu anki varsayılanları) anlamsal set üretir.
    static func varsayilanlardan(_ katalog: PPDKatalogu) -> BaskiAyarSeti {
        BaskiAyarSeti(
            kalite: katalog.varsayilan("CNIJPrintQuality").flatMap { Kalite(pq: $0) },
            griTon: katalog.varsayilan("CNIJGrayScale").map { $0 == "1" },
            ortam: katalog.varsayilan("CNIJMediaType"),
            kagit: katalog.varsayilan("PageSize"),
            parlaklik: katalog.varsayilan("CNIJGamma2").flatMap { Parlaklik(rawValue: $0) },
            yariTon: katalog.varsayilan("CNIJDitherPattern").map { $0 == "2560" ? .titreme : .dagilma }
        )
    }

    /// Kısa özet: "Taslak · Siyah-beyaz · A4".
    func ozet(katalog: PPDKatalogu? = nil) -> String {
        var p: [String] = []
        if let kalite { p.append(kalite.ad) }
        if let griTon { p.append(griTon ? "Siyah-beyaz" : "Renkli") }
        if let ortam { p.append(BaskiAyarSeti.ortamAdi(ortam, katalog: katalog)) }
        if let kagit { p.append(BaskiAyarSeti.kagitAdi(kagit, katalog: katalog)) }
        if let parlaklik, parlaklik != .normal { p.append("Parlaklık: \(parlaklik.ad)") }
        if let yariTon, yariTon != .dagilma { p.append(yariTon.ad) }
        return p.isEmpty ? "Ayar yok" : p.joined(separator: " · ")
    }

    static func ortamAdi(_ kod: String, katalog: PPDKatalogu?) -> String {
        katalog?["CNIJMediaType"]?.secim(kod)?.ad ?? (kod == "0" ? "Düz Kağıt" : "Ortam \(kod)")
    }

    static func kagitAdi(_ kod: String, katalog: PPDKatalogu?) -> String {
        katalog?["PageSize"]?.secim(kod)?.ad ?? kod
    }
}
