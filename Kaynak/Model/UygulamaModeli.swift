import AppKit
import Observation
import ServiceManagement
import SwiftUI
import UserNotifications

// MARK: - Arayüz türleri

enum Bolum: String, CaseIterable, Identifiable, Hashable {
    case genelBakis, baskiAyarlari, hazirAyarlar, hizliYazdir, kuyruk, bakim, bilgi, tercihler
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .genelBakis: return "Genel Bakış"
        case .baskiAyarlari: return "Baskı Ayarları"
        case .hazirAyarlar: return "Hazır Ayarlar"
        case .hizliYazdir: return "Hızlı Yazdır"
        case .kuyruk: return "Yazdırma Kuyruğu"
        case .bakim: return "Bakım"
        case .bilgi: return "Yazıcı Bilgisi"
        case .tercihler: return "Tercihler"
        }
    }

    var simge: String {
        switch self {
        case .genelBakis: return "gauge.with.dots.needle.33percent"
        case .baskiAyarlari: return "slider.horizontal.3"
        case .hazirAyarlar: return "square.stack.3d.up"
        case .hizliYazdir: return "doc.on.doc"
        case .kuyruk: return "list.bullet.rectangle"
        case .bakim: return "wrench.and.screwdriver"
        case .bilgi: return "info.circle"
        case .tercihler: return "gearshape"
        }
    }
}

/// Sabitlenebilir ayar anahtarları.
enum AyarAnahtari: String, CaseIterable, Identifiable, Hashable, Codable {
    case kalite, griTon, ortam, kagit, parlaklik, yariTon
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .kalite: return "Baskı kalitesi"
        case .griTon: return "Renk"
        case .ortam: return "Kağıt türü"
        case .kagit: return "Kağıt boyutu"
        case .parlaklik: return "Parlaklık"
        case .yariTon: return "Yarı ton"
        }
    }

    var simge: String {
        switch self {
        case .kalite: return "dial.medium"
        case .griTon: return "circle.lefthalf.filled"
        case .ortam: return "doc.richtext"
        case .kagit: return "rectangle.portrait"
        case .parlaklik: return "sun.max"
        case .yariTon: return "circle.grid.cross"
        }
    }
}

extension BaskiAyarSeti {
    /// Yalnız verilen anahtarları tutar, diğerlerini `nil` yapar.
    func sadece(_ anahtarlar: Set<AyarAnahtari>) -> BaskiAyarSeti {
        BaskiAyarSeti(kalite: anahtarlar.contains(.kalite) ? kalite : nil,
                      griTon: anahtarlar.contains(.griTon) ? griTon : nil,
                      ortam: anahtarlar.contains(.ortam) ? ortam : nil,
                      kagit: anahtarlar.contains(.kagit) ? kagit : nil,
                      parlaklik: anahtarlar.contains(.parlaklik) ? parlaklik : nil,
                      yariTon: anahtarlar.contains(.yariTon) ? yariTon : nil)
    }

    var doluAnahtarlar: Set<AyarAnahtari> {
        var s = Set<AyarAnahtari>()
        if kalite != nil { s.insert(.kalite) }
        if griTon != nil { s.insert(.griTon) }
        if ortam != nil { s.insert(.ortam) }
        if kagit != nil { s.insert(.kagit) }
        if parlaklik != nil { s.insert(.parlaklik) }
        if yariTon != nil { s.insert(.yariTon) }
        return s
    }
}

struct Bildirim: Identifiable, Equatable {
    enum Tur { case basari, hata, bilgi }
    let id = UUID()
    let tur: Tur
    let metin: String
}

// MARK: - Model

@Observable
@MainActor
final class UygulamaModeli {
    // Kimlik
    var kuyrukAdi = ""
    var kuyruklar: [KuyrukOzeti] = []

    // Durum
    var kuyruk: KuyrukDurumu?
    var kuyrukHatasi: String?
    var cihaz: CihazDurumu?
    var cihazHatasi: String?
    var cihazAdresi: CihazAdresi?
    var cihazSonOkuma: Date?
    var isler: [YaziciIsi] = []
    var tamamlananlar: [YaziciIsi] = []
    var katalog: PPDKatalogu?
    var yaziciSimgesi: NSImage?
    var sonYenileme: Date?
    var yenileniyor = false

    // Sabitleme
    var sabitleme = SabitlemeYapilandirmasi.yukle()
    var yedek: SabitlemeYedegi? = SabitlemeYedegi.yukle()
    var gorevli: GorevliDurumu?
    /// Nabız okunduğu anda hesaplanan canlılık (sonradan geçen süre yüzünden yanlış "ölü" demesin).
    var gorevliCanliDurum = false
    var gorevliYuklu = false
    /// Elle çift taraf: 1. adımdan sonra 2. adıma kadar (bölüm değişse de) saklanır.
    var ciftTarafOturumu: ElleCiftTarafOturumu?
    var ciftTarafSirayiCevir = false
    /// Baskı Ayarları ekranında düzenlenen değerler (tümü dolu).
    var duzenlenen = BaskiAyarSeti()
    /// Baskı Ayarları ekranında kilitlenen (sabitlenecek) ayarlar.
    var kilitli: Set<AyarAnahtari> = [.kalite]
    var pencereKatmaniSecili = true
    var kesinModSecili = false
    var hazirAyarlar: [HazirAyar] = HazirAyarDeposu.hepsi()

    // Arayüz
    var secilenBolum: Bolum = .genelBakis
    var bildirim: Bildirim?
    var mesgul: String?
    var gunlukSatirlari: [String] = []

    // Tercihler
    var bildirimlerAcik: Bool = UserDefaults.standard.object(forKey: "bildirimlerAcik") as? Bool ?? true {
        didSet { UserDefaults.standard.set(bildirimlerAcik, forKey: "bildirimlerAcik"); if bildirimlerAcik { bildirimIzniIste() } }
    }
    var menuCubugunda: Bool = UserDefaults.standard.object(forKey: "menuCubugunda") as? Bool ?? true {
        didSet { UserDefaults.standard.set(menuCubugunda, forKey: "menuCubugunda") }
    }
    var arkaPlandaCalis: Bool = UserDefaults.standard.object(forKey: "arkaPlandaCalis") as? Bool ?? true {
        didSet { UserDefaults.standard.set(arkaPlandaCalis, forKey: "arkaPlandaCalis") }
    }
    var girisBaslat: Bool = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private var dongu: Task<Void, Never>?
    @ObservationIgnored private var bulucu = CihazBulucu()
    @ObservationIgnored private var sonCihazOkumaDenemesi = Date.distantPast
    @ObservationIgnored private var sonPencereTazeleme = Date.distantPast
    @ObservationIgnored private var sonGorevliSorgusu = Date.distantPast
    @ObservationIgnored private var cihazOkunuyor = false
    @ObservationIgnored private var mesgulSayaci = 0
    @ObservationIgnored private var yenidenTaraniyor = false
    @ObservationIgnored private var sonCozme = Date.distantPast
    @ObservationIgnored private var sonBildirilenSorun: String?
    @ObservationIgnored private var bildirimGorevi: Task<Void, Never>?
    @ObservationIgnored private var basladi = false

    init() {}

    // MARK: Başlangıç

