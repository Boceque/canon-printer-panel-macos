import CoreFoundation
import Foundation

/// Kullanıcının sabitlediği ayarlar. Uygulama ile arka plan görevlisi bu dosyayı paylaşır.
struct SabitlemeYapilandirmasi: Codable, Equatable, Sendable {
    var etkin = false
    var kuyruk = ""
    var ayarlar = BaskiAyarSeti()
    /// macOS yazdırma penceresinin "Son Kullanılan Ayarlar"ını da sabit ayarlarla doldur.
    var pencereKatmani = true
    /// Her işi denetle: işler bekletilir, görevli sabit ayarları yazıp serbest bırakır.
    var kesinMod = false
    var kesinModBaslangic: Date?
    var hazirAyarAdi: String?
    var guncelleme: Date?

    static let dosyaAdi = "sabitleme.json"
    static func yukle() -> SabitlemeYapilandirmasi { Depo.oku(SabitlemeYapilandirmasi.self, dosyaAdi) ?? .init() }
    func kaydet() throws { try Depo.yaz(self, SabitlemeYapilandirmasi.dosyaAdi) }

    var aktifKesinMod: Bool { etkin && kesinMod }
}

/// Sabitlemeden önceki özgün değerler. Sabitleme kaldırılınca hepsi geri yüklenir.
struct SabitlemeYedegi: Codable, Sendable {
    var aktif: Bool
    var kuyruk: String
    var alinma: Date
    var ppd: [String: String]
    /// Yazıcıya özel "son kullanılan" sözlüğündeki değerler (nil = anahtar yoktu). Sözlük yoksa nil.
    var pencereYazici: [String: String?]?
    /// Genel "Son Kullanılan Ayarlar" hazır ayarındaki değerler.
    var pencereGenel: [String: String?]?
    var isBeklemeVarsayilani: String

    static let dosyaAdi = "yedek.json"
    static func yukle() -> SabitlemeYedegi? { Depo.oku(SabitlemeYedegi.self, dosyaAdi) }
    func kaydet() throws { try Depo.yaz(self, SabitlemeYedegi.dosyaAdi) }
}

// MARK: - Katman 2: macOS yazdırma penceresi

/// macOS yazdırma penceresi her açılışta "Son Kullanılan Ayarlar"ı yükler ve tüm CNIJ* anahtarlarını
/// işle birlikte gönderir; bu yüzden yalnız PPD varsayılanı yetmez. Burada o sözlükler CFPreferences
/// üzerinden (cfprefsd ile uyumlu) güncellenir.
enum PencereKatmani {
    static func yaziciAlani(_ kuyruk: String) -> String { "com.apple.print.custompresets.forprinter.\(kuyruk)" }
    static let genelAlan = "com.apple.print.custompresets"
    static let sonKullanilanAnahtari = "com.apple.print.v2.lastUsedSettingsPref"
    static let sonKullanilanAdlari = ["Son Kullanılan Ayarlar", "Last Used Settings"]
    static let ayarlarAnahtari = "com.apple.print.preset.settings"

    static var anahtarlar: [String] { BaskiAyarSeti.tumPPDAnahtarlari + BaskiAyarSeti.pencereEkAnahtarlari }

    private static func oku(_ alan: String, _ anahtar: String) -> Any? {
        CFPreferencesAppSynchronize(alan as CFString)
        return CFPreferencesCopyAppValue(anahtar as CFString, alan as CFString)
    }

    private static func yaz(_ alan: String, _ anahtar: String, _ deger: Any) {
        CFPreferencesSetAppValue(anahtar as CFString, deger as CFPropertyList, alan as CFString)
        CFPreferencesAppSynchronize(alan as CFString)
    }

    /// Genel alandaki "son kullanılan" hazır ayarının adı (dile göre değişir).
    private static func genelSonKullanilanAdi() -> String? {
        for ad in sonKullanilanAdlari where oku(genelAlan, ad) is [String: Any] { return ad }
        return nil
    }

    static func yaziciSozlugu(_ kuyruk: String) -> [String: Any]? {
        oku(yaziciAlani(kuyruk), sonKullanilanAnahtari) as? [String: Any]
    }

