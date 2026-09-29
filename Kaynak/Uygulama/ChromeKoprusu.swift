import Foundation

/// Chrome eklentisi ile uygulama arasındaki native messaging köprüsü.
/// Chrome programı `chrome-extension://<kimlik>/` argümanıyla başlatır; stdin'den 4 bayt uzunluk + JSON
/// okunur, aynı biçimde tek yanıt yazılır ve program çıkar. Bu kipte stdout'a başka hiçbir şey yazılmamalı.
enum ChromeKoprusu {
    static let hostAdi = "com.caglar.yazicipaneli"
    static let eklentiKimligi = "abohnodngchkppmelngdcbidgpfocfho"
    static let yaziciKimligi = "yazici-paneli-canon"

    // MARK: - Kurulum (NativeMessagingHosts manifest'i)

    /// Chromium tabanlı tarayıcıların kullanıcı klasörleri (yalnız var olanlara yazılır).
    private static let tarayicilar = ["Google/Chrome", "Google/Chrome Beta", "Google/Chrome Canary", "Chromium",
                                      "BraveSoftware/Brave-Browser", "Microsoft Edge"]

    private static var destekKlasoru: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    static var chromeManifestYolu: URL {
        destekKlasoru.appendingPathComponent("Google/Chrome/NativeMessagingHosts/\(hostAdi).json")
    }

    /// Eklentinin Chrome'a yükleneceği klasör. Masaüstü gibi korumalı klasörler yerine burası kullanılır:
    /// Chrome her açılışta eklentiyi okur, Masaüstü'nde macOS izin isteyebilir.
    static var eklentiKlasoru: URL { Depo.klasor.appendingPathComponent("Chrome Eklentisi", isDirectory: true) }

    /// Köprü manifest'ini yazar ve eklenti dosyalarını kurulum klasörüne kopyalar. Kurulan tarayıcı sayısını döndürür.
    @discardableResult
    static func kur() -> Int {
        guard let program = GorevliYoneticisi.program else { return 0 }
        let manifest: [String: Any] = [
            "name": hostAdi,
            "description": "Yazıcı Paneli — Canon G3010 köprüsü",
            "path": program,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(eklentiKimligi)/"],
        ]
        guard let veri = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else { return 0 }
        var sayi = 0
        for t in tarayicilar {
            let kok = destekKlasoru.appendingPathComponent(t, isDirectory: true)
            guard FileManager.default.fileExists(atPath: kok.path) else { continue }
            let klasor = kok.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            let hedef = klasor.appendingPathComponent("\(hostAdi).json")
            if (try? Data(contentsOf: hedef)) == veri { sayi += 1; continue }
            do {
                try FileManager.default.createDirectory(at: klasor, withIntermediateDirectories: true)
                try veri.write(to: hedef, options: .atomic)
                sayi += 1
            } catch {
                Gunluk.yaz("Chrome köprüsü kurulamadı (\(t)): \(error.localizedDescription)")
            }
        }
        if eklentiyiKopyala(program: program) {
            // Chrome paketlenmemiş eklentinin arka planını diskten kendiliğinden yenilemez: işaret bırak,
            // Tercihler "Chrome'da yeniden yükleyin" desin (derle.sh de bu dosyanın değişmesine bakar).
            try? Depo.yaz(EklentiGuncellemesi(tarih: Date(), onaylandi: false), guncellemeDosyasi)
        }
        return sayi
    }

    static var kurulu: Bool {
        guard let veri = try? Data(contentsOf: chromeManifestYolu),
              let j = try? JSONSerialization.jsonObject(with: veri) as? [String: Any],
              let yol = j["path"] as? String else { return false }
        return FileManager.default.isExecutableFile(atPath: yol)
    }