    func baslat() {
        guard !basladi else { return }
        basladi = true
        Task {
            mesgul = "Yazıcı aranıyor…"
            let (liste, secili) = await Task.detached { () -> ([KuyrukOzeti], String?) in
                (CUPSIstemci.kuyruklar(), CUPSIstemci.canonKuyrugu())
            }.value
            kuyruklar = liste
            let kayitli = UserDefaults.standard.string(forKey: "kuyruk")
            kuyrukAdi = (kayitli.flatMap { k in liste.contains { $0.ad == k } ? k : nil }) ?? secili ?? ""
            if sabitleme.kuyruk.isEmpty { sabitleme.kuyruk = kuyrukAdi }
            mesgul = nil
            await kataloguYukle()
            duzenleyiciyiSifirla()
            await yenile(cihazDahil: true)
            if bildirimlerAcik { bildirimIzniIste() }
            donguyuBaslat()
            // Chrome köprüsünü ve eklenti dosyalarını güncel tut (uygulama taşınınca yol değişebilir).
            await chromeDurumunuYenile(kur: true)
        }
    }

    /// Yazıcı bulunamadıysa (ya da yeni yazıcı eklendiyse) kuyrukları yeniden tarar.
    func kuyruklariYenidenTara() async {
        guard !yenidenTaraniyor else { return }
        yenidenTaraniyor = true
        defer { yenidenTaraniyor = false }
        let (liste, secili) = await Task.detached { () -> ([KuyrukOzeti], String?) in
            (CUPSIstemci.kuyruklar(), CUPSIstemci.canonKuyrugu())
        }.value
        kuyruklar = liste
        if kuyrukAdi.isEmpty || !liste.contains(where: { $0.ad == kuyrukAdi }) {
            kuyrukAdi = secili ?? ""
            if sabitleme.kuyruk.isEmpty { sabitleme.kuyruk = kuyrukAdi }
            await kataloguYukle()
            duzenleyiciyiSifirla()
        }
        await yenile(cihazDahil: true)
    }

    func kuyrukSec(_ ad: String) {
        guard ad != kuyrukAdi else { return }
        if sabitleme.etkin, !sabitleme.kuyruk.isEmpty, sabitleme.kuyruk != ad {
            goster("Sabit ayarlar \"\(sabitleme.kuyruk)\" yazıcısında kalıyor. Bu yazıcıya uygulamak için Baskı Ayarları'nda Güncelle'ye basın.", .bilgi)
        }
        kuyrukAdi = ad
        UserDefaults.standard.set(ad, forKey: "kuyruk")
        cihaz = nil
        cihazAdresi = nil
        Task {
            await kataloguYukle()
            duzenleyiciyiSifirla()
            await yenile(cihazDahil: true)
        }
    }

    private func kataloguYukle() async {
        let ad = kuyrukAdi
        guard !ad.isEmpty else { return }
        let k = await Task.detached { PPDKatalogu.oku(CUPSIstemci.ppdYolu(ad)) }.value
        katalog = k
        if let yol = k?.simgeYolu { yaziciSimgesi = NSImage(contentsOfFile: yol) }
    }

    private func donguyuBaslat() {
        dongu?.cancel()
        dongu = Task { [weak self] in
            while !Task.isCancelled {
                let aktif = NSApp.isActive
                try? await Task.sleep(for: .seconds(aktif ? 2 : 8))
                guard let self, !Task.isCancelled else { return }
                let cihazAraligi: TimeInterval = aktif ? 6 : 30
                await self.yenile(cihazDahil: Date().timeIntervalSince(self.sonCihazOkumaDenemesi) > cihazAraligi)
            }
        }
    }

    // MARK: Yenileme

    func yenile(cihazDahil: Bool = false) async {
        let ad = kuyrukAdi
        guard !ad.isEmpty else {
            kuyrukHatasi = "Bu Mac'te kurulu yazıcı bulunamadı."
            return
        }
        yenileniyor = true
        defer { yenileniyor = false; sonYenileme = Date() }

        async let kuyrukSonucu = Task.detached { () -> Result<IPPOznitelikler, Error> in
            Result { try CUPSIstemci.kuyrukOznitelikleri(ad) }
        }.value
        async let isSonucu = Task.detached { () -> Result<[IPPOznitelikler], Error> in
            Result { try CUPSIstemci.isler(ad, tamamlanan: false) }
        }.value
        async let bitenSonucu = Task.detached { () -> Result<[IPPOznitelikler], Error> in
            Result { try CUPSIstemci.isler(ad, tamamlanan: true, oznitelikler: [
                "job-id", "job-name", "job-state", "job-state-reasons", "job-originating-user-name",
                "time-at-creation", "time-at-completed", "job-k-octets", "job-impressions-completed",
                "job-media-sheets-completed", "document-format", "CNIJPrintQuality", "CNIJGrayScale",
                "CNIJMediaType", "job-preserved", Sabitleme.isaretOzniteligi,
            ]) }
        }.value

        switch await kuyrukSonucu {
        case .success(let o):
            kuyruk = KuyrukDurumu(o)
            kuyrukHatasi = nil
        case .failure(let e):
            // Bayat durumu gösterme: kuyruk okunamıyorsa bilinmiyor say.
            kuyrukHatasi = e.localizedDescription
            kuyruk = nil
            isler = []
            // 0x0406 = IPP not-found: kuyruk silinmiş/yeniden adlandırılmış; yenisini ara.
            if (e as? CUPSHatasi)?.kod == 0x0406, !yenidenTaraniyor {
                Task { await self.kuyruklariYenidenTara() }
            }
        }
        if case .success(let liste) = await isSonucu {
            isler = liste.map(YaziciIsi.init).sorted { $0.id < $1.id }
        }
        if case .success(let liste) = await bitenSonucu {
            tamamlananlar = Array(liste.map(YaziciIsi.init).sorted { $0.id > $1.id }.prefix(60))
        }

        // launchctl süreci açmak pahalı: yalnız kesin modda ve 30 sn'de bir sor.
        if sabitleme.kesinMod {
            if Date().timeIntervalSince(sonGorevliSorgusu) > 30 {
                sonGorevliSorgusu = Date()
                gorevliYuklu = await Task.detached { GorevliYoneticisi.yuklu }.value
            }
        } else {
            gorevliYuklu = false
        }
        let diskteki = SabitlemeYapilandirmasi.yukle()
        if diskteki != sabitleme {
            // Başka yerden (Chrome eklentisi, menü) değişti: yedeği ve düzenleyiciyi de diskle eşitle.
            let onemli = diskteki.etkin != sabitleme.etkin || diskteki.ayarlar != sabitleme.ayarlar
                || diskteki.kuyruk != sabitleme.kuyruk
            sabitleme = diskteki
            yedek = SabitlemeYedegi.yukle()
            if onemli {
                await kataloguYukle()
                duzenleyiciyiSifirla()
            } else if diskteki.etkin {
                kesinModSecili = diskteki.kesinMod
                pencereKatmaniSecili = diskteki.pencereKatmani
            }
        }
        girisBaslat = SMAppService.mainApp.status == .enabled

        if cihazDahil { await cihaziOku() }

        // Nabız cihaz okumasından SONRA okunur ve canlılık o anda hesaplanır.
        gorevli = GorevliDurumu.yukle()
        gorevliCanliDurum = gorevli?.canli ?? false

        // Pencere katmanını ara ara tazele (görevli çalışmıyorsa uygulama üstlenir).
        if sabitleme.etkin, sabitleme.pencereKatmani, !(gorevli?.canli ?? false),
           Date().timeIntervalSince(sonPencereTazeleme) > 20 {
            sonPencereTazeleme = Date()
            let cfg = sabitleme, k = katalog
            let ppdYazildi = await Task.detached { () -> Bool in
                Sabitleme.pencereyiTazele(cfg, katalog: k)
                // Kuyruk yeniden kurulduysa PPD varsayılanlarını da geri yaz.
                guard let guncel = PPDKatalogu.oku(CUPSIstemci.ppdYolu(cfg.kuyruk)) else { return false }
                return Sabitleme.ppdyiTazele(cfg, katalog: guncel)
            }.value
            if ppdYazildi {
                Gunluk.yaz("Yazıcı varsayılanları yeniden sabitlendi")
                await kataloguYukle()
            }
        }
        sorunBildiriminiDegerlendir()
    }

