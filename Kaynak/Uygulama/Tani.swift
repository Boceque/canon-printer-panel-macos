import Foundation

/// `YaziciPaneli --tani`: arayüzsüz teşhis. Kuyruk, yazıcı, işler, PPD ve sabitleme durumunu yazar.
///   --tani            özet
///   --tani --ppd      tüm PPD seçenekleri
///   --tani --gunluk   son günlük satırları
///   --tani --cihaz    yazıcının kendi durumu ve cihaz ayarları (Canon CHMP, salt okunur)
enum Tani {
    static func calistir(_ arg: [String]) {
        guard let kuyruk = CUPSIstemci.canonKuyrugu() else {
            print("Yazıcı kuyruğu bulunamadı.")
            return
        }
        print("== Kuyruk: \(kuyruk)")
        do {
            let k = KuyrukDurumu(try CUPSIstemci.kuyrukOznitelikleri(kuyruk))
            print("durum: \(k.durum.ad) · iş kabul: \(k.isKabulEdiyor) · bekleyen: \(k.bekleyenIsSayisi)")
            print("nedenler: \(k.nedenler.map { "\($0.ham) → \($0.baslik)" }.joined(separator: "; "))")
            print("hata politikası: \(k.hataPolitikasi ?? "?") · bekletme varsayılanı: \(k.isBeklemeVarsayilani ?? "?")")
            print("aygıt: \(k.aygitAdresi)")
            if let (ad, alan) = CihazBulucu.bonjourAdi(k.aygitAdresi) { print("bonjour: \(ad) @ \(alan)") }
        } catch {
            print("kuyruk okunamadı: \(error.localizedDescription)")
        }

        print("\n== İşler")
        if let isler = try? CUPSIstemci.isler(kuyruk, tamamlanan: false).map(YaziciIsi.init) {
            if isler.isEmpty { print("(etkin iş yok)") }
            for i in isler {
                print("#\(i.id) \(i.durum.ad) \"\(i.ad)\" pq=\(i.kalite ?? "-") gri=\(i.griTon ?? "-") ortam=\(i.ortam ?? "-") bekletme=\(i.bekletmeZamani ?? "-") işaret=\(i.sabitlemeIsareti ?? "-") nedenler=\(i.nedenler)")
            }
        }
        if let biten = try? CUPSIstemci.isler(kuyruk, tamamlanan: true).map(YaziciIsi.init) {
            print("tamamlanan iş sayısı: \(biten.count); son 3: " + biten.sorted { $0.id > $1.id }.prefix(3)
                .map { "#\($0.id) \($0.durum.ad) \($0.ad) pq=\($0.kalite ?? "-")" }.joined(separator: " | "))
        }

        print("\n== PPD")
        if let katalog = PPDKatalogu.oku(CUPSIstemci.ppdYolu(kuyruk)) {
            print("model: \(katalog.model) · sürüm: \(katalog.surum) · seçenek: \(katalog.secenekler.count)")
            let mevcut = BaskiAyarSeti.varsayilanlardan(katalog)
            print("varsayılanlar: \(mevcut.ozet(katalog: katalog))")
            for a in ["CNIJPrintQuality", "CNIJMediaType", "PageSize", "CNIJGrayScale", "CNIJGamma2"] {
                if let s = katalog[a] {
                    print("  \(s.ad) [\(a)] = \(s.varsayilan ?? "?") · " + s.secimler.prefix(8).map { "\($0.kod):\($0.ad)" }.joined(separator: ", "))
                }
            }
            if arg.contains("--ppd") {
                for a in katalog.sira { if let s = katalog[a] { print("  \(a) (\(s.ad)) = \(s.varsayilan ?? "?") [\(s.secimler.map(\.kod).joined(separator: ","))]") } }
            }
        } else {
            print("PPD okunamadı")
        }

        print("\n== Sabitleme")
        let cfg = SabitlemeYapilandirmasi.yukle()
        print("etkin: \(cfg.etkin) · kesin mod: \(cfg.kesinMod) · pencere: \(cfg.pencereKatmani) · ayarlar: \(cfg.ayarlar.ozet())")
        if let y = SabitlemeYedegi.yukle() { print("yedek: aktif=\(y.aktif) alınma=\(y.alinma) ppd=\(y.ppd.count) anahtar") }
        let p = PencereKatmani.anlikGoruntu(kuyruk)
        print("pencere (yazıcı): \(p.yazici.map { $0.compactMapValues { $0 }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") } ?? "yok")")
        print("görevli: yüklü=\(GorevliYoneticisi.yuklu) · canlı=\(GorevliDurumu.yukle()?.canli ?? false) · program=\(GorevliYoneticisi.program ?? "?")")

        print("\n== Canon metinleri: \(CanonMetinleri.shared.yuklendi ? "yüklendi" : "YOK")")
        if let m = CanonMetinleri.shared.kisaBaslik(kod: "1000") { print("  1000 → \(m)") }

        if arg.contains("--gunluk") {
            print("\n== Günlük")
            Gunluk.sonSatirlar(40).forEach { print($0) }
        }

        if arg.contains("--cihaz") {
            print("\n== Yazıcı (Canon CHMP, salt okunur)")
            cihaziYaz(kuyruk)
        }
    }

    /// Yazıcının ağ adresini kuyruğun aygıt adresinden bulur; durum ve cihaz ayarlarını yazar. Hiçbir şey göndermez.
    private static func cihaziYaz(_ kuyruk: String) {
        guard let aygit = try? KuyrukDurumu(CUPSIstemci.kuyrukOznitelikleri(kuyruk)).aygitAdresi, !aygit.isEmpty else {
            print("kuyruğun aygıt adresi okunamadı")
            return
        }
        var adres = CihazBulucu.onbellek(aygit)
        var kaynak = "önbellek"
        if adres == nil, let d = CihazBulucu.dogrudan(aygit) { adres = d; kaynak = "aygıt adresi" }
        if adres == nil { adres = bonjourIleCoz(aygit); kaynak = "Bonjour" }
        guard let host = adres?.host else {
            print("yazıcının ağ adresi bulunamadı (aygıt: \(aygit))")
            return
        }
        print("adres: \(host) (\(kaynak))")

        do {
            let d = try CanonCihaz.durum(host: host)
            print("durum: \(d.durum) (\(d.durumAdi))" + (d.ayrinti.isEmpty ? "" : " · ayrıntı: \(d.ayrinti)"))
            if let islem = d.bakimIslemi { print("bakım işlemi: \(islem)" + (d.bakimTuru.map { " / \($0)" } ?? "")) }
            if let kod = d.destekKodu {
                print("destek kodu: \(kod) → \(CanonMetinleri.shared.kisaBaslik(kod: kod) ?? "?")")
            }
        } catch {
            print("durum okunamadı: \(error.localizedDescription)")
        }

        do {
            let a = try CanonCihaz.ayarlar(host: host)
            func acik(_ b: Bool?) -> String { b.map { $0 ? "açık" : "kapalı" } ?? "?" }
            print("otomatik açılma: \(acik(a.otomatikAcilma))")
            print("otomatik kapanma: \(acik(a.otomatikKapanma))" + (a.kapanmaDakika.map { " · \($0) dk" } ?? ""))
            print("sessiz mod: \(a.sessizMod ?? "?") · \(a.sessizBaslangic ?? "?")–\(a.sessizBitis ?? "?")")
            print("kalan mürekkep bildirimi: \(acik(a.murekkepBildirimi))")
        } catch {
            print("ayarlar okunamadı: \(error.localizedDescription)")
        }
    }

    /// Önbellekte adres yoksa Bonjour ile çözer (terminalde: ana döngüyü kısa süre döndürerek).
    private static func bonjourIleCoz(_ aygit: String) -> CihazAdresi? {
        final class Kutu: @unchecked Sendable {
            var adres: CihazAdresi?
            var bitti = false
        }
        let kutu = Kutu()
        Task { @MainActor in
            kutu.adres = await CihazBulucu().coz(aygit)
            kutu.bitti = true
        }
        let son = Date().addingTimeInterval(15)
        while !kutu.bitti && Date() < son {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        return kutu.adres
    }
}