    /// Chrome profillerindeki bu eklentiye ait kayıtlar (Secure Preferences / Preferences; salt okunur).
    private static func eklentiKayitlari() -> [[String: Any]] {
        let chrome = destekKlasoru.appendingPathComponent("Google/Chrome", isDirectory: true)
        guard let profiller = try? FileManager.default.contentsOfDirectory(atPath: chrome.path) else { return [] }
        var sonuc: [[String: Any]] = []
        for p in profiller where p == "Default" || p.hasPrefix("Profile ") {
            for dosya in ["Secure Preferences", "Preferences"] {
                let url = chrome.appendingPathComponent(p).appendingPathComponent(dosya)
                guard let veri = try? Data(contentsOf: url),
                      let j = try? JSONSerialization.jsonObject(with: veri) as? [String: Any],
                      let ayarlar = (j["extensions"] as? [String: Any])?["settings"] as? [String: Any],
                      let e = ayarlar[eklentiKimligi] as? [String: Any],
                      e["location"] != nil || e["path"] != nil else { continue }   // yarım kayıt değil, kurulu eklenti
                sonuc.append(e)
            }
        }
        return sonuc
    }

    /// Kayıttaki eklenti etkin mi? Güncel Chrome `disable_reasons` listesi tutar (boş = etkin);
    /// eski Chrome bit maskesi (0 = etkin) ya da daha eskisi `state` (0 = devre dışı) yazar.
    private static func etkinMi(_ e: [String: Any]) -> Bool {
        if let l = e["disable_reasons"] as? [Any] { return l.isEmpty }
        if let n = e["disable_reasons"] as? Int { return n == 0 }
        return (e["state"] as? Int) != 0
    }

    /// Eklenti Chrome'a yüklü ve etkin mi? (Başka profilde etkin bir kopya da sayılır.)
    static var eklentiYuklu: Bool { eklentiKayitlari().contains(where: etkinMi) }

    // MARK: - Eklenti güncellemesi (Chrome'da ↻ gerekir)

    /// `kur()` eklenti dosyalarını değiştirdiğinde yazılır.
    private struct EklentiGuncellemesi: Codable {
        var tarih: Date
        /// Kullanıcı "Yeniden yükledim" dedi.
        var onaylandi: Bool
    }

    private static let guncellemeDosyasi = "chrome-eklenti-guncelleme.json"

    /// Chrome zamanı: 1601-01-01'den bu yana mikrosaniye (metin ya da sayı).
    private static func chromeZamani(_ deger: Any?) -> Date? {
        let mikro: Double?
        if let s = deger as? String { mikro = Double(s) } else { mikro = (deger as? NSNumber)?.doubleValue }
        guard let m = mikro, m > 0 else { return nil }
        return Date(timeIntervalSince1970: m / 1_000_000 - 11_644_473_600)
    }

    /// Eklenti dosyaları güncellendi ama Chrome eklentiyi o günden beri yeniden yüklemedi mi?
    /// Chrome ↻ ile yeniden yükleyince kaydın `last_update_time` alanını yeniler. Bu alan okunamazsa
    /// uyarı kullanıcı "Yeniden yükledim" diyene dek sürer.
    static var eklentiYenidenYuklenmeli: Bool {
        guard let g = Depo.oku(EklentiGuncellemesi.self, guncellemeDosyasi), !g.onaylandi else { return false }
        let etkinler = eklentiKayitlari().filter(etkinMi)
        guard !etkinler.isEmpty else { return false }   // yüklü değil: ilk yüklemede zaten yeni dosyalar okunur
        guard let son = etkinler.compactMap({ chromeZamani($0["last_update_time"] ?? $0["install_time"]) }).max() else {
            return true
        }
        return son < g.tarih
    }

    static func eklentiGuncellemesiniOnayla() {
        guard var g = Depo.oku(EklentiGuncellemesi.self, guncellemeDosyasi), !g.onaylandi else { return }
        g.onaylandi = true
        try? Depo.yaz(g, guncellemeDosyasi)
    }