    private func cihaziOku() async {
        guard !cihazOkunuyor else { return }
        cihazOkunuyor = true
        defer { cihazOkunuyor = false }
        sonCihazOkumaDenemesi = Date()
        guard let aygit = kuyruk?.aygitAdresi, !aygit.isEmpty else { return }
        if cihazAdresi == nil {
            cihazAdresi = CihazBulucu.onbellek(aygit)
            if cihazAdresi == nil, Date().timeIntervalSince(sonCozme) > 20 {
                sonCozme = Date()
                cihazAdresi = await bulucu.coz(aygit)
            }
        }
        guard let adres = cihazAdresi else {
            cihaz = nil
            cihazHatasi = aygit.hasPrefix("dnssd://") || aygit.hasPrefix("ipp")
                ? "Yazıcı ağda bulunamadı (kapalı olabilir ya da yerel ağ izni verilmemiş olabilir)."
                : "Bu bağlantı türünde yazıcının kendi durumu okunamıyor."
            return
        }
        // Yazıcı arada bir geç yanıtlar; tek başarısız okuma "kapalı" uyarısına dönmesin diye bir kez daha denenir.
        let sonuc = await Task.detached { () -> Result<IPPOznitelikler, Error> in
            if let o = try? CUPSIstemci.cihazOznitelikleri(adres) { return .success(o) }
            try? await Task.sleep(for: .milliseconds(700))
            return Result { try CUPSIstemci.cihazOznitelikleri(adres) }
        }.value
        switch sonuc {
        case .success(let o):
            var c = CihazDurumu(o)
            if c.sorunVar || c.durum != .bosta {
                // IPP bazı durumları yanlış adlandırır (hizalama deseni taratılmayı beklerken "spool area full").
                // Yazıcının kendi kanalı (CHMP) durmuş + Canon kodu diyorsa, o kodun Türkçe metni öne geçer.
                let host = adres.host
                if let d = await Task.detached(operation: { try? CanonCihaz.durum(host: host) }).value,
                   d.durum == "stopped", let kod = d.destekKodu {
                    c.durum = .durdu
                    c.nedenler.removeAll { $0.kok == "spool-area-full" || $0.kok == "none" }
                    c.nedenler.insert(DurumNedeni(ham: "com.canon-\(kod)-error"), at: 0)
                    c.uyariMetni = nil
                }
            }
            cihaz = c
            cihazHatasi = nil
            cihazSonOkuma = Date()
        case .failure(let e):
            cihazHatasi = "Yazıcıya ağdan ulaşılamadı. Kapalı ya da uyku modunda olabilir. (\(e.localizedDescription))"
            // Adres değişmiş olabilir (DHCP): dakikada en çok bir kez yeniden çöz.
            if Date().timeIntervalSince(sonCozme) > 60 {
                sonCozme = Date()
                if let yeni = await bulucu.coz(aygit), yeni != adres { cihazAdresi = yeni }
            }
            if let son = cihazSonOkuma, Date().timeIntervalSince(son) > 60 { cihaz = nil }
        }
    }

    // MARK: Türetilmiş durum

    /// Durum yorumu çekirdekte (Chrome köprüsü de aynısını kullanır).
    var durumYorumu: DurumYorumu {
        DurumYorumu(kuyruk: kuyruk, kuyrukHatasi: kuyrukHatasi, cihaz: cihaz, cihazHatasi: cihazHatasi,
                    isler: isler, sabitleme: sabitleme, gorevliCanli: gorevliCanli)
    }
    var etkinIs: YaziciIsi? { durumYorumu.etkinIs }
    var bekleyenIsSayisi: Int { durumYorumu.bekleyenIsSayisi }
    /// Kesin mod açık ama görevli işlemediği için bekleyen işler.
    var takiliIsSayisi: Int { durumYorumu.takiliIsSayisi }
    var gorevliCanli: Bool { gorevliCanliDurum }
    /// Kuyrukta, yazıcının artık bildirmediği hata nedenleri (eski uyarılar).
    var eskiUyarilar: [DurumNedeni] { durumYorumu.eskiUyarilar }
    var durumOzeti: DurumOzeti { durumYorumu.durumOzeti }

    /// Şu an geçerli (sabitlenmiş ya da yazıcı varsayılanı) ayarlar.
    var etkinAyarlar: BaskiAyarSeti {
        let temel = katalog.map(BaskiAyarSeti.varsayilanlardan) ?? BaskiAyarSeti()
        return sabitleme.etkin ? temel.birlestir(sabitleme.ayarlar) : temel
    }

    var sabitlemeOzeti: String {
        sabitleme.etkin ? sabitleme.ayarlar.ozet(katalog: katalog) : "Sabitleme kapalı"
    }

    /// "Kağıt bitince kuyruğu durdur" (CUPS varsayılanı stop-printer).
    var kagitBitinceDurdur: Bool { (kuyruk?.hataPolitikasi ?? "stop-printer") == "stop-printer" }

    // MARK: Düzenleyici

    func duzenleyiciyiSifirla() {
        let temel = katalog.map(BaskiAyarSeti.varsayilanlardan) ?? BaskiAyarSeti()
        var tam = temel
        if tam.kalite == nil { tam.kalite = .standart }
        if tam.griTon == nil { tam.griTon = false }
        if tam.ortam == nil { tam.ortam = "0" }
        if tam.kagit == nil { tam.kagit = "A4" }
        if tam.parlaklik == nil { tam.parlaklik = .normal }
        if tam.yariTon == nil { tam.yariTon = .dagilma }
        if sabitleme.etkin {
            duzenlenen = tam.birlestir(sabitleme.ayarlar)
            kilitli = sabitleme.ayarlar.doluAnahtarlar
            pencereKatmaniSecili = sabitleme.pencereKatmani
            kesinModSecili = sabitleme.kesinMod
        } else {
            duzenlenen = tam
            kilitli = [.kalite]
            pencereKatmaniSecili = true
            kesinModSecili = false
        }
    }

    /// Düzenleyicideki kilitli ayarlar, sabitlenmiş olanlardan farklı mı?
    var duzenleyiciDegisti: Bool {
        guard sabitleme.etkin else { return true }
        return duzenlenen.sadece(kilitli) != sabitleme.ayarlar
            || pencereKatmaniSecili != sabitleme.pencereKatmani || kesinModSecili != sabitleme.kesinMod
    }

