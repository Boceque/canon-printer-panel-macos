import Foundation

/// Görevlinin uygulamaya bildirdiği nabız.
struct GorevliDurumu: Codable, Sendable {
    var pid: Int32
    var baslangic: Date
    var sonKontrol: Date
    var islenenSayisi: Int
    var sonIslemler: [String]

    static let dosyaAdi = "gorevli-durum.json"
    static func yukle() -> GorevliDurumu? { Depo.oku(GorevliDurumu.self, dosyaAdi) }

    /// Yakın zamanda nabız attı mı? (Görevli ~4 sn'de bir yazar; okuma gecikmesine pay bırakılır.)
    var canli: Bool { Date().timeIntervalSince(sonKontrol) < 25 && kill(pid, 0) == 0 }
}

/// Kesin mod için arka planda çalışan denetçi (`YaziciPaneli --gorevli`).
/// launchd tarafından ayakta tutulur; her saniye bekletilen işleri işler.
enum Gorevli {
    static func calistir() -> Never {
        setpriority(PRIO_PROCESS, 0, 10)
        Gunluk.yaz("Görevli başladı (pid \(getpid()))", kaynak: "görevli")
        let baslangic = Date()
        var islenenler = Set<Int>()
        var islenenSayisi = 0
        var sonIslemler: [String] = []
        var katalog: PPDKatalogu?
        var katalogZamani = Date.distantPast
        var sonPencere = Date.distantPast
        var sonBeklemeKontrolu = Date.distantPast
        var sonNabiz = Date.distantPast

        func nabiz() {
            let d = GorevliDurumu(pid: getpid(), baslangic: baslangic, sonKontrol: Date(),
                                  islenenSayisi: islenenSayisi, sonIslemler: sonIslemler)
            try? Depo.yaz(d, GorevliDurumu.dosyaAdi)
        }

        while true {
            let cikis: Bool = autoreleasepool {
                let cfg = SabitlemeYapilandirmasi.yukle()
                let simdi = Date()
                guard cfg.aktifKesinMod, !cfg.kuyruk.isEmpty else {
                    // Kesin mod kapandı: kendimi bekletilmiş iş bırakmadan kapat.
                    if cfg.kesinModBaslangic != nil {
                        IsDenetleyici.isle(cfg, katalog: katalog, islenenler: &islenenler, asgariYas: 0,
                                           yalnizSerbestBirak: true).kayitlar.forEach { Gunluk.yaz($0, kaynak: "görevli") }
                    }
                    Gunluk.yaz("Kesin mod kapalı, görevli çıkıyor", kaynak: "görevli")
                    return true
                }
                if katalog == nil || simdi.timeIntervalSince(katalogZamani) > 60 {
                    katalog = PPDKatalogu.oku(CUPSIstemci.ppdYolu(cfg.kuyruk))
                    katalogZamani = simdi
                    // Kuyruk yeniden kurulduysa (PPD varsayılanları sıfırlandıysa) sabitleri geri yaz.
                    if let k = katalog, Sabitleme.ppdyiTazele(cfg, katalog: k) {
                        Gunluk.yaz("Yazıcı varsayılanları yeniden sabitlendi", kaynak: "görevli")
                        katalog = PPDKatalogu.oku(CUPSIstemci.ppdYolu(cfg.kuyruk))
                    }
                }
                let sonuc = IsDenetleyici.isle(cfg, katalog: katalog, islenenler: &islenenler, simdi: simdi)
                islenenSayisi += sonuc.islenen
                // Aynı hata her saniye tekrar etmesin: hata satırları yalnız değiştiğinde yazılır.
                for k in sonuc.kayitlar where k != sonIslemler.last {
                    Gunluk.yaz(k, kaynak: "görevli")
                    sonIslemler.append(k)
                }
                if sonIslemler.count > 20 { sonIslemler.removeFirst(sonIslemler.count - 20) }
                if sonuc.islenen > 0 { nabiz(); sonNabiz = simdi }

                // Kuyruğun bekletme varsayılanı bir yerden sıfırlandıysa yeniden kur.
                if simdi.timeIntervalSince(sonBeklemeKontrolu) > 30 {
                    sonBeklemeKontrolu = simdi
                    let mevcut = (try? CUPSIstemci.kuyrukOznitelikleri(cfg.kuyruk))?.metin("job-hold-until-default")
                    if let mevcut, mevcut != "indefinite" {
                        do {
                            try Komut.lpadmin(cfg.kuyruk, [("job-hold-until-default", "indefinite")])
                            Gunluk.yaz("Kuyruk bekletme varsayılanı yeniden kuruldu", kaynak: "görevli")
                        } catch {
                            Gunluk.yaz("Bekletme varsayılanı kurulamadı: \(error.localizedDescription)", kaynak: "görevli")
                        }
                    }
                }
                if cfg.pencereKatmani && simdi.timeIntervalSince(sonPencere) > 15 {
                    sonPencere = simdi
                    if Sabitleme.pencereyiTazele(cfg, katalog: katalog) {
                        Gunluk.yaz("Yazdırma penceresi ayarları yeniden sabitlendi", kaynak: "görevli")
                    }
                }
                if simdi.timeIntervalSince(sonNabiz) > 4 { nabiz(); sonNabiz = simdi }
                return false
            }
            if cikis { exit(0) }
            usleep(1_000_000)
        }
    }
}