    static func genelSozluk() -> [String: Any]? {
        guard let ad = genelSonKullanilanAdi(), let hazir = oku(genelAlan, ad) as? [String: Any] else { return nil }
        return hazir[ayarlarAnahtari] as? [String: Any]
    }

    private static func secilenler(_ s: [String: Any]?) -> [String: String?]? {
        guard let s else { return nil }
        var sonuc: [String: String?] = [:]
        for a in anahtarlar { sonuc[a] = s[a].map { "\($0)" } }
        return sonuc
    }

    static func anlikGoruntu(_ kuyruk: String) -> (yazici: [String: String?]?, genel: [String: String?]?) {
        (secilenler(yaziciSozlugu(kuyruk)), secilenler(genelSozluk()))
    }

    /// `hedef` değerlerini yazar; `nil` değer anahtarı siler. Değişiklik yoksa yazmaz.
    /// Yalnız var olan sözlükler güncellenir (pencere hiç kullanılmadıysa PPD varsayılanı zaten geçerli).
    /// `kaliteKorumasi`: sözlükteki kağıt türü düz kağıt değilse kalite anahtarları yazılmaz
    /// (fotoğraf kağıdına taslak kalitesi yazmak yazıcıda 4103 hatası verir).
    @discardableResult
    static func uygula(kuyruk: String, yaziciHedef: [String: String?], genelHedef: [String: String?],
                       kaliteKorumasi: Bool = false) -> Bool {
        var yazildi = false
        func birlestir(_ s: [String: Any], _ hedef: [String: String?]) -> [String: Any]? {
            var yeni = s
            var degisti = false
            let fotograf = kaliteKorumasi && (s["CNIJMediaType"].map { "\($0)" } ?? "0") != "0"
            for (a, d) in hedef {
                if fotograf && BaskiAyarSeti.kaliteAnahtarlari.contains(a) { continue }
                let mevcut = s[a].map { "\($0)" }
                if mevcut == d { continue }
                degisti = true
                if let d { yeni[a] = d } else { yeni.removeValue(forKey: a) }
            }
            return degisti ? yeni : nil
        }
        if let s = yaziciSozlugu(kuyruk), let yeni = birlestir(s, yaziciHedef) {
            yaz(yaziciAlani(kuyruk), sonKullanilanAnahtari, yeni)
            yazildi = true
        }
        if let ad = genelSonKullanilanAdi(), var hazir = oku(genelAlan, ad) as? [String: Any],
           let s = hazir[ayarlarAnahtari] as? [String: Any], let yeni = birlestir(s, genelHedef) {
            hazir[ayarlarAnahtari] = yeni
            yaz(genelAlan, ad, hazir)
            yazildi = true
        }
        return yazildi
    }
}

// MARK: - Sabitleme motoru

enum Sabitleme {
    /// İşlenen işlere yazılan işaret özniteliği. Değerler: "1" görevli sabit ayarları yazdı,
    /// "serbest" olduğu gibi bırakıldı, "komut" bakım komutu, "uygulama" uygulamadan gönderildi.
    static let isaretOzniteligi = "yazicipaneli-sabit"

    struct Rapor: Sendable {
        var adimlar: [String] = []
        var uyarilar: [String] = []
    }