    // MARK: Eylemler — kuyruk

    private func arkada<T: Sendable>(mesaj islem: String? = nil, _ govde: @escaping @Sendable () throws -> T) async -> T? {
        var benim = 0
        if let islem {
            mesgulSayaci += 1
            benim = mesgulSayaci
            mesgul = islem
        }
        // Yalnız en son başlayan işlem meşgul yazısını kaldırır (kısa bir işlem uzun olanın yazısını silmesin).
        defer { if islem != nil, mesgulSayaci == benim { mesgul = nil } }
        do {
            return try await Task.detached(priority: .userInitiated) { try govde() }.value
        } catch {
            goster(error.localizedDescription, .hata)
            return nil
        }
    }

    func eylem(_ e: HizliEylem) async {
        switch e {
        case .surdur: await kuyruguSurdur()
        case .uyarilariTemizle: await uyarilariTemizle()
        case .bekleyenleriSerbestBirak: await bekleyenleriSerbestBirak()
        case .gorevliyiBaslat: await gorevliyiYenidenBaslat()
        case .bekletmeyiKaldir: await bekletmeyiKaldir()
        case .yenile:
            if kuyruk == nil { await kuyruklariYenidenTara() } else { await yenile(cihazDahil: true) }
        }
    }

    func kuyruguSurdur() async {
        let ad = kuyrukAdi
        if await arkada(mesaj: "Kuyruk sürdürülüyor…", { try Komut.kuyruguSurdur(ad) }) != nil {
            goster("Kuyruk sürdürüldü", .basari)
        }
        await yenile(cihazDahil: true)
    }

    func kuyruguDurdur() async {
        let ad = kuyrukAdi
        if await arkada(mesaj: "Kuyruk durduruluyor…", { try CUPSIstemci.kuyruguDurdur(ad) }) != nil {
            goster("Kuyruk durduruldu; yeni işler bekleyecek", .bilgi)
        }
        await yenile()
    }

    func uyarilariTemizle() async {
        let ad = kuyrukAdi
        if await arkada(mesaj: "Uyarılar temizleniyor…", { try CUPSIstemci.uyarilariTemizle(ad) }) != nil {
            goster("Eski uyarılar temizlendi", .basari)
        }
        await yenile()
    }

    func isIptal(_ id: Int) async {
        if await arkada({ try CUPSIstemci.isIptal(id) }) != nil { goster("İş #\(id) iptal edildi", .bilgi) }
        await yenile()
    }

    func isBeklet(_ id: Int) async {
        if await arkada({ try CUPSIstemci.isBeklet(id) }) != nil { goster("İş #\(id) bekletiliyor", .bilgi) }
        await yenile()
    }

    func isSurdur(_ id: Int) async {
        // Kesin mod açıkken elle sürdürülen iş de sabit ayarları alsın.
        // Görevlinin kullandığı kuralların aynısı: bakım komutuna ve fotoğraf kağıdındaki kaliteye dokunulmaz.
        let cfg = sabitleme, k = katalog
        let is_ = isler.first { $0.id == id }
        let sonuc: Void? = await arkada { () -> Void in
            if cfg.aktifKesinMod, let is_, is_.sabitlemeIsareti == nil {
                var s = IsDenetleyici.isSecenekleri(is_, cfg: cfg, katalog: k).secenekler
                s[Sabitleme.isaretOzniteligi] = is_.komutIsi ? "komut" : (s.isEmpty ? "serbest" : "1")
                s["job-hold-until"] = "no-hold"
                try CUPSIstemci.isAyarla(id, s)
            } else {
                try CUPSIstemci.isSurdur(id)
            }
        }
        if sonuc != nil { goster("İş #\(id) sürdürüldü", .basari) }
        await yenile()
    }

    func isYenidenBas(_ id: Int) async {
        if await arkada({ try CUPSIstemci.isYenidenBas(id) }) != nil { goster("İş #\(id) yeniden yazdırılıyor", .basari) }
        await yenile()
    }

    func tumunuIptal() async {
        let kimlikler = isler.filter { $0.durum.etkin }.map(\.id)
        guard !kimlikler.isEmpty else { return }
        let hatalar = await arkada(mesaj: "İşler iptal ediliyor…") { () -> [String] in
            var h: [String] = []
            for id in kimlikler {
                do { try CUPSIstemci.isIptal(id) } catch { h.append("#\(id): \(error.localizedDescription)") }
            }
            return h
        } ?? []
        if hatalar.isEmpty { goster("\(kimlikler.count) iş iptal edildi", .bilgi) } else { goster(hatalar.joined(separator: "\n"), .hata) }
        await yenile()
    }

    func bekleyenleriSerbestBirak() async {
        let cfg = sabitleme, k = katalog
        let sonuc = await arkada(mesaj: "İşler gönderiliyor…") { () -> IsDenetleyici.Sonuc in
            var islenenler = Set<Int>()
            return IsDenetleyici.isle(cfg, katalog: k, islenenler: &islenenler, asgariYas: 0)
        } ?? IsDenetleyici.Sonuc()
        sonuc.kayitlar.forEach { Gunluk.yaz($0) }
        if sonuc.hatali > 0 {
            goster(sonuc.kayitlar.joined(separator: "\n"), .hata)
        } else {
            goster(sonuc.islenen == 0 ? "Bekleyen iş yok" : "\(sonuc.islenen) iş gönderildi", .basari)
        }
        await yenile()
    }

    /// Kesin mod kapalıyken kuyrukta kalmış iş bekletme ayarını kapatır.
    func bekletmeyiKaldir() async {
        let ad = sabitleme.kuyruk.isEmpty ? kuyrukAdi : sabitleme.kuyruk
        if await arkada(mesaj: "Ayar değiştiriliyor…", { try Komut.lpadmin(ad, [("job-hold-until-default", "no-hold")]) }) != nil {
            goster("Yeni işler artık bekletilmeyecek. Bekleyen işleri kuyruktan sürdürebilirsiniz.", .basari)
        }
        await yenile()
    }

    func gorevliyiYenidenBaslat() async {
        if await arkada(mesaj: "Görevli başlatılıyor…", { try GorevliYoneticisi.yenidenBaslat() }) != nil {
            goster("Arka plan görevlisi çalışıyor", .basari)
        }
        await yenile()
    }

    // MARK: Eylemler — sabitleme

    /// Düzenleyicideki kilitli ayarları sabitler.
    func duzenleyicidekileriSabitle() async {
        await sabitle(duzenlenen.sadece(kilitli), pencere: pencereKatmaniSecili, kesin: kesinModSecili, hazirAyarAdi: nil)
    }