/// Görevliyi launchd'ye (kullanıcı oturumu) kurar/kaldırır.
enum GorevliYoneticisi {
    static let etiket = "com.caglar.yazicipaneli.gorevli"
    static let kurulumYolu = "/Applications/Yazıcı Paneli.app"

    static var plistYolu: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(etiket).plist")
    }

    static var hizmet: String { "\(Komut.kullaniciAlani)/\(etiket)" }

    /// Görevlinin çalıştıracağı program. /Applications'taki kopya tercih edilir: launchd,
    /// Masaüstü gibi korumalı klasörlerdeki programları çalıştıramayabilir.
    static var program: String? {
        let kurulu = "\(kurulumYolu)/Contents/MacOS/YaziciPaneli"
        if FileManager.default.isExecutableFile(atPath: kurulu) { return kurulu }
        return Bundle.main.executablePath
    }

    static var korumaliKlasorde: Bool {
        guard let p = program else { return false }
        let ev = FileManager.default.homeDirectoryForCurrentUser.path
        return ["Desktop", "Documents", "Downloads"].contains { p.hasPrefix("\(ev)/\($0)/") }
    }

    static var yuklu: Bool { Komut.launchctl(["print", hizmet]).basarili }

    static func baslat() throws {
        guard let program else { throw Komut.Hata(aciklama: "Uygulamanın yolu bulunamadı") }
        let plist: [String: Any] = [
            "Label": etiket,
            "ProgramArguments": [program, "--gorevli"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "ThrottleInterval": 5,
            "StandardErrorPath": Depo.dosya("gorevli-hata.log").path,
            "StandardOutPath": Depo.dosya("gorevli-hata.log").path,
        ]
        let veri = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistYolu.deletingLastPathComponent(), withIntermediateDirectories: true)
        try veri.write(to: plistYolu, options: .atomic)

        Komut.launchctl(["enable", hizmet])
        if yuklu {
            Komut.launchctl(["bootout", hizmet])
            usleep(400_000)
        }
        let s = Komut.launchctl(["bootstrap", Komut.kullaniciAlani, plistYolu.path])
        if !s.basarili && !yuklu {
            throw Komut.Hata(aciklama: "Arka plan görevlisi başlatılamadı: \(s.hata.isEmpty ? "kod \(s.kod)" : s.hata)")
        }
        // İlk nabzı bekle.
        let bitis = Date().addingTimeInterval(6)
        while Date() < bitis {
            if let d = GorevliDurumu.yukle(), d.canli, d.sonKontrol > Date().addingTimeInterval(-6) { return }
            usleep(250_000)
        }
        let ipucu = korumaliKlasorde
            ? " Uygulama Masaüstü'nden çalışıyor; derle.sh ile /Applications'a kurup oradan açın."
            : ""
        throw Komut.Hata(aciklama: "Arka plan görevlisi yanıt vermedi.\(ipucu)")
    }

    /// Görevliyi durdurur ve girişte yeniden yüklenmesin diye plist'i Çöp Sepeti'ne taşır
    /// (Sistem Ayarları › Giriş Öğeleri'nde boşuna görünmesin). Gerekince `baslat()` yeniden yazar.
    static func durdur() {
        if yuklu { Komut.launchctl(["bootout", hizmet]) }
        Komut.launchctl(["disable", hizmet])
        if FileManager.default.fileExists(atPath: plistYolu.path) {
            try? FileManager.default.trashItem(at: plistYolu, resultingItemURL: nil)
        }
    }

    static func yenidenBaslat() throws {
        durdur()
        usleep(300_000)
        try baslat()
    }
}