    /// Köprü programının paketindeki eklenti dosyalarını kurulum klasörüne kopyalar (değişenleri günceller).
    /// Kaynak, köprü manifest'indeki programın paketidir: böylece köprü ile eklenti hep aynı kopyadan gelir
    /// (/Applications dışındaki bir deneme kopyası kurulu eklentiyi sessizce değiştirmez).
    /// Bir dosya değiştiyse `true` döner.
    private static func eklentiyiKopyala(program: String) -> Bool {
        let kaynak = URL(fileURLWithPath: program).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Chrome Eklentisi", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: kaynak.path) else { return false }
        try? fm.createDirectory(at: eklentiKlasoru, withIntermediateDirectories: true)
        guard let numaralandirici = fm.enumerator(at: kaynak, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
        var degisti = false
        for case let url as URL in numaralandirici {
            let goreli = url.path.replacingOccurrences(of: kaynak.path + "/", with: "")
            if goreli.hasPrefix("test") || goreli.hasSuffix(".DS_Store") { continue }
            let hedef = eklentiKlasoru.appendingPathComponent(goreli)
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try? fm.createDirectory(at: hedef, withIntermediateDirectories: true)
            } else if (try? Data(contentsOf: hedef)) != (try? Data(contentsOf: url)) {
                try? fm.removeItem(at: hedef)   // yalnız bizim kopyamız: bir önceki sürümün aynı dosyası
                if (try? fm.copyItem(at: url, to: hedef)) != nil { degisti = true }
            }
        }
        return degisti
    }

    // MARK: - Çalıştırma (native messaging)

    static func calistir() -> Never {
        let yanit: [String: Any]
        if let istek = oku() {
            do {
                yanit = try isle(istek)
            } catch {
                yanit = ["tamam": false, "hata": error.localizedDescription]
            }
        } else {
            yanit = ["tamam": false, "hata": "İstek okunamadı"]
        }
        yaz(yanit)
        exit(0)
    }

    private static func tamOku(_ n: Int) -> Data? {
        var veri = Data()
        while veri.count < n {
            let parca = FileHandle.standardInput.readData(ofLength: n - veri.count)
            if parca.isEmpty { return nil }
            veri.append(parca)
        }
        return veri
    }

    private static func oku() -> [String: Any]? {
        guard let bas = tamOku(4) else { return nil }
        let uzunluk = bas.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard uzunluk > 0, uzunluk < 256 * 1024 * 1024, let govde = tamOku(uzunluk) else { return nil }
        return (try? JSONSerialization.jsonObject(with: govde)) as? [String: Any]
    }