    /// Sabitlemeyi (yeniden) uygular: 1) PPD varsayılanı 2) yazdırma penceresi 3) kesin mod.
    /// Her katman yalnız sabitlenen ayarların anahtarlarına dokunur; sabitlemeden çıkarılan
    /// anahtarlar yedekteki özgün değerine döner, hiç sabitlenmemiş anahtarlara dokunulmaz.
    @discardableResult
    static func uygula(_ gelen: SabitlemeYapilandirmasi) throws -> Rapor {
        var cfg = gelen
        var rapor = Rapor()
        var onceki = SabitlemeYapilandirmasi.yukle()

        // Başka bir kuyruk sabitliyse önce onu tamamen eski hâline döndür.
        if let y = SabitlemeYedegi.yukle(), y.aktif, y.kuyruk != cfg.kuyruk {
            let r = try kaldir(kuyruk: y.kuyruk)
            rapor.adimlar.append("Önceki yazıcıdaki (\(y.kuyruk)) sabitleme kaldırıldı")
            rapor.uyarilar += r.uyarilar
            onceki = SabitlemeYapilandirmasi.yukle()
        }

        let kuyruk = cfg.kuyruk
        guard let katalog = PPDKatalogu.oku(CUPSIstemci.ppdYolu(kuyruk)) else {
            throw Komut.Hata(aciklama: "Yazıcı sürücü dosyası (PPD) okunamadı: \(CUPSIstemci.ppdYolu(kuyruk))")
        }

        let yedek: SabitlemeYedegi
        if let y = SabitlemeYedegi.yukle(), y.aktif, y.kuyruk == kuyruk {
            yedek = y
        } else {
            yedek = anlikYedek(kuyruk, katalog)
            try yedek.kaydet()
            rapor.adimlar.append("Özgün yazıcı ayarları yedeklendi")
        }
        let oncekiSabit = onceki.etkin && onceki.kuyruk == kuyruk ? onceki.ayarlar : BaskiAyarSeti()

        // Katman 1: PPD varsayılanları (Chrome önizlemesi, lp ve "Saptanmış Ayarlar" için).
        let hedef = ppdHedefi(cfg, katalog: katalog)
        if cfg.ayarlar.kalite != nil, hedef["CNIJPrintQuality"] == nil, cfg.ayarlar.kaliteUygulanabilir {
            rapor.uyarilar.append("Yazıcının varsayılan kağıdı fotoğraf kağıdı olduğu için kalite varsayılana yazılmadı.")
        }
        var istenen = hedef
        for a in oncekiSabit.ppdAnahtarlari.subtracting(hedef.keys) {
            if let d = yedek.ppd[a] { istenen[a] = d }
        }
        let degisen = istenen
            .filter { katalog.var_($0.key) && katalog.varsayilan($0.key) != $0.value }
            .sorted { $0.key < $1.key }
        if !degisen.isEmpty {
            try Komut.lpadmin(kuyruk, degisen.map { ($0.key, $0.value) })
            rapor.adimlar.append("Yazıcı varsayılanları güncellendi (\(degisen.count) ayar)")
        }

        // Katman 2: yazdırma penceresi.
        let oncekiPencere = onceki.etkin && onceki.kuyruk == kuyruk && onceki.pencereKatmani
        if cfg.pencereKatmani {
            // Sabitlemeden çıkan anahtarlar önce özgün değerine döner, sonra sabitler yazılır.
            let birakilan = oncekiPencere
                ? oncekiSabit.pencereAnahtarlari.subtracting(cfg.ayarlar.pencereSecenekleri(katalog: katalog).keys) : []
            let geri = pencereyiGeriYukle(yedek, anahtarlar: birakilan)
            if pencereyiUygula(cfg, katalog: katalog) || geri {
                rapor.adimlar.append("Yazdırma penceresinin son kullanılan ayarları güncellendi")
            }
        } else if oncekiPencere {
            if pencereyiGeriYukle(yedek, anahtarlar: oncekiSabit.pencereAnahtarlari) {
                rapor.adimlar.append("Yazdırma penceresi ayarları geri yüklendi")
            }
        }

        // Katman 3: kesin mod.
        cfg.etkin = true
        cfg.guncelleme = Date()
        if cfg.kesinMod {
            if cfg.kesinModBaslangic == nil { cfg.kesinModBaslangic = Date() }
            try cfg.kaydet()
            // Önce görevli, sonra bekletme: görevsiz bekleyen iş kalmasın.
            do {
                try GorevliYoneticisi.baslat()
            } catch {
                cfg.kesinMod = false
                cfg.kesinModBaslangic = nil
                try? cfg.kaydet()
                GorevliYoneticisi.durdur()
                throw error
            }
            if (try? CUPSIstemci.kuyrukOznitelikleri(kuyruk))?.metin("job-hold-until-default") != "indefinite" {
                try Komut.lpadmin(kuyruk, [("job-hold-until-default", "indefinite")])
            }
            rapor.adimlar.append("Kesin mod açık: her iş sabit ayarlarla basılacak")
        } else {
            let baslangic = onceki.kesinModBaslangic
            if onceki.kesinMod || GorevliYoneticisi.yuklu {
                do {
                    rapor.uyarilar += try kesinModuKapat(kuyruk, yedek: yedek, baslangic: baslangic,
                                                         ayarlar: onceki.ayarlar, katalog: katalog)
                } catch {
                    // Bekletme kaldırılamadı: görevli sürsün ki işler takılı kalmasın.
                    try? GorevliYoneticisi.baslat()
                    throw error
                }
                rapor.adimlar.append("Kesin mod kapatıldı")
            }
            cfg.kesinModBaslangic = nil
            try cfg.kaydet()
        }
        Gunluk.yaz("Sabitleme uygulandı: \(cfg.ayarlar.ozet(katalog: katalog))\(cfg.kesinMod ? " (kesin mod)" : "")")
        return rapor
    }

