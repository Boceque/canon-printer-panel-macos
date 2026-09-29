import Foundation

// MARK: - Yazıcı durumu

enum YaziciDurumKodu: Int, Sendable {
    case bosta = 3, yazdiriyor = 4, durdu = 5, bilinmiyor = 0

    init(_ deger: Int?) { self = YaziciDurumKodu(rawValue: deger ?? 0) ?? .bilinmiyor }

    var ad: String {
        switch self {
        case .bosta: return "Hazır"
        case .yazdiriyor: return "Yazdırıyor"
        case .durdu: return "Durdu"
        case .bilinmiyor: return "Bilinmiyor"
        }
    }
}

enum Onem: Int, Comparable, Sendable {
    case bilgi = 0, uyari = 1, hata = 2
    static func < (a: Onem, b: Onem) -> Bool { a.rawValue < b.rawValue }
}

/// `printer-state-reasons` içindeki tek bir neden (ör. "media-empty-error").
struct DurumNedeni: Hashable, Sendable, Identifiable {
    let ham: String
    var id: String { ham }

    /// Sonundaki -error/-warning/-report eki atılmış anahtar.
    var kok: String {
        for ek in ["-error", "-warning", "-report"] where ham.hasSuffix(ek) {
            return String(ham.dropLast(ek.count))
        }
        return ham
    }

    var onem: Onem {
        if ham.hasSuffix("-error") { return .hata }
        if ham.hasSuffix("-warning") { return .uyari }
        if ham.hasSuffix("-report") { return .bilgi }
        switch kok {
        case "paused", "offline", "stopped", "shutdown", "media-jam", "cover-open", "door-open", "media-empty",
             "cups-missing-filter", "com.apple.print.recoverable":
            return .hata
        case "none": return .bilgi
        default: return .uyari
        }
    }

    /// Canon'a özgü kod (com.canon-10000D-warning → "10000D"). Canon, mesaj anahtarından
    /// ("Error1000_0D") "Error" ve "_" atılarak türetilmiş adı kullanır.
    var canonKodu: String? {
        guard kok.hasPrefix("com.canon-") else { return nil }
        let kod = kok.dropFirst("com.canon-".count)
        return kod.isEmpty ? nil : String(kod)
    }

    var baslik: String {
        if let kod = canonKodu {
            return CanonMetinleri.shared.kisaBaslik(kod: kod) ?? "Canon durum kodu \(kod)"
        }
        return DurumNedeni.ceviriler[kok] ?? kok
    }

    var ayrinti: String? {
        if let kod = canonKodu { return CanonMetinleri.shared.hata(kod: kod) }
        return DurumNedeni.ayrintilar[kok]
    }

    static let ceviriler: [String: String] = [
        "none": "Sorun yok",
        "other": "Diğer bir durum",
        "paused": "Mac'teki kuyruk durduruldu",
        "media-empty": "Kağıt yok",
        "media-needed": "Kağıt gerekiyor",
        "media-low": "Kağıt azaldı",
        "media-jam": "Kağıt sıkıştı",
        "cover-open": "Kapak açık",
        "door-open": "Kapak açık",
        "input-tray-missing": "Kağıt tepsisi takılı değil",
        "output-tray-missing": "Çıkış tepsisi takılı değil",
        "output-area-full": "Çıkış tepsisi dolu",
        "output-area-almost-full": "Çıkış tepsisi dolmak üzere",
        "marker-supply-low": "Mürekkep azaldı",
        "marker-supply-empty": "Mürekkep bitti",
        "marker-waste-almost-full": "Atık mürekkep emici dolmak üzere",
        "marker-waste-full": "Atık mürekkep emici dolu",
        "offline": "Yazıcı çevrimdışı",
        "connecting-to-device": "Yazıcıya bağlanılıyor",
        "timed-out": "Yazıcı yanıt vermedi",
        "stopping": "Durduruluyor",
        "stopped-partly": "Kısmen durdu",
        "shutdown": "Yazıcı kapatılıyor",
        "moving-to-paused": "Duraklatılıyor",
        "spool-area-full": "Bekleme alanı dolu",
        "hold-new-jobs": "Yeni işler bekletiliyor",
        "cups-missing-filter": "Sürücü filtresi bulunamadı",
        "cups-insecure-filter": "Sürücü filtresi güvensiz",
        "cups-waiting-for-job-completed": "Yazıcı işin bitmesini bekliyor",
        "com.apple.print.recoverable": "Geçici hata, yeniden deneniyor",
        "identify-printer-requested": "Yazıcı tanıtılıyor",
        "deactivated": "Yazıcı devre dışı",
        "interpreter-resource-unavailable": "Yazıcı kaynakları yetersiz",
    ]