    /// `kuyruk` verilmezse o an seçili yazıcıya uygulanır; başka bir yazıcı sabitliyse önce o geri alınır.
    func sabitle(_ ayarlar: BaskiAyarSeti, pencere: Bool, kesin: Bool, hazirAyarAdi: String?, kuyruk: String? = nil) async {
        guard !ayarlar.bos else {
            await sabitlemeyiKaldir()
            return
        }
        var cfg = sabitleme
        cfg.kuyruk = kuyruk ?? kuyrukAdi
        cfg.ayarlar = ayarlar
        cfg.pencereKatmani = pencere
        cfg.kesinMod = kesin
        cfg.hazirAyarAdi = hazirAyarAdi
        let gonderilen = cfg
        if let rapor = await arkada(mesaj: "Ayarlar sabitleniyor…", { try Sabitleme.uygula(gonderilen) }) {
            sabitleme = SabitlemeYapilandirmasi.yukle()
            yedek = SabitlemeYedegi.yukle()
            goster("Sabitlendi: \(ayarlar.ozet(katalog: katalog))" + (rapor.uyarilar.isEmpty ? "" : "\n" + rapor.uyarilar.joined(separator: "\n")),
                   rapor.uyarilar.isEmpty ? .basari : .bilgi)
        } else {
            sabitleme = SabitlemeYapilandirmasi.yukle()
        }
        await kataloguYukle()
        duzenleyiciyiSifirla()
        await yenile()
    }

    func sabitlemeyiKaldir() async {
        // Her zaman sabitlenen yazıcıda geri al (o an seçili yazıcı farklı olabilir).
        let ad = sabitleme.kuyruk.isEmpty ? kuyrukAdi : sabitleme.kuyruk
        if let rapor = await arkada(mesaj: "Sabitleme kaldırılıyor…", { try Sabitleme.kaldir(kuyruk: ad) }) {
            goster("Sabitleme kaldırıldı, özgün ayarlar geri yüklendi"
                   + (rapor.uyarilar.isEmpty ? "" : "\n" + rapor.uyarilar.joined(separator: "\n")), .basari)
        }
        sabitleme = SabitlemeYapilandirmasi.yukle()
        yedek = SabitlemeYedegi.yukle()
        await kataloguYukle()
        duzenleyiciyiSifirla()
        await yenile()
    }

    /// Sabitlemeyi koruyarak yalnız kesin modu açar/kapatır.
    func kesinModuAyarla(_ acik: Bool) async {
        guard sabitleme.etkin else { kesinModSecili = acik; return }
        await sabitle(sabitleme.ayarlar, pencere: sabitleme.pencereKatmani, kesin: acik,
                      hazirAyarAdi: sabitleme.hazirAyarAdi, kuyruk: sabitleme.kuyruk.isEmpty ? nil : sabitleme.kuyruk)
    }

    // MARK: Eylemler — hazır ayarlar

    func hazirAyariSabitle(_ h: HazirAyar) async {
        // Sabitleme kapalıysa Baskı Ayarları'ndaki "pencere" ve "kesin mod" seçimleri kullanılır.
        await sabitle(h.ayarlar, pencere: sabitleme.etkin ? sabitleme.pencereKatmani : pencereKatmaniSecili,
                      kesin: sabitleme.etkin ? sabitleme.kesinMod : kesinModSecili, hazirAyarAdi: h.ad)
    }

    func hazirAyariDuzenleyiciyeYukle(_ h: HazirAyar) {
        duzenlenen = duzenlenen.birlestir(h.ayarlar)
        kilitli = h.ayarlar.doluAnahtarlar
        secilenBolum = .baskiAyarlari
    }

    func hazirAyarKaydet(ad: String, simge: String, aciklama: String, ayarlar: BaskiAyarSeti) {
        let yeni = HazirAyar(id: UUID(), ad: ad, simge: simge, aciklama: aciklama, ayarlar: ayarlar, yerlesik: false)
        hazirAyarlar.append(yeni)
        hazirAyarlariKaydet()
        goster("\"\(ad)\" kaydedildi", .basari)
    }

    func hazirAyarGuncelle(_ h: HazirAyar) {
        guard let i = hazirAyarlar.firstIndex(where: { $0.id == h.id }), !h.yerlesik else { return }
        hazirAyarlar[i] = h
        hazirAyarlariKaydet()
    }

    func hazirAyarSil(_ h: HazirAyar) {
        guard !h.yerlesik else { return }
        hazirAyarlar.removeAll { $0.id == h.id }
        hazirAyarlariKaydet()
        goster("\"\(h.ad)\" silindi", .bilgi)
    }

    private func hazirAyarlariKaydet() {
        do { try HazirAyarDeposu.kaydet(hazirAyarlar) } catch { goster(error.localizedDescription, .hata) }
    }

    /// Şu an sabitlenmiş ayarlarla eşleşen hazır ayar.
    var etkinHazirAyar: HazirAyar? {
        guard sabitleme.etkin else { return nil }
        return hazirAyarlar.first { $0.ayarlar == sabitleme.ayarlar }
    }

    // MARK: Eylemler — bakım

    // Bakım ve cihaz ayarları yazıcıya doğrudan ağdan, Canon'un IVEC komut biçimiyle gider (CanonAg.swift).
    // Mac'teki kuyruk kullanılmaz: sürücünün eski BJL bakım komutlarını G3010 yok sayıyor.

    /// Yazıcının kendi ayarları (otomatik açılma/kapanma, sessiz mod, kalan mürekkep bildirimi).
    var cihazAyarlari: IVEC.CihazAyarlari?
    var cihazAyarHatasi: String?
    var cihazAyarOkunuyor = false
    var cihazAyarUygulaniyor = false
    /// Son bakım işleminin canlı durumu (yazıcının durumu yoklanarak güncellenir).
    var bakimCanli: BakimCanliDurum?
    @ObservationIgnored private var bakimIzleyici: Task<Void, Never>?

    /// Bir bakım işlemi sürüyor mu (yeni işlem ya da ayar gönderilmesin)?
    var bakimSuruyor: Bool { bakimCanli?.suruyor ?? false }

    private var kuyrukYazdiriyor: Bool { kuyruk?.durum == .yazdiriyor || etkinIs?.durum == .yazdiriliyor }

    private static let adresYokMetni = "Yazıcının ağ adresi bulunamadı. Yazıcı açık ve bu Mac ile aynı ağda olmalı."

    /// Komutların gideceği yazıcı adresi (IP ya da .local adı). Henüz bilinmiyorsa bir kez aranır.
    private func yaziciHostu() async -> String? {
        if cihazAdresi == nil { await yenile(cihazDahil: true) }
        return cihazAdresi?.host
    }

    /// Bakım ya da ayar göndermeye engel varsa açıklaması.
    private func gondermeEngeli() -> String? {
        if bakimSuruyor { return "Bir bakım işlemi sürüyor; bitmesini bekleyin." }
        if cihazAyarUygulaniyor { return "Yazıcıya ayar gönderiliyor; bitmesini bekleyin." }
        if kuyrukYazdiriyor { return "Yazıcı şu an baskı yapıyor. Baskı bitince tekrar deneyin." }
        return nil
    }

    /// Yazıcının cihaz ayarlarını okur (salt okunur, CHMP).
    func cihazAyarlariniOku() async {
        guard !cihazAyarOkunuyor else { return }
        cihazAyarOkunuyor = true
        defer { cihazAyarOkunuyor = false }
        guard let host = await yaziciHostu() else {
            cihazAyarHatasi = Self.adresYokMetni
            return
        }
        let sonuc = await Task.detached(priority: .userInitiated) {
            Result { try CanonCihaz.ayarlar(host: host) }
        }.value
        switch sonuc {
        case .success(let a):
            cihazAyarlari = a
            cihazAyarHatasi = nil
        case .failure(let e):
            cihazAyarHatasi = e.localizedDescription
        }
    }