    /// Sabitlemeyi tamamen kaldırır, sabitlenen her şeyi yedekteki özgün hâline döndürür.
    /// Aktif yedek varsa her zaman yedeğin kuyruğunda çalışır (o an seçili kuyruk farklı olabilir).
    @discardableResult
    static func kaldir(kuyruk varsayilanKuyruk: String) throws -> Rapor {
        var cfg = SabitlemeYapilandirmasi.yukle()
        var rapor = Rapor()
        guard var yedek = SabitlemeYedegi.yukle(), yedek.aktif else {
            // Yedek yok: yine de bekletmeyi açık bırakma.
            let kuyruk = cfg.kuyruk.isEmpty ? varsayilanKuyruk : cfg.kuyruk
            GorevliYoneticisi.durdur()
            if (try? CUPSIstemci.kuyrukOznitelikleri(kuyruk))?.metin("job-hold-until-default") == "indefinite" {
                try Komut.lpadmin(kuyruk, [("job-hold-until-default", "no-hold")])
            }
            if cfg.etkin { rapor.uyarilar.append("Yedek bulunamadı; yazıcı varsayılanları geri yüklenemedi.") }
            cfg.etkin = false
            cfg.kesinMod = false
            cfg.kesinModBaslangic = nil
            try cfg.kaydet()
            return rapor
        }
        let kuyruk = yedek.kuyruk
        let katalog = PPDKatalogu.oku(CUPSIstemci.ppdYolu(kuyruk))
        let sabit = cfg.etkin && cfg.kuyruk == kuyruk ? cfg.ayarlar : nil

        // Kesin mod (bekletme doğrulanamazsa hata fırlatır; yedek aktif kalır, yeniden denenebilir).
        rapor.uyarilar += try kesinModuKapat(kuyruk, yedek: yedek, baslangic: cfg.kesinModBaslangic,
                                             ayarlar: cfg.ayarlar, katalog: katalog)

        // Katman 1: yalnız sabitlenmiş anahtarlar (yapılandırma yoksa yedekteki tüm anahtarlar).
        if let katalog {
            let anahtarlar = sabit?.ppdAnahtarlari ?? Set(yedek.ppd.keys)
            let degisen = yedek.ppd
                .filter { anahtarlar.contains($0.key) && katalog.var_($0.key) && katalog.varsayilan($0.key) != $0.value }
                .sorted { $0.key < $1.key }
            if !degisen.isEmpty {
                try Komut.lpadmin(kuyruk, degisen.map { ($0.key, $0.value) })
                rapor.adimlar.append("Yazıcı varsayılanları geri yüklendi")
            }
        }
        // Katman 2: yalnız pencere katmanı açıktıysa ve yalnız sabitlenmiş anahtarlar.
        if cfg.pencereKatmani, let sabit,
           pencereyiGeriYukle(yedek, anahtarlar: sabit.pencereAnahtarlari) {
            rapor.adimlar.append("Yazdırma penceresi ayarları geri yüklendi")
        }

        yedek.aktif = false
        try yedek.kaydet()
        cfg.etkin = false
        cfg.kesinMod = false
        cfg.kesinModBaslangic = nil
        cfg.guncelleme = Date()
        try cfg.kaydet()
        Gunluk.yaz("Sabitleme kaldırıldı, özgün ayarlar geri yüklendi (\(kuyruk))")
        return rapor
    }