    static let ayrintilar: [String: String] = [
        "paused": "Yeni işler yazıcıya gönderilmiyor. Yazıcıda sorun yoksa \"Sürdür\" ile devam ettirin.",
        "media-empty": "Arka tepsiye kağıdı düzgün yükleyin ve yazıcıdaki Siyah ya da Renkli (Başlat) düğmesine basın.",
        "media-needed": "Arka tepsiye kağıt koyun.",
        "media-jam": "Sıkışan kağıdı iki elinizle yavaşça çekip çıkarın, ardından yazıcıdaki Siyah ya da Renkli (Başlat) düğmesine basın.",
        "cover-open": "Yazıcının kapağını kapatın.",
        "offline": "Yazıcı kapalı olabilir ya da aynı ağda olmayabilir.",
        "com.apple.print.recoverable": "macOS işi yeniden göndermeyi deniyor. Yazıcı açık ve ağa bağlı mı?",
        "marker-supply-low": "Mürekkep tanklarını gözle kontrol edin. G3010 mürekkep seviyesini ölçmez.",
    ]
}

extension Array where Element == DurumNedeni {
    /// "none" olmayan nedenler.
    var gercekler: [DurumNedeni] { filter { $0.kok != "none" && !$0.ham.isEmpty } }
    var enYuksekOnem: Onem { gercekler.map(\.onem).max() ?? .bilgi }
}

/// Mac'teki CUPS kuyruğunun durumu.
struct KuyrukDurumu: Sendable {
    var durum: YaziciDurumKodu
    var nedenler: [DurumNedeni]
    var mesaj: String
    var isKabulEdiyor: Bool
    var bekleyenIsSayisi: Int
    var degisimZamani: Date?
    var hataPolitikasi: String?
    var isBeklemeVarsayilani: String?
    var aygitAdresi: String
    var model: String
    var bilgi: String
    var ham: IPPOznitelikler

    init(_ o: IPPOznitelikler) {
        durum = YaziciDurumKodu(o.tamsayi("printer-state"))
        nedenler = o.metinler("printer-state-reasons").map(DurumNedeni.init(ham:))
        mesaj = o.metin("printer-state-message") ?? ""
        isKabulEdiyor = o.mantiksal("printer-is-accepting-jobs") ?? true
        bekleyenIsSayisi = o.tamsayi("queued-job-count") ?? 0
        degisimZamani = o.epochTarih("printer-state-change-time")
        hataPolitikasi = o.metin("printer-error-policy")
        isBeklemeVarsayilani = o.metin("job-hold-until-default")
        aygitAdresi = o.metin("device-uri") ?? ""
        model = o.metin("printer-make-and-model") ?? ""
        bilgi = o.metin("printer-info") ?? ""
        ham = o
    }

    /// Kuyruk durdurulmuş mu (kullanıcı ya da hata yüzünden)?
    var durdurulmus: Bool { durum == .durdu || nedenler.contains { $0.kok == "paused" } }
}