    /// Cihaz ayarını yazıcıya uygular ve okuyarak doğrular; doğrulanınca `cihazAyarlari` güncellenir.
    @discardableResult
    func cihazAyariUygula(xml: String, dogrula: @escaping @Sendable (IVEC.CihazAyarlari) -> Bool,
                          aciklama: String) async -> Bool {
        if let engel = gondermeEngeli() { goster(engel, .bilgi); return false }
        cihazAyarUygulaniyor = true
        defer { cihazAyarUygulaniyor = false }
        guard let host = await yaziciHostu() else { goster(Self.adresYokMetni, .hata); return false }
        let sonuc = await Task.detached(priority: .userInitiated) {
            Result { try CanonCihaz.ayarGonder(host: host, xml, dogrula: dogrula) }
        }.value
        switch sonuc {
        case .success(let a):
            cihazAyarlari = a
            cihazAyarHatasi = nil
            Gunluk.yaz("Yazıcı ayarı uygulandı: \(aciklama)")
            goster("\(aciklama) — yazıcıya uygulandı", .basari)
            return true
        case .failure(let e):
            Gunluk.yaz("Yazıcı ayarı uygulanamadı: \(aciklama) — \(e.localizedDescription)")
            goster("\(aciklama): \(e.localizedDescription)", .hata)
            cihazAyarUygulaniyor = false
            await cihazAyarlariniOku()   // ekrandaki değerler yazıcıdakiyle aynı olsun
            return false
        }
    }