    private static func yaz(_ yanit: [String: Any]) {
        var veri = (try? JSONSerialization.data(withJSONObject: yanit)) ?? Data(#"{"tamam":false,"hata":"Yanıt kodlanamadı"}"#.utf8)
        if veri.count > 1_000_000 {   // Chrome'a giden yanıt sınırı 1 MB
            veri = Data(#"{"tamam":false,"hata":"Yanıt çok büyük"}"#.utf8)
        }
        var uzunluk = UInt32(veri.count).littleEndian
        let bas = Data(bytes: &uzunluk, count: 4)
        FileHandle.standardOutput.write(bas + veri)
    }

    // MARK: - İstekler

    struct Baglam {
        let cfg: SabitlemeYapilandirmasi
        let kuyruk: String
        let katalog: PPDKatalogu?
    }

    static func baglam() throws -> Baglam {
        let cfg = SabitlemeYapilandirmasi.yukle()
        let kuyruk = try kuyrukSec(cfg)
        return Baglam(cfg: cfg, kuyruk: kuyruk, katalog: PPDKatalogu.oku(CUPSIstemci.ppdYolu(kuyruk)))
    }

    /// Köprünün kullanacağı kuyruk. Sabitleme etkinse sabitlenen kuyruk (sabitleme kuyruğa bağlıdır);
    /// değilse uygulamada seçili kuyruk (köprü aynı paketten çalışır, UserDefaults ortaktır); o da yoksa
    /// ya da artık kurulu değilse Canon kuyruğu (uygulamanın açılışta seçtiğiyle aynı).
    private static func kuyrukSec(_ cfg: SabitlemeYapilandirmasi) throws -> String {
        let mevcut = Set(CUPSIstemci.kuyruklar().map(\.ad))
        guard !mevcut.isEmpty else { throw Komut.Hata(aciklama: "Bu Mac'te kurulu yazıcı bulunamadı.") }
        if cfg.etkin, !cfg.kuyruk.isEmpty {
            guard mevcut.contains(cfg.kuyruk) else {
                throw Komut.Hata(aciklama: "Sabitlenen yazıcı (\(cfg.kuyruk)) artık bu Mac'te yok. Yazıcı Paneli'nden yeniden sabitleyin.")
            }
            return cfg.kuyruk
        }
        if let secili = UserDefaults.standard.string(forKey: "kuyruk"), mevcut.contains(secili) { return secili }
        guard let canon = CUPSIstemci.canonKuyrugu() else { throw Komut.Hata(aciklama: "Bu Mac'te kurulu yazıcı bulunamadı.") }
        return canon
    }

    /// Durum değiştiren köprü istekleri süreçler arasında sıraya girer: Chrome'un zaman aşımından sonra
    /// önceki köprü süreci hâlâ çalışıyor olabilir. Bağlam kilit altında okunur, böylece bekleyen istek
    /// önceki işlemin yazdığı son hâli görür. (Kilit dosyası yalnız köprüye ait.)
    private static func kilitle<T>(_ govde: () throws -> T) throws -> T {
        let fd = open(Depo.dosya("chrome-kopru.kilit").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Komut.Hata(aciklama: "Köprü kilidi açılamadı") }
        defer { close(fd) }   // kapatmak kilidi de bırakır
        while flock(fd, LOCK_EX) != 0 {
            guard errno == EINTR else { throw Komut.Hata(aciklama: "Köprü kilidi alınamadı") }
        }
        return try govde()
    }

    static func isle(_ istek: [String: Any]) throws -> [String: Any] {
        let tur = istek["tur"] as? String ?? ""
        switch tur {
        case "durum": return try durum()
        case "yazici": return try yazici()
        case "yetenekler": return ["tamam": true, "cdd": try yetenekler(baglam())]
        case "yazdir": return try yazdir(istek)
        case "sabitle": return try kilitle { try sabitle(istek["hazirAyarId"] as? String ?? "") }
        case "kaldir":
            return try kilitle {
                // Aktif yedek varsa kaldir yedeğin kuyruğunu kullanır; sabitlenen kuyruk silinmiş olsa da çalışsın.
                let kuyruk = (try? baglam())?.kuyruk ?? SabitlemeYapilandirmasi.yukle().kuyruk
                try Sabitleme.kaldir(kuyruk: kuyruk)
                return ["tamam": true]
            }
        case "kesinMod":
            return try kilitle {
                let b = try baglam()
                guard b.cfg.etkin else { throw Komut.Hata(aciklama: "Önce bir ayar sabitleyin.") }
                var cfg = b.cfg
                cfg.kuyruk = b.kuyruk
                cfg.kesinMod = istek["acik"] as? Bool ?? false
                try Sabitleme.uygula(cfg)
                return ["tamam": true]
            }
        case "paneliAc":
            let yol = FileManager.default.fileExists(atPath: GorevliYoneticisi.kurulumYolu)
                ? GorevliYoneticisi.kurulumYolu : (Bundle.main.bundlePath)
            Komut.calistir("/usr/bin/open", [yol], zamanAsimi: 10)
            return ["tamam": true]
        default:
            throw Komut.Hata(aciklama: "Bilinmeyen istek: \(tur)")
        }
    }

    private static func seviyeAdi(_ s: DurumSeviyesi) -> String {
        switch s {
        case .hazir: return "hazir"
        case .calisiyor: return "calisiyor"
        case .bilinmiyor: return "bilinmiyor"
        case .uyari: return "uyari"
        case .hata: return "hata"
        }
    }

    private static func durum() throws -> [String: Any] {
        let b = try baglam()
        var kuyrukDurumu: KuyrukDurumu?
        var kuyrukHatasi: String?
        do { kuyrukDurumu = KuyrukDurumu(try CUPSIstemci.kuyrukOznitelikleri(b.kuyruk)) } catch { kuyrukHatasi = error.localizedDescription }
        let isler = ((try? CUPSIstemci.isler(b.kuyruk, tamamlanan: false)) ?? []).map(YaziciIsi.init)
        // Yazıcının kendisi: yalnız bilinen adresle, kısa zaman aşımıyla (panel hızlı açılsın).
        var cihaz: CihazDurumu?
        var cihazHatasi: String?
        if let aygit = kuyrukDurumu?.aygitAdresi,
           let adres = CihazBulucu.onbellek(aygit) ?? CihazBulucu.dogrudan(aygit) {
            // Yazıcı arada bir geç yanıtlar (ölçüm: 12 sorgunun 1'i 2 sn); tek hata "kapalı" dedirtmesin.
            let o = (try? CUPSIstemci.cihazOznitelikleri(adres, zamanAsimiMs: 1500))
                ?? (try? CUPSIstemci.cihazOznitelikleri(adres, zamanAsimiMs: 3000))
            if let o { cihaz = CihazDurumu(o) }
            else { cihazHatasi = "Yazıcıya ağdan ulaşılamadı. Kapalı ya da uyku modunda olabilir." }
        }
        let gorevliCanli = GorevliDurumu.yukle()?.canli ?? false
        let yorum = DurumYorumu(kuyruk: kuyrukDurumu, kuyrukHatasi: kuyrukHatasi, cihaz: cihaz, cihazHatasi: cihazHatasi,
                                isler: isler, sabitleme: b.cfg, gorevliCanli: gorevliCanli)
        let ozet = yorum.durumOzeti
        let hazirlar = HazirAyarDeposu.hepsi()
        let etkinHazir = b.cfg.etkin ? hazirlar.first { $0.ayarlar == b.cfg.ayarlar } : nil
        return [
            "tamam": true,
            "surum": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "geliştirme",
            "yazici": ["ad": "Canon G3010", "kuyruk": b.kuyruk],
            "durum": ["seviye": seviyeAdi(ozet.seviye), "baslik": ozet.baslik, "ayrinti": ozet.ayrinti as Any],
            "bekleyenIs": yorum.bekleyenIsSayisi,
            "sabitleme": [
                "etkin": b.cfg.etkin,
                "ozet": b.cfg.etkin ? b.cfg.ayarlar.ozet(katalog: b.katalog) : "Sabitleme kapalı",
                "kesinMod": b.cfg.kesinMod,
                "pencereKatmani": b.cfg.pencereKatmani,
                "hazirAyarId": etkinHazir?.id.uuidString as Any,
                "gorevliCanli": gorevliCanli,
            ],
            "hazirAyarlar": hazirlar.map { h in
                ["id": h.id.uuidString, "ad": h.ad, "aciklama": h.aciklama,
                 "ozet": h.ayarlar.ozet(katalog: b.katalog), "yerlesik": h.yerlesik] as [String: Any]
            },
            "chromeNotu": chromeNotu(b.cfg),
        ]
    }

    /// Chrome'un normal Canon hedefinin sabit ayarlarla ilişkisi (Chrome'un gönderdiği işler incelenerek bulundu:
    /// kalite, kağıt türü, parlaklık ve yarı tonu göndermez; renk, çözünürlük ve kağıt boyutunu kendi seçimiyle gönderir).
    static func chromeNotu(_ cfg: SabitlemeYapilandirmasi) -> String {
        guard cfg.etkin else {
            return "Sabitleme kapalı. Chrome, kendi yazdırma penceresinde seçtiğiniz ayarlarla basar."
        }
        // Fotoğraf kağıdı sabitse kalite sabitlenmez (Canon kağıda göre seçer); notun geri kalanı da buna göre.
        let fotoNotu = cfg.ayarlar.kalite != nil && !cfg.ayarlar.kaliteUygulanabilir
            ? "Kağıt türü fotoğraf kağıdı olduğu için kaliteyi Canon seçer; sabit kalite yalnız düz kağıtta geçerli. " : ""
        if cfg.kesinMod {
            return fotoNotu + "Kesin mod açık: Chrome'dan normal Canon yazıcısına gönderilen işler de sabit ayarlarla basılır."
        }
        var ezilen: [String] = []
        if cfg.ayarlar.griTon != nil { ezilen.append("renk") }
        if cfg.ayarlar.kaliteUygulanabilir { ezilen.append("çözünürlük") }
        if cfg.ayarlar.kagit != nil { ezilen.append("kağıt boyutu") }
        if ezilen.isEmpty {
            return fotoNotu + "Chrome'un normal Canon hedefi de sabit ayarları kullanır."
        }
        let liste = ezilen.count > 1 ? ezilen.dropLast().joined(separator: ", ") + " ve " + ezilen.last! : ezilen[0]
        let ek = ezilen.count > 1 ? "ayarlarını" : "ayarını"
        let bas = cfg.ayarlar.kaliteUygulanabilir ? "Chrome'un normal Canon hedefi sabit kaliteyi kullanır ama" : "Chrome'un normal Canon hedefi"
        return fotoNotu + "\(bas) \(liste) \(ek) kendi penceresindeki seçimle gönderir. Tamamen sabit baskı için yazdırırken “\(yaziciAdi(cfg))” hedefini seçin ya da kesin modu açın."
    }

    static func yaziciAdi(_ cfg: SabitlemeYapilandirmasi) -> String {
        cfg.etkin ? "Canon G3010 · Sabit ayarlar" : "Canon G3010 · Yazıcı Paneli"
    }

    private static func yazici() throws -> [String: Any] {
        let b = try baglam()
        let aciklama = b.cfg.etkin ? "Sabit: \(b.cfg.ayarlar.ozet(katalog: b.katalog))" : "Yazıcı Paneli üzerinden basar"
        return ["tamam": true, "id": yaziciKimligi, "ad": yaziciAdi(b.cfg), "aciklama": aciklama]
    }

    // MARK: - Yetenekler (Chrome'un yazdırma penceresinde görünenler)

    /// PPD kağıt boyutu → Chrome'un (CDD) ölçü adı ve mikron cinsinden boyutu.
    private static let kagitOlculeri: [String: (ad: String, en: Int, boy: Int)] = [
        "A4": ("ISO_A4", 210_000, 297_000), "A5": ("ISO_A5", 148_000, 210_000), "B5": ("JIS_B5", 182_000, 257_000),
        "Letter": ("NA_LETTER", 215_900, 279_400), "Legal": ("NA_LEGAL", 215_900, 355_600),
        "4x6": ("NA_INDEX_4X6", 101_600, 152_400), "5x7": ("NA_5X7", 127_000, 177_800),
        "8x10": ("NA_GOVT_LETTER", 203_200, 254_000), "Postcard": ("JPN_HAGAKI", 100_000, 148_000),
        "89x127mm": ("JPN_PHOTO_L", 89_000, 127_000), "127x127mm": ("OM_SQUARE_PHOTO", 127_000, 127_000),
    ]

    /// Etkin (varsayılan + sabit) ayarlar ve yalnız sabitlenmiş olanlar.
    private static func ayarlar(_ b: Baglam) -> (etkin: BaskiAyarSeti, sabit: BaskiAyarSeti) {
        let temel = b.katalog.map(BaskiAyarSeti.varsayilanlardan) ?? BaskiAyarSeti()
        let sabit = b.cfg.etkin ? b.cfg.ayarlar : BaskiAyarSeti()
        return (temel.birlestir(sabit), sabit)
    }

    private static func secenek(_ deger: String, _ ad: String, varsayilan: Bool) -> [String: Any] {
        ["value": deger, "display_name": ad, "is_default": varsayilan]
    }

    static func yetenekler(_ b: Baglam) -> [String: Any] {
        let (etkin, sabit) = ayarlar(b)
        var yazici: [String: Any] = [
            "supported_content_type": [["content_type": "application/pdf"]],
            "copies": ["default": 1, "max": 99],
            "page_orientation": ["option": [
                ["type": "PORTRAIT", "is_default": true], ["type": "LANDSCAPE"], ["type": "AUTO"],
            ]],
            "duplex": ["option": [["type": "NO_DUPLEX", "is_default": true]]],
        ]

        // Renk: sabitse tek seçenek (Chrome başka renk seçtiremez).
        let gri = etkin.griTon ?? false
        if let g = sabit.griTon {
            yazici["color"] = ["option": [["type": g ? "STANDARD_MONOCHROME" : "STANDARD_COLOR", "is_default": true,
                                           "custom_display_name": g ? "Siyah-beyaz (sabit)" : "Renkli (sabit)"]]]
        } else {
            yazici["color"] = ["option": [
                ["type": "STANDARD_COLOR", "is_default": !gri],
                ["type": "STANDARD_MONOCHROME", "is_default": gri],
            ]]
        }

        // Kağıt boyutu: PPD'deki bilinen boyutlar; sabitse yalnız o.
        let varsayilanKagit = etkin.kagit ?? "A4"
        var boyutlar: [[String: Any]] = []
        let kodlar = sabit.kagit.map { [$0] } ?? (b.katalog?["PageSize"]?.secimler.map(\.kod) ?? ["A4"])
        for kod in kodlar {
            let kenarsiz = kod.hasSuffix(".FullBleed")
            let temelKod = kenarsiz ? String(kod.dropLast(".FullBleed".count)) : kod
            guard let o = kagitOlculeri[temelKod] else { continue }
            if kenarsiz && sabit.kagit == nil { continue }   // kenarsız seçenekler kalabalık etmesin
            let ad = BaskiAyarSeti.kagitAdi(kod, katalog: b.katalog)
            boyutlar.append(["name": o.ad, "width_microns": o.en, "height_microns": o.boy, "vendor_id": kod,
                             "custom_display_name": sabit.kagit != nil ? "\(ad) (sabit)" : ad,
                             "is_default": kod == varsayilanKagit])
        }
        if !boyutlar.isEmpty, !boyutlar.contains(where: { $0["is_default"] as? Bool == true }) {
            boyutlar[0]["is_default"] = true
        }
        yazici["media_size"] = ["option": boyutlar]

        // Canon'a özgü ayarlar: "Gelişmiş ayarlar"da görünür.
        var ozel: [[String: Any]] = []
        let ortamSabitFoto = (sabit.ortam ?? "0") != "0"
        if !ortamSabitFoto {
            let secenekler: [[String: Any]]
            if let k = sabit.kalite {
                // Kağıt türü seçilebiliyorsa: fotoğraf kağıdı seçilince kaliteyi Canon belirler.
                let ad = sabit.ortam == nil ? "\(k.ad) (sabit, yalnız düz kağıtta)" : "\(k.ad) (sabit)"
                secenekler = [secenek(k.rawValue, ad, varsayilan: true)]
            } else {
                let v = etkin.kalite ?? .standart
                secenekler = Kalite.allCases.map { secenek($0.rawValue, $0.ad, varsayilan: $0 == v) }
            }
            ozel.append(["id": "kalite", "display_name": "Baskı kalitesi", "type": "SELECT",
                         "select_cap": ["option": secenekler]])
        }
        if let ortamlar = b.katalog?["CNIJMediaType"]?.secimler {
            let secenekler: [[String: Any]]
            if let o = sabit.ortam {
                secenekler = [secenek(o, "\(BaskiAyarSeti.ortamAdi(o, katalog: b.katalog)) (sabit)", varsayilan: true)]
            } else {
                let v = etkin.ortam ?? "0"
                secenekler = ortamlar.map { secenek($0.kod, $0.ad, varsayilan: $0.kod == v) }
            }
            ozel.append(["id": "ortam", "display_name": "Kağıt türü", "type": "SELECT",
                         "select_cap": ["option": secenekler]])
        }
        let parlaklik: [[String: Any]] = sabit.parlaklik.map { [secenek($0.rawValue, "\($0.ad) (sabit)", varsayilan: true)] }
            ?? Parlaklik.allCases.map { secenek($0.rawValue, $0.ad, varsayilan: $0 == (etkin.parlaklik ?? .normal)) }
        ozel.append(["id": "parlaklik", "display_name": "Parlaklık", "type": "SELECT", "select_cap": ["option": parlaklik]])
        yazici["vendor_capability"] = ozel

        return ["version": "1.0", "printer": yazici]
    }

    // MARK: - Yazdırma

    /// Chrome'un bileti (CJT) → anlamsal ayarlar. Sabitlenmiş ayarlar her zaman bilete üstün gelir.
    static func biletAyarlari(_ bilet: [String: Any], katalog: PPDKatalogu?) -> (ayarlar: BaskiAyarSeti, kopya: Int) {
        let p = bilet["print"] as? [String: Any] ?? [:]
        var a = BaskiAyarSeti()
        if let renk = (p["color"] as? [String: Any])?["type"] as? String {
            a.griTon = renk.contains("MONOCHROME")
        }
        if let boyut = p["media_size"] as? [String: Any] {
            if let v = boyut["vendor_id"] as? String, katalog?["PageSize"]?.secim(v) != nil || katalog == nil {
                a.kagit = v
            } else if let en = boyut["width_microns"] as? Int, let boy = boyut["height_microns"] as? Int {
                a.kagit = kagitOlculeri.first { abs($0.value.en - en) < 1500 && abs($0.value.boy - boy) < 1500 }?.key
            }
        }
        for oge in p["vendor_ticket_item"] as? [[String: Any]] ?? [] {
            guard let id = oge["id"] as? String, let deger = oge["value"] as? String else { continue }
            switch id {
            case "kalite": a.kalite = Kalite(rawValue: deger)
            case "ortam": a.ortam = deger
            case "parlaklik": a.parlaklik = Parlaklik(rawValue: deger)
            default: break
            }
        }
        let kopya = ((p["copies"] as? [String: Any])?["copies"] as? Int) ?? 1
        return (a, max(1, min(99, kopya)))
    }

    private static func yazdir(_ istek: [String: Any]) throws -> [String: Any] {
        let b = try baglam()
        guard let taban64 = istek["belge"] as? String, let pdf = Data(base64Encoded: taban64), !pdf.isEmpty else {
            throw Komut.Hata(aciklama: "Belge okunamadı")
        }
        guard pdf.starts(with: Data("%PDF".utf8)) else { throw Komut.Hata(aciklama: "Belge PDF değil") }
        let baslik = (istek["baslik"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Chrome"
        let (etkin, sabit) = ayarlar(b)
        let (biletten, kopya) = biletAyarlari(istek["bilet"] as? [String: Any] ?? [:], katalog: b.katalog)
        let son = etkin.birlestir(biletten).birlestir(sabit)

        var secenekler = son.isSecenekleri(katalog: b.katalog)
        var gosterilen = son
        if let o = son.ortam, o != "0" {
            // Fotoğraf kağıdında kalite anahtarları işe konmaz (kaliteUygulanabilir). Köprü işi kendi kalitesini
            // taşımadığından Canon filtresi eksikleri PPD varsayılanından (ör. sabit taslak, 300 dpi) alır:
            // fotoğraf kağıdı + taslak yazıcıda 4103 hatası verir. Bu yüzden güvenli kalite açıkça yazılır.
            let guvenli = BaskiAyarSeti(kalite: .standart, ortam: "0").isSecenekleri(katalog: b.katalog)
            for (a, d) in guvenli where BaskiAyarSeti.kaliteAnahtarlari.contains(a) { secenekler[a] = d }
            gosterilen.kalite = nil   // kaliteyi Canon belirler; özette seçilen/sabit kalite görünmesin
        }
        if kopya > 1 {
            secenekler["copies"] = String(kopya)
            secenekler["multiple-document-handling"] = "separate-documents-collated-copies"
        }
        secenekler["job-hold-until"] = "no-hold"          // kesin mod bekletmesin: ayarlar zaten uygulandı
        secenekler[Sabitleme.isaretOzniteligi] = "uygulama"

        let gecici = FileManager.default.temporaryDirectory
            .appendingPathComponent("yazici-paneli-chrome-\(UUID().uuidString).pdf")
        try pdf.write(to: gecici)
        defer { try? FileManager.default.removeItem(at: gecici) }   // yalnız bizim geçici kopyamız
        let no = try CUPSIstemci.dosyaYazdir(kuyruk: b.kuyruk, dosya: gecici, baslik: baslik, secenekler: secenekler)
        let ozet = gosterilen.ozet(katalog: b.katalog) + (kopya > 1 ? " · \(kopya) kopya" : "")
        Gunluk.yaz("Chrome'dan yazdırıldı (#\(no)): \(baslik) — \(ozet)", kaynak: "chrome")
        return ["tamam": true, "isNo": no, "ozet": ozet]
    }

    // MARK: - Hazır ayar

    private static func sabitle(_ kimlik: String) throws -> [String: Any] {
        let b = try baglam()
        guard let h = HazirAyarDeposu.hepsi().first(where: { $0.id.uuidString == kimlik }) else {
            throw Komut.Hata(aciklama: "Hazır ayar bulunamadı")
        }
        var cfg = b.cfg
        if !cfg.etkin {
            cfg.pencereKatmani = true
            cfg.kesinMod = false
        }
        cfg.kuyruk = b.kuyruk
        cfg.ayarlar = h.ayarlar
        cfg.hazirAyarAdi = h.ad
        try Sabitleme.uygula(cfg)
        return ["tamam": true, "ozet": h.ayarlar.ozet(katalog: b.katalog)]
    }
}