/// Yazıcının kendisinden (ağ üzerinden IPP) okunan durum.
struct CihazDurumu: Sendable {
    var durum: YaziciDurumKodu
    var nedenler: [DurumNedeni]
    var uyariMetni: String?
    var firmware: String
    var model: String
    var ad: String
    var aygitKimligi: String
    var uuid: String
    var calismaSuresi: TimeInterval?
    var webAdresi: URL?
    var murekkepSayfasi: URL?
    var dakikadaSayfa: Int?
    var dakikadaRenkliSayfa: Int?
    var tanitmaDestekli: Bool
    var murekkepAdlari: [String]
    var murekkepRenkleri: [String]
    var ham: IPPOznitelikler

    init(_ o: IPPOznitelikler) {
        durum = YaziciDurumKodu(o.tamsayi("printer-state"))
        nedenler = o.metinler("printer-state-reasons").map(DurumNedeni.init(ham:))
        let uyari = o.metin("printer-alert-description") ?? ""
        uyariMetni = (uyari.isEmpty || uyari.lowercased() == "non-alert") ? nil : uyari
        firmware = o.metin("printer-firmware-string-version") ?? ""
        model = o.metin("printer-make-and-model") ?? ""
        ad = o.metin("printer-dns-sd-name") ?? o.metin("printer-info") ?? ""
        aygitKimligi = o.metin("printer-device-id") ?? ""
        uuid = (o.metin("printer-uuid") ?? "").replacingOccurrences(of: "urn:uuid:", with: "")
        calismaSuresi = o.tamsayi("printer-up-time").map(TimeInterval.init)
        webAdresi = o.metin("printer-more-info").flatMap(URL.init(string:))
        murekkepSayfasi = o.metin("printer-supply-info-uri").flatMap(URL.init(string:))
        dakikadaSayfa = o.tamsayi("pages-per-minute")
        dakikadaRenkliSayfa = o.tamsayi("pages-per-minute-color")
        tanitmaDestekli = o.metinler("identify-actions-supported").contains("flash")
        murekkepAdlari = o.metinler("marker-names")
        murekkepRenkleri = o.metinler("marker-colors")
        ham = o
    }

    /// Yazıcı sorun bildiriyor mu?
    var sorunVar: Bool { durum == .durdu || !nedenler.gercekler.filter { $0.onem >= .uyari }.isEmpty || uyariMetni != nil }

    /// device-id içindeki alanlar (MFG, MDL, VER, PSE…).
    var aygitKimligiAlanlari: [String: String] {
        var s: [String: String] = [:]
        for parca in aygitKimligi.split(separator: ";") {
            let p = parca.split(separator: ":", maxSplits: 1)
            if p.count == 2 { s[String(p[0])] = String(p[1]) }
        }
        return s
    }
}

// MARK: - İşler

enum IsDurumu: Int, Sendable {
    case sirada = 3, beklemede = 4, yazdiriliyor = 5, durdu = 6, iptalEdildi = 7, hataIleBitti = 8, tamamlandi = 9
    case bilinmiyor = 0

    init(_ deger: Int?) { self = IsDurumu(rawValue: deger ?? 0) ?? .bilinmiyor }

    var ad: String {
        switch self {
        case .sirada: return "Sırada"
        case .beklemede: return "Beklemede"
        case .yazdiriliyor: return "Yazdırılıyor"
        case .durdu: return "Durdu"
        case .iptalEdildi: return "İptal edildi"
        case .hataIleBitti: return "Hata ile bitti"
        case .tamamlandi: return "Tamamlandı"
        case .bilinmiyor: return "Bilinmiyor"
        }
    }

    var etkin: Bool { rawValue >= 3 && rawValue <= 6 }
}