    /// Bakım işlemini yazıcıya gönderir; yazıcının durumunu arka planda izleyip `bakimCanli`yı günceller.
    /// Gönderildiyse true döner (işlemin bitmesini beklemez).
    @discardableResult
    func bakimBaslat(_ islem: BakimIslemi, grup: TemizlikGrubu = .tum) async -> Bool {
        if let engel = gondermeEngeli() { goster(engel, .bilgi); return false }
        let ad = islem.baslik(grup: grup)
        let gonderim = islem.gonderim(grup: grup)
        var canli = BakimCanliDurum(tur: islem.tur, ad: ad, asama: .gonderiliyor,
                                    mesaj: "Yazıcıya gönderiliyor…", baslangic: Date())
        bakimIzleyici?.cancel()
        bakimCanli = canli

        guard let host = await yaziciHostu() else {
            bakimSonuclandir(canli.id, .hata, Self.adresYokMetni)
            goster(Self.adresYokMetni, .hata)
            return false
        }
        let sonuc = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            Result {
                switch gonderim {
                case .bakim(let islemAdi, let icerik):
                    try CanonCihaz.bakimGonder(host: host, islem: islemAdi, icerik: icerik)
                case .sayacSifirla:
                    try CanonCihaz.murekkepSayaciniSifirla(host: host)
                }
            }
        }.value
        if case .failure(let e) = sonuc {
            Gunluk.yaz("Bakım gönderilemedi: \(ad) — \(e.localizedDescription)")
            bakimSonuclandir(canli.id, .hata, e.localizedDescription)
            goster("\(ad) gönderilemedi: \(e.localizedDescription)", .hata)
            return false
        }
        Gunluk.yaz("Bakım gönderildi: \(ad) → \(host)")
        guard case .bakim = gonderim else {
            // Mürekkep sayacı: yazıcı komutu anında onayladı (onaylamasaydı yukarıda hata dönerdi).
            bakimSonuclandir(canli.id, .bitti, islem.bittiMetni)
            goster("\(ad): yazıcı onayladı", .basari)
            return true
        }
        canli.mesaj = "Yazıcının başlaması bekleniyor…"
        canli.izleniyor = true
        bakimCanli = canli
        let kimlik = canli.id
        bakimIzleyici = Task { [weak self] in
            await self?.bakimiIzle(islem, ad: ad, host: host, kimlik: kimlik)
        }
        return true
    }

    /// Biten bakımın sonucunu ekrandan kaldırır.
    /// Süren bakımı yazıcıya iptal ettirir (CancelJob). İzleme boşa dönüşü görünce "durduruldu" der.
    func bakimiDurdur() async {
        guard let c = bakimCanli, c.durdurulabilir, !c.durdurmaIstendi, let host = cihazAdresi?.host else { return }
        bakimCanli?.durdurmaIstendi = true
        let sonuc = await Task.detached { Result { try CanonCihaz.bakimiDurdur(host: host) } }.value
        guard bakimCanli?.id == c.id else { return }
        switch sonuc {
        case .success:
            Gunluk.yaz("Bakım durdurma gönderildi: \(c.ad)")
            bakimGuncelle(c.id, .calisiyor, Self.durduruluyorMetni)
        case .failure(let e):
            bakimCanli?.durdurmaIstendi = false
            goster("Durdurulamadı: \(e.localizedDescription)", .hata)
        }
    }

    private static let durduruluyorMetni = "Durduruluyor… Yazıcı kafayı yerine alıp birkaç saniyede durur."

    func bakimSonucunuKapat() {
        guard bakimCanli?.suruyor == false else { return }
        bakimCanli = nil
    }

    /// Yazıcının CHMP durumunu 1,5 sn'de bir yoklar (en çok 8 dk). Boşta değilse "çalışıyor";
    /// çalıştıktan sonra boşa dönünce "bitti"; 20 sn'de hiç başlamazsa uyarı; durursa Canon'un metniyle hata.
    /// Yazıcının "durdu" dediği ama işlemin olağan adımı olan destek kodları → kullanıcıya talimat.
    private static let beklenenDurmalar: [String: String] = [
        "2901": "Hizalama deseni basıldı. Sayfayı yazılı yüzü aşağı gelecek şekilde tarayıcı camına koyun, kapağı kapatın ve yazıcının Başlat (Start) düğmesine basın. Yazıcı deseni tarayıp kafayı hizalar.",
    ]

    private func bakimiIzle(_ islem: BakimIslemi, ad: String, host: String, kimlik: UUID) async {
        let baslangic = Date()
        var sonOkuma = Date()
        var basladi = false
        var durmaGoruldu = false
        var sonDurmaKodu: String?
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, bakimCanli?.id == kimlik else { return }
            let gecen = Date().timeIntervalSince(baslangic)
            let durum = await Task.detached(priority: .utility) { try? CanonCihaz.durum(host: host) }.value
            if let d = durum {
                sonOkuma = Date()
                if d.durum == "stopped", let kod = d.destekKodu, let adim = Self.beklenenDurmalar[kod] {
                    // İşlemin olağan bir adımı (ör. hizalama deseni taratılmayı bekliyor): hata sayılmaz.
                    basladi = true
                    if sonDurmaKodu != kod {
                        sonDurmaKodu = kod
                        Gunluk.yaz("Bakım: \(ad) — kullanıcı bekleniyor (destek kodu \(kod))")
                        bakimGuncelle(kimlik, .calisiyor, adim)
                        goster("\(ad): \(adim)", .bilgi)
                    }
                } else if d.durum == "stopped" {
                    // Kağıt yok gibi durumlarda kullanıcı sorunu giderince yazıcı sürer; izleme devam eder.
                    basladi = true
                    durmaGoruldu = true
                    let kod = d.destekKodu ?? ""
                    if sonDurmaKodu != kod {
                        sonDurmaKodu = kod
                        let metin = kod.isEmpty ? "Yazıcı durdu. Yazıcının ışıklarına bakın."
                            : (CanonMetinleri.shared.hata(kod: kod) ?? "Yazıcı durdu (destek kodu \(kod)).")
                        let kisa = kod.isEmpty ? nil : CanonMetinleri.shared.kisaBaslik(kod: kod)
                        Gunluk.yaz("Bakım: \(ad) — yazıcı durdu" + (kod.isEmpty ? "" : " (destek kodu \(kod))"))
                        bakimGuncelle(kimlik, .hata, metin)
                        goster("\(ad): \(kisa ?? "yazıcı durdu")", .hata)
                    }
                } else if !d.bosta {
                    basladi = true
                    sonDurmaKodu = nil
                    bakimGuncelle(kimlik, .calisiyor,
                                  bakimCanli?.durdurmaIstendi == true ? Self.durduruluyorMetni : islem.calisiyorMetni)
                } else if basladi {
                    if bakimCanli?.durdurmaIstendi == true {
                        Gunluk.yaz("Bakım durduruldu: \(ad), \(Int(gecen)) sn")
                        bakimSonuclandir(kimlik, .uyari, "Durduruldu; işlem yarıda kaldı. Gerekirse yeniden başlatın.")
                        goster("\(ad) durduruldu", .bilgi)
                    } else if durmaGoruldu {
                        Gunluk.yaz("Bakım sona erdi (arada durdu): \(ad), \(Int(gecen)) sn")
                        bakimSonuclandir(kimlik, .uyari, "İşlem sona erdi ama arada yazıcı durdu. Sonucu yazıcıda kontrol edin.")
                        goster("\(ad) sona erdi; sonucu kontrol edin", .bilgi)
                    } else {
                        Gunluk.yaz("Bakım bitti: \(ad), \(Int(gecen)) sn")
                        bakimSonuclandir(kimlik, .bitti, islem.bittiMetni)
                        goster("\(ad) bitti", .basari)
                    }
                    return
                } else if gecen > 20 {
                    Gunluk.yaz("Bakım: \(ad) — yazıcı işi başlatmadı")
                    bakimSonuclandir(kimlik, .uyari,
                                     "Yazıcı işi başlatmadı. Yazıcının açık ve hazır olduğunu kontrol edip tekrar deneyin.")
                    goster("\(ad): yazıcı işi başlatmadı", .hata)
                    return
                }
            } else if Date().timeIntervalSince(sonOkuma) > 60 {
                Gunluk.yaz("Bakım: \(ad) — yazıcının durumu okunamıyor, izleme bırakıldı")
                bakimSonuclandir(kimlik, .uyari, "Yazıcının durumu okunamıyor. Sonucu yazıcıda kontrol edin.")
                goster("\(ad): yazıcının durumu okunamıyor", .bilgi)
                return
            }
            if gecen > 8 * 60 {
                Gunluk.yaz("Bakım: \(ad) — 8 dakikada bitmedi, izleme bırakıldı")
                bakimSonuclandir(kimlik, .uyari, "Yazıcı 8 dakikadır çalışıyor; izleme bırakıldı. Bitince sonucu kontrol edin.")
                return
            }
        }
    }

    private func bakimGuncelle(_ kimlik: UUID, _ asama: BakimCanliDurum.Asama, _ mesaj: String) {
        guard var c = bakimCanli, c.id == kimlik, c.asama != asama || c.mesaj != mesaj else { return }
        c.asama = asama
        c.mesaj = mesaj
        bakimCanli = c
    }

    /// Canlı durumu sonuçlandırır (bu arada başka bir işlem başladıysa dokunmaz).
    private func bakimSonuclandir(_ kimlik: UUID, _ asama: BakimCanliDurum.Asama, _ mesaj: String) {
        guard var c = bakimCanli, c.id == kimlik else { return }
        c.asama = asama
        c.mesaj = mesaj
        c.izleniyor = false
        c.bitis = Date()
        bakimCanli = c
    }

    // MARK: Eylemler — yazdırma

    /// Dosyaları verilen ayarlarla yazdırır. Kesin moddaki görevli bu işlere dokunmaz (işaretli).
    @discardableResult
    func dosyalariYazdir(_ dosyalar: [URL], ayarlar: BaskiAyarSeti, secenekler: YazdirmaSecenekleri) async -> [URL: Int] {
        let ad = kuyrukAdi, k = katalog
        var tum = ayarlar.isSecenekleri(katalog: k)
        var ozetAyar = ayarlar
        if let o = ayarlar.ortam, o != "0" {
            // Fotoğraf kağıdında kalite anahtarları işe konmaz; eksikler PPD varsayılanından (ör. sabit taslak)
            // gelirse yazıcı 4103 verir. Güvenli kalite açıkça yazılır (Chrome köprüsündekiyle aynı).
            let guvenli = BaskiAyarSeti(kalite: .standart, ortam: "0").isSecenekleri(katalog: k)
            for (a, d) in guvenli where BaskiAyarSeti.kaliteAnahtarlari.contains(a) { tum[a] = d }
            ozetAyar.kalite = nil
        }
        for (a, d) in secenekler.cupsSecenekleri() { tum[a] = d }
        tum["job-hold-until"] = "no-hold"
        tum[Sabitleme.isaretOzniteligi] = "uygulama"
        let gonderilecek = tum
        // Her dosya ayrı denenir: biri başarısız olsa da gönderilenler kaybolmaz (ikinci kez basılmasın).
        let (sonuc, hatalar) = await arkada(mesaj: dosyalar.count > 1 ? "\(dosyalar.count) dosya gönderiliyor…" : "Gönderiliyor…") { () -> ([URL: Int], [String]) in
            var numaralar: [URL: Int] = [:]
            var hatalar: [String] = []
            for d in dosyalar {
                let erisim = d.startAccessingSecurityScopedResource()
                defer { if erisim { d.stopAccessingSecurityScopedResource() } }
                do {
                    numaralar[d] = try CUPSIstemci.dosyaYazdir(kuyruk: ad, dosya: d, baslik: d.lastPathComponent,
                                                               secenekler: gonderilecek)
                } catch {
                    hatalar.append("\(d.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return (numaralar, hatalar)
        } ?? ([:], [])
        if !hatalar.isEmpty {
            goster((sonuc.isEmpty ? "" : "\(sonuc.count) dosya gönderildi, ") + "gönderilemeyen: " + hatalar.joined(separator: "\n"), .hata)
        } else if !sonuc.isEmpty {
            goster(sonuc.count == 1 ? "Yazdırılıyor (iş #\(sonuc.values.first ?? 0))" : "\(sonuc.count) dosya yazdırılıyor", .basari)
            Gunluk.yaz("Hızlı yazdır: \(dosyalar.map(\.lastPathComponent).joined(separator: ", ")) — \(ozetAyar.ozet(katalog: k))")
        }
        await yenile()
        return sonuc
    }

    /// Elle çift taraf, 1. adım: tek sayfaları basar ve oturumu açar (bölüm değişse de korunur).
    /// 1. geçiş her zaman "son sayfa önce" gider (G3010'un PPD varsayılanı; çıkan deste 1. sayfa üstte
    /// okunur sırada durur). 2. geçiş varsayılan olarak aynı sırayla gider; tutmazsa kullanıcı çevirir.
    @discardableResult
    func elleCiftTarafBaslat(_ dosya: URL, ayarlar: BaskiAyarSeti, secenekler: YazdirmaSecenekleri) async -> ElleCiftTaraf.Hazirlik? {
        let erisim = dosya.startAccessingSecurityScopedResource()
        defer { if erisim { dosya.stopAccessingSecurityScopedResource() } }
        let nup = secenekler.yaprakBasinaSayfa
        guard let hazirlik = await arkada({ try ElleCiftTaraf.hazirla(dosya, yaprakBasinaSayfa: nup) }) else { return nil }
        var s = secenekler
        s.sayfaKumesi = .tek
        s.sayfaAraligi = ""
        s.cikisSirasi = .ters
        let numaralar = await dosyalariYazdir([hazirlik.dosya], ayarlar: ayarlar, secenekler: s)
        guard !numaralar.isEmpty else { return nil }
        ciftTarafOturumu = ElleCiftTarafOturumu(hazirlik: hazirlik, ad: dosya.lastPathComponent,
                                                ayarlar: ayarlar, secenekler: s)
        ciftTarafSirayiCevir = false
        return hazirlik
    }

    /// Elle çift taraf, 2. adım: çift sayfaları 1. adımla aynı ayarlarla basar. Başarılıysa oturumu kapatır;
    /// başarısızsa oturum kalır, yeniden denenebilir.
    @discardableResult
    func elleCiftTarafBitir() async -> Bool {
        guard let o = ciftTarafOturumu else { return false }
        var s = o.secenekler
        s.sayfaKumesi = .cift
        s.cikisSirasi = ciftTarafSirayiCevir ? .normal : .ters
        let sonuc = await dosyalariYazdir([o.hazirlik.dosya], ayarlar: o.ayarlar, secenekler: s)
        guard !sonuc.isEmpty else { return false }
        elleCiftTarafVazgec()
        return true
    }

    func elleCiftTarafVazgec() {
        if let o = ciftTarafOturumu, o.hazirlik.bosSayfaEklendi {
            try? FileManager.default.removeItem(at: o.hazirlik.dosya)   // yalnız bizim oluşturduğumuz geçici kopya
        }
        ciftTarafOturumu = nil
        ciftTarafSirayiCevir = false
    }

    // MARK: Eylemler — yazıcı

    func hataPolitikasiAyarla(kagitBitinceDurdur: Bool) async {
        let ad = kuyrukAdi
        let deger = kagitBitinceDurdur ? "stop-printer" : "retry-current-job"
        if await arkada(mesaj: "Ayar değiştiriliyor…", { try Komut.lpadmin(ad, [("printer-error-policy", deger)]) }) != nil {
            goster(kagitBitinceDurdur ? "Hata olunca kuyruk durdurulacak (macOS varsayılanı)"
                                      : "Hata olunca kuyruk durmayacak; iş yeniden denenecek", .basari)
        }
        await yenile()
    }

    func yaziciyiTanit() async {
        guard let adres = cihazAdresi else { goster("Yazıcının ağ adresi bilinmiyor", .hata); return }
        if await arkada({ try CUPSIstemci.yaziciyiTanit(adres) }) != nil {
            goster("Yazıcının ışıkları yanıp sönmeli", .bilgi)
        }
    }

    func girisBaslatAyarla(_ acik: Bool) {
        do {
            if acik { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            goster("Giriş öğesi ayarlanamadı: \(error.localizedDescription)", .hata)
        }
        girisBaslat = SMAppService.mainApp.status == .enabled
        if acik && SMAppService.mainApp.status == .requiresApproval {
            goster("Sistem Ayarları › Genel › Giriş Öğeleri'nden onay verin", .bilgi)
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: Chrome eklentisi

    var chromeKopruKurulu = false
    var chromeEklentiYuklu = false

    func chromeDurumunuYenile(kur: Bool = false) async {
        let (kurulu, yuklu) = await Task.detached { () -> (Bool, Bool) in
            if kur { ChromeKoprusu.kur() }
            return (ChromeKoprusu.kurulu, ChromeKoprusu.eklentiYuklu)
        }.value
        chromeKopruKurulu = kurulu
        chromeEklentiYuklu = yuklu
    }

    func chromeEklentiKlasorunuGoster() {
        NSWorkspace.shared.activateFileViewerSelecting([ChromeKoprusu.eklentiKlasoru])
    }

    func chromeEklentilerSayfasiniAc() {
        // Chrome dışarıdan chrome:// adresi açmayı kabul etmeyebilir; en azından Chrome öne gelir.
        Komut.calistir("/usr/bin/open", ["-a", "Google Chrome", "chrome://extensions"], zamanAsimi: 10)
    }

    // MARK: Bağlantılar

    func canonYardimciPrograminiAc() {
        let yol = katalog?.yardimciProgramYolu ?? "/Library/Printers/Canon/BJPrinter/Utilities/CanonIJPrinterUtility.app"
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: yol), configuration: NSWorkspace.OpenConfiguration())
    }

    func yaziciWebSayfasiniAc() {
        if let u = cihaz?.webAdresi { NSWorkspace.shared.open(u) }
        else if let a = cihazAdresi, let u = URL(string: "http://\(a.host)/") { NSWorkspace.shared.open(u) }
    }

    func sistemYaziciAyarlariniAc() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension") {
            NSWorkspace.shared.open(u)
        }
    }

    func gunlukDosyasiniAc() { NSWorkspace.shared.open(Depo.dosya(Gunluk.dosyaAdi)) }

    func gunluguYukle() {
        gunlukSatirlari = Gunluk.sonSatirlar(300).reversed()
    }

    // MARK: Bildirimler

    func goster(_ metin: String, _ tur: Bildirim.Tur) {
        let b = Bildirim(tur: tur, metin: metin)
        bildirim = b
        bildirimGorevi?.cancel()
        bildirimGorevi = Task { [weak self] in
            try? await Task.sleep(for: .seconds(tur == .hata ? 7 : 4))
            guard !Task.isCancelled, self?.bildirim?.id == b.id else { return }
            self?.bildirim = nil
        }
    }

    private func bildirimIzniIste() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Yeni bir sorun çıkınca (uygulama arka plandayken) sistem bildirimi gönderir.
    private func sorunBildiriminiDegerlendir() {
        let ozet = durumOzeti
        let anahtar = ozet.seviye >= .uyari ? ozet.baslik : nil
        defer { sonBildirilenSorun = anahtar }
        guard bildirimlerAcik, let anahtar, anahtar != sonBildirilenSorun, !NSApp.isActive,
              Bundle.main.bundleIdentifier != nil else { return }
        let icerik = UNMutableNotificationContent()
        icerik.title = "Yazıcı: \(ozet.baslik)"
        if let a = ozet.ayrinti { icerik.body = a }
        icerik.sound = .default
        let istek = UNNotificationRequest(identifier: "yazici-sorun", content: icerik, trigger: nil)
        UNUserNotificationCenter.current().add(istek)
    }
}