    /// Pencere katmanı zamanla (kullanıcı pencerede başka seçip bastıkça) bozulur; sabitleri yeniden yazar.
    @discardableResult
    static func pencereyiTazele(_ cfg: SabitlemeYapilandirmasi, katalog: PPDKatalogu?) -> Bool {
        guard cfg.etkin, cfg.pencereKatmani, let yedek = SabitlemeYedegi.yukle(), yedek.aktif,
              yedek.kuyruk == cfg.kuyruk else { return false }
        return pencereyiUygula(cfg, katalog: katalog)
    }

    /// PPD varsayılanları sabit ayarlardan saptıysa (ör. kuyruk yeniden kuruldu) yeniden yazar.
    /// `katalog` güncel PPD'den okunmuş olmalı.
    @discardableResult
    static func ppdyiTazele(_ cfg: SabitlemeYapilandirmasi, katalog: PPDKatalogu) -> Bool {
        guard cfg.etkin, let yedek = SabitlemeYedegi.yukle(), yedek.aktif, yedek.kuyruk == cfg.kuyruk else { return false }
        let sapan = ppdHedefi(cfg, katalog: katalog)
            .filter { katalog.var_($0.key) && katalog.varsayilan($0.key) != $0.value }
            .sorted { $0.key < $1.key }
        guard !sapan.isEmpty else { return false }
        do {
            try Komut.lpadmin(cfg.kuyruk, sapan.map { ($0.key, $0.value) })
            return true
        } catch {
            return false
        }
    }

    // MARK: Yardımcılar

    /// Katman 1'e yazılacak değerler. Ortam sabitlenmemiş ve yazıcının varsayılan kağıdı fotoğraf
    /// kağıdıysa kalite yazılmaz: geçersiz ortam/kalite birleşimi yazıcıda 4103 hatası verir.
    private static func ppdHedefi(_ cfg: SabitlemeYapilandirmasi, katalog: PPDKatalogu) -> [String: String] {
        var hedef = cfg.ayarlar.ppdSecenekleri(katalog: katalog)
        if cfg.ayarlar.ortam == nil, let ortam = katalog.varsayilan("CNIJMediaType"), ortam != "0" {
            for a in BaskiAyarSeti.kaliteAnahtarlari { hedef.removeValue(forKey: a) }
        }
        return hedef
    }

    private static func anlikYedek(_ kuyruk: String, _ katalog: PPDKatalogu) -> SabitlemeYedegi {
        var ppd: [String: String] = [:]
        for a in BaskiAyarSeti.tumPPDAnahtarlari {
            if let d = katalog.varsayilan(a) { ppd[a] = d }
        }
        let pencere = PencereKatmani.anlikGoruntu(kuyruk)
        var bekleme = (try? CUPSIstemci.kuyrukOznitelikleri(kuyruk))?.metin("job-hold-until-default") ?? "no-hold"
        if bekleme == "indefinite" { bekleme = "no-hold" }  // önceki bir çökmeden kalmış olabilir
        return SabitlemeYedegi(aktif: true, kuyruk: kuyruk, alinma: Date(), ppd: ppd,
                               pencereYazici: pencere.yazici, pencereGenel: pencere.genel,
                               isBeklemeVarsayilani: bekleme)
    }

    /// Yalnız sabitlenen anahtarları yazar (kağıt türü sabit değilse fotoğraf kağıdında kaliteyi atlar).
    private static func pencereyiUygula(_ cfg: SabitlemeYapilandirmasi, katalog: PPDKatalogu?) -> Bool {
        let hedef = cfg.ayarlar.pencereSecenekleri(katalog: katalog).mapValues { Optional($0) }
        return PencereKatmani.uygula(kuyruk: cfg.kuyruk, yaziciHedef: hedef, genelHedef: hedef,
                                     kaliteKorumasi: cfg.ayarlar.ortam == nil)
    }

    /// Verilen anahtarları yedekteki özgün değerlerine döndürür (yedekte yoksa anahtar silinir).
    private static func pencereyiGeriYukle(_ yedek: SabitlemeYedegi, anahtarlar: Set<String>) -> Bool {
        guard !anahtarlar.isEmpty else { return false }
        func sec(_ ozgun: [String: String?]?) -> [String: String?] {
            guard let ozgun else { return [:] }   // sözlük sabitlemeden önce yoktu: dokunma
            var s: [String: String?] = [:]
            for a in anahtarlar { s[a] = ozgun[a] ?? nil }
            return s
        }
        return PencereKatmani.uygula(kuyruk: yedek.kuyruk, yaziciHedef: sec(yedek.pencereYazici),
                                     genelHedef: sec(yedek.pencereGenel))
    }