struct YaziciIsi: Identifiable, Hashable, Sendable {
    let id: Int
    let ad: String
    let sahip: String
    let durum: IsDurumu
    let nedenler: [String]
    let yaziciMesaji: String
    let olusturma: Date?
    let islenme: Date?
    let tamamlanma: Date?
    let boyutKB: Int?
    let basilanSayfa: Int?
    let bekletmeZamani: String?
    let belgeTuru: String?
    let belgeSayisi: Int?
    let kalite: String?
    let ortam: String?
    let griTon: String?
    let cozunurluk: String?
    let kagit: String?
    let sabitlemeIsareti: String?
    /// Mac belgeyi sakladı mı? (false ise yeniden yazdırılamaz; nil = bilinmiyor)
    let belgeSaklandi: Bool?

    init(_ o: IPPOznitelikler) {
        id = o.tamsayi("job-id") ?? 0
        ad = o.metin("job-name") ?? "Adsız iş"
        sahip = o.metin("job-originating-user-name") ?? ""
        durum = IsDurumu(o.tamsayi("job-state"))
        nedenler = o.metinler("job-state-reasons")
        yaziciMesaji = o.metin("job-printer-state-message") ?? ""
        olusturma = o.epochTarih("time-at-creation")
        islenme = o.epochTarih("time-at-processing")
        tamamlanma = o.epochTarih("time-at-completed")
        boyutKB = o.tamsayi("job-k-octets")
        basilanSayfa = o.tamsayi("job-impressions-completed") ?? o.tamsayi("job-media-sheets-completed")
        bekletmeZamani = o.metin("job-hold-until")
        belgeTuru = o.metin("document-format-detected") ?? o.metin("document-format-supplied") ?? o.metin("document-format")
        belgeSayisi = o.tamsayi("number-of-documents")
        kalite = o.metin("CNIJPrintQuality")
        ortam = o.metin("CNIJMediaType")
        griTon = o.metin("CNIJGrayScale")
        cozunurluk = o.metin("Resolution")
        kagit = o.metin("PageSize")
        sabitlemeIsareti = o.metin(Sabitleme.isaretOzniteligi)
        belgeSaklandi = o.mantiksal("job-preserved")
    }

    var komutIsi: Bool { belgeTuru == "application/vnd.cups-command" || sabitlemeIsareti == "komut" }
    var geliyor: Bool { nedenler.contains("job-incoming") }

    /// Kalitenin okunur adı (CNIJPrintQuality değerinden).
    var kaliteAdi: String? { kalite.flatMap { Kalite(pq: $0)?.ad } }
    var griTonMu: Bool { griTon == "1" }

    var nedenMetni: String? {
        let anlamli = nedenler.filter { !["none", "job-printing", "job-queued", "job-completed-successfully",
                                          "processing-to-stop-point", "job-hold-until-specified"].contains($0) }
        guard let ilk = anlamli.first else { return nil }
        return YaziciIsi.nedenCevirileri[ilk] ?? ilk
    }

    static let nedenCevirileri: [String: String] = [
        "job-incoming": "Bilgisayardan geliyor",
        "job-data-insufficient": "Veri eksik",
        "document-format-error": "Belge biçimi okunamadı",
        "job-canceled-by-user": "Kullanıcı iptal etti",
        "job-canceled-at-device": "Yazıcıda iptal edildi",
        "job-canceled-by-operator": "Yönetici iptal etti",
        "aborted-by-system": "Sistem durdurdu",
        "job-completed-with-errors": "Hatalarla tamamlandı",
        "job-completed-with-warnings": "Uyarılarla tamamlandı",
        "printer-stopped": "Kuyruk durduğu için bekliyor",
        "printer-stopped-partly": "Kuyruk kısmen durdu",
        "job-held-for-review": "İnceleme için bekletiliyor",
        "job-hold-until-specified": "Bekletiliyor",
        "resources-are-not-ready": "Yazıcı hazır değil",
        "cups-held-for-authentication": "Kimlik doğrulama bekleniyor",
        "job-transforming": "Hazırlanıyor",
        "job-printing": "Yazdırılıyor",
        "unsupported-document-format": "Desteklenmeyen belge türü",
    ]
}