    /// Kesin modu kapatır: görevliyi durdurur, bekletme varsayılanını geri alır (doğrulayarak) ve
    /// kesin mod sırasında bekletilmiş işleri sabit ayarlarla gönderir. Bekletme geri alınamazsa hata fırlatır.
    private static func kesinModuKapat(_ kuyruk: String, yedek: SabitlemeYedegi, baslangic: Date?,
                                       ayarlar: BaskiAyarSeti, katalog: PPDKatalogu?) throws -> [String] {
        var uyarilar: [String] = []
        // Sıra önemli: önce görevli durur. Aksi hâlde görevli, bekletme varsayılanının değiştiğini
        // görüp `indefinite`'i geri kurabilir ve ardından sonlandırılınca işler takılı kalır.
        GorevliYoneticisi.durdur()
        var sonHata: Error?
        for deneme in 0..<2 {
            if deneme > 0 { usleep(500_000) }
            do {
                try Komut.lpadmin(kuyruk, [("job-hold-until-default", yedek.isBeklemeVarsayilani)])
            } catch {
                sonHata = error
            }
            if (try? CUPSIstemci.kuyrukOznitelikleri(kuyruk))?.metin("job-hold-until-default") != "indefinite" {
                sonHata = nil
                break
            }
        }
        if let sonHata {
            throw Komut.Hata(aciklama: "Kuyruğun iş bekletme ayarı geri alınamadı; yeni işler bekleyebilir. \(sonHata.localizedDescription)")
        }

        // Görevli durduktan sonra gelip bekletilmiş işler de gönderilir. Tam o anda gelmekte olan
        // (job-incoming) işler için birkaç kez bakılır; sonunda yine gelmekteyse bekletmesi kaldırılır.
        guard let baslangic else { return uyarilar }
        var cfg = SabitlemeYapilandirmasi()
        cfg.etkin = true
        cfg.kesinMod = true
        cfg.kuyruk = kuyruk
        cfg.ayarlar = ayarlar
        cfg.kesinModBaslangic = baslangic
        var islenenler = Set<Int>()
        for gecis in 0..<8 {
            if gecis > 0 { usleep(1_500_000) }
            let s = IsDenetleyici.isle(cfg, katalog: katalog, islenenler: &islenenler, asgariYas: 0)
            s.kayitlar.forEach { Gunluk.yaz($0) }
            if s.gelmekteOlan.isEmpty { return uyarilar }
            if gecis == 7 {
                for no in s.gelmekteOlan { try? CUPSIstemci.isAyarla(no, ["job-hold-until": "no-hold"]) }
                uyarilar.append("\(s.gelmekteOlan.count) iş gelmeye devam ettiği için sabit ayarlar yazılmadan serbest bırakıldı.")
            }
        }
        return uyarilar
    }
}

// MARK: - Kesin mod: iş denetimi

enum IsDenetleyici {
    struct Sonuc: Sendable {
        var kayitlar: [String] = []
        /// Sabit ayarları yazılıp (ya da olduğu gibi) serbest bırakılan iş sayısı.
        var islenen = 0
        var hatali = 0
        /// Henüz bilgisayardan gelmekte olduğu için atlanan bekletilmiş işler.
        var gelmekteOlan: [Int] = []
    }

    /// Bir işe yazılacak sabit ayarlar. Bakım komutlarına dokunulmaz. Kağıt türü sabitlenmemişken
    /// fotoğraf kağıdı seçilmiş işte kaliteye dokunulmaz (4103 hatası riski). `not` günlük içindir.
    static func isSecenekleri(_ i: YaziciIsi, cfg: SabitlemeYapilandirmasi, katalog: PPDKatalogu?) -> (secenekler: [String: String], not: String) {
        guard !i.komutIsi else { return ([:], "") }
        var s = cfg.ayarlar.isSecenekleri(katalog: katalog)
        var not = ""
        if cfg.ayarlar.ortam == nil, let ortam = i.ortam, ortam != "0" {
            for a in BaskiAyarSeti.kaliteAnahtarlari { s.removeValue(forKey: a) }
            not = " (fotoğraf kağıdı: kaliteye dokunulmadı)"
        }
        return (s, not)
    }

    /// Kesin modda bekletilmiş yeni işleri bulur, sabit ayarları yazar ve serbest bırakır.
    static func isle(_ cfg: SabitlemeYapilandirmasi, katalog: PPDKatalogu?, islenenler: inout Set<Int>,
                     simdi: Date = Date(), asgariYas: TimeInterval = 1.5, yalnizSerbestBirak: Bool = false) -> Sonuc {
        var sonuc = Sonuc()
        guard let baslangic = cfg.kesinModBaslangic else { return sonuc }
        let isler: [YaziciIsi]
        do {
            isler = try CUPSIstemci.isler(cfg.kuyruk, tamamlanan: false).map(YaziciIsi.init)
        } catch {
            sonuc.hatali += 1
            sonuc.kayitlar.append("İş listesi okunamadı: \(error.localizedDescription)")
            return sonuc
        }
        for i in isler {
            guard i.durum == .beklemede, i.bekletmeZamani == "indefinite", i.sabitlemeIsareti == nil,
                  !islenenler.contains(i.id) else { continue }
            // Kesin moddan önce (ör. kullanıcının elle beklettiği) işlere dokunma.
            if let t = i.olusturma, t < baslangic.addingTimeInterval(-5) { continue }
            // İş henüz tamamen gelmediyse ya da sistem kendi ayarlarını yazmadıysa bekle.
            if i.geliyor || (i.belgeSayisi ?? 1) < 1 {
                sonuc.gelmekteOlan.append(i.id)
                continue
            }
            if let t = i.olusturma, simdi.timeIntervalSince(t) < asgariYas { continue }

            let (secenekler, not) = yalnizSerbestBirak ? ([:], "") : isSecenekleri(i, cfg: cfg, katalog: katalog)
            let isaret = i.komutIsi ? "komut" : (secenekler.isEmpty ? "serbest" : "1")
            var istek = secenekler
            istek[Sabitleme.isaretOzniteligi] = isaret
            istek["job-hold-until"] = "no-hold"
            islenenler.insert(i.id)
            do {
                try CUPSIstemci.isAyarla(i.id, istek)
                sonuc.islenen += 1
                sonuc.kayitlar.append(secenekler.isEmpty
                                      ? "İş #\(i.id) \"\(i.ad)\" olduğu gibi serbest bırakıldı"
                                      : "İş #\(i.id) \"\(i.ad)\" sabit ayarlarla yazdırılıyor: \(cfg.ayarlar.ozet(katalog: katalog))\(not)")
            } catch {
                // İşaret özniteliği reddedildiyse onsuz dene; o da olmazsa en azından serbest bırak.
                var yedekIstek = secenekler
                yedekIstek["job-hold-until"] = "no-hold"
                if (try? CUPSIstemci.isAyarla(i.id, yedekIstek)) != nil {
                    sonuc.islenen += 1
                    sonuc.kayitlar.append("İş #\(i.id) sabit ayarlarla yazdırılıyor (işaretsiz)")
                } else if (try? CUPSIstemci.isSurdur(i.id)) != nil {
                    sonuc.islenen += 1
                    sonuc.kayitlar.append("İş #\(i.id) ayarları yazılamadı, olduğu gibi serbest bırakıldı: \(error.localizedDescription)")
                } else {
                    sonuc.hatali += 1
                    sonuc.kayitlar.append("İş #\(i.id) işlenemedi: \(error.localizedDescription)")
                }
            }
        }
        return sonuc
    }

    /// Kesin mod açıkken bekletilip işlenmemiş (ve tamamen gelmiş) iş sayısı.
    static func bekleyenSayisi(_ isler: [YaziciIsi], baslangic: Date?) -> Int {
        guard let baslangic else { return 0 }
        return isler.filter {
            $0.durum == .beklemede && $0.bekletmeZamani == "indefinite" && $0.sabitlemeIsareti == nil && !$0.geliyor
                && ($0.olusturma ?? .distantFuture) >= baslangic.addingTimeInterval(-5)
        }.count
    }
}
