import Foundation

// Bakım işlemleri Canon'un IVEC komut biçimiyle, doğrudan yazıcıya (ham 9100) gider; bkz. CanonAg.swift.
// Eski yol (CUPS komut işi → Command2CanonIJ → BJL "@CLEANING=…") yazıcıya ulaşıyor ama G3010 onu yok sayıyordu.
//
// İşlem adları, türler ve gruplar yazıcının kendi GetCapability(maintenance) yanıtından (2026-09-29):
//   Cleaning        regular (all, group1, group2) · deep (all, group1) · choke (all, group1, group2)
//   RollerCleaning  roller · platen
//   TestPrint       nozzle_check · half_auto_registration · regi_check
// group1 = siyah (BK), group2 = renkli (C, M, Y).

enum TemizlikGrubu: String, CaseIterable, Identifiable, Sendable {
    case tum, siyah, renkli
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .tum: return "Tüm renkler (BK, C, M, Y)"
        case .siyah: return "Yalnız siyah (BK)"
        case .renkli: return "Yalnız renkli (C, M, Y)"
        }
    }

    var kisaAd: String {
        switch self {
        case .tum: return "Tümü"
        case .siyah: return "Siyah"
        case .renkli: return "Renkli"
        }
    }

    /// IVEC `inkgroup` değeri.
    var ivec: String {
        switch self {
        case .tum: return "all"
        case .siyah: return "group1"
        case .renkli: return "group2"
        }
    }
}

enum MurekkepKullanimi: Int, Comparable, Sendable {
    case yok = 0, az, orta, cok, cokFazla
    static func < (a: MurekkepKullanimi, b: MurekkepKullanimi) -> Bool { a.rawValue < b.rawValue }

    var ad: String {
        switch self {
        case .yok: return "Mürekkep harcamaz"
        case .az: return "Az mürekkep"
        case .orta: return "Mürekkep harcar"
        case .cok: return "Çok mürekkep harcar"
        case .cokFazla: return "Çok fazla mürekkep harcar"
        }
    }
}

struct BakimIslemi: Identifiable, Sendable {
    enum Tur: String, Sendable {
        case puskurtmeDenetimi, temizleme, yogunTemizleme, sistemTemizleme
        case altPlaka, silindir, silindirKagitli
        case kafaHizalama, hizalamaDegerleri, murekkepSayaci
    }

    /// Yazıcıya giden iş.
    enum Gonderim: Sendable, Equatable {
        /// Bakım işi (StartJob servicetype="maintenance"): IVEC işlem adı ve içeriği.
        case bakim(islem: String, icerik: String)
        /// Mürekkep sayacı sıfırlama: CHMP'den üretici komutu (VendorCmd ResetCounter); yazıcı hemen OK/NG yanıtlar.
        case sayacSifirla
    }

    let tur: Tur
    let ad: String
    let simge: String
    let ozet: String
    let adimlar: [String]
    let murekkep: MurekkepKullanimi
    let kagit: String?
    /// Yalnız yazıcının bu işlem için desteklediği gruplar (boşsa grup seçilmez).
    let gruplar: [TemizlikGrubu]
    let onay: String
    let sure: String?
    /// Yazıcı çalışırken canlı durumda görünen kısa metin.
    let calisiyorMetni: String
    /// Yazıcı boşa dönünce görünen sonuç.
    let bittiMetni: String
    /// Çalışırken kullanıcının yapması gereken (ör. hizalama desenini taratmak).
    var canliIpucu: String? = nil

    var id: String { tur.rawValue }

    func gonderim(grup: TemizlikGrubu = .tum) -> Gonderim {
        let g = gruplar.contains(grup) ? grup : (gruplar.first ?? .tum)
        switch tur {
        case .puskurtmeDenetimi: return Self.testBaskisi("nozzle_check")
        case .temizleme: return Self.temizlik("regular", g)
        case .yogunTemizleme: return Self.temizlik("deep", g)
        case .sistemTemizleme: return Self.temizlik("choke", g)
        case .altPlaka: return .bakim(islem: "RollerCleaning", icerik: "<ivec:type>platen</ivec:type>")
        case .silindir, .silindirKagitli: return .bakim(islem: "RollerCleaning", icerik: "<ivec:type>roller</ivec:type>")
        case .kafaHizalama: return Self.testBaskisi("half_auto_registration")
        case .hizalamaDegerleri: return Self.testBaskisi("regi_check")
        case .murekkepSayaci: return .sayacSifirla
        }
    }

    private static func temizlik(_ tip: String, _ g: TemizlikGrubu) -> Gonderim {
        .bakim(islem: "Cleaning", icerik: "<ivec:inkgroup>\(g.ivec)</ivec:inkgroup><ivec:type>\(tip)</ivec:type>")
    }

    private static func testBaskisi(_ tip: String) -> Gonderim {
        .bakim(islem: "TestPrint", icerik: "<ivec:type>\(tip)</ivec:type>")
    }

    /// Günlükte ve canlı durumda görünen ad.
    func baslik(grup: TemizlikGrubu = .tum) -> String {
        gruplar.count > 1 ? "\(ad) (\(grup.kisaAd))" : ad
    }

    static let hepsi: [BakimIslemi] = [
        BakimIslemi(
            tur: .puskurtmeDenetimi, ad: "Püskürtme Ucu Denetimi", simge: "square.grid.3x3.topleft.filled",
            ozet: "Test deseni basar. Çizgiler kesikliyse ya da bir renk eksikse uçlar tıkalıdır.",
            adimlar: [
                "Arka tepsiye bir sayfa A4 düz kağıt koyun.",
                "Deseni basın ve inceleyin: tüm çizgiler tam ve her renk görünüyorsa temizlik gerekmez.",
                "Eksik çizgi varsa önce Temizleme yapın, sonra denetimi tekrarlayın.",
            ],
            murekkep: .az, kagit: "1 sayfa A4 düz kağıt", gruplar: [],
            onay: "Püskürtme ucu denetim deseni yazdırılsın mı?", sure: "yaklaşık 1 dakika",
            calisiyorMetni: "Test sayfası basılıyor…",
            bittiMetni: "Deseni inceleyin: çizgiler tam ve her renk görünüyorsa temizlik gerekmez. Eksik çizgi varsa Temizleme yapın."),
        BakimIslemi(
            tur: .temizleme, ad: "Temizleme", simge: "drop.degreesign",
            ozet: "Yazıcı kafasındaki tıkanmayı giderir. Denetim deseninde eksik çizgi görünce kullanın.",
            adimlar: [
                "Denetim desenine göre hangi grubun tıkalı olduğunu seçin; emin değilseniz Tümü.",
                "Temizlik bitince Püskürtme Ucu Denetimi ile sonucu kontrol edin.",
                "İki temizlikten sonra düzelmezse Yoğun Temizleme deneyin.",
            ],
            murekkep: .orta, kagit: nil, gruplar: [.tum, .siyah, .renkli],
            onay: "Yazıcı kafası temizlensin mi? Bu işlem mürekkep harcar.", sure: "yaklaşık 1–2 dakika",
            calisiyorMetni: "Temizleniyor…",
            bittiMetni: "Temizlik bitti. Sonucu Püskürtme Ucu Denetimi ile kontrol edin."),
        BakimIslemi(
            tur: .yogunTemizleme, ad: "Yoğun Temizleme", simge: "drop.triangle",
            ozet: "Normal temizlemeden çok daha güçlü. Yalnız normal temizlik işe yaramadıysa kullanın.",
            adimlar: [
                "Önce en az bir kez normal Temizleme yapmış olun.",
                "G3010'da yoğun temizlik iki seçenekle yapılır: tüm renkler ya da yalnız siyah (BK).",
                "Bitince Püskürtme Ucu Denetimi yapın. Düzelmediyse yazıcıyı 24 saat kapalı bırakıp tekrar deneyin.",
            ],
            murekkep: .cok, kagit: nil, gruplar: [.tum, .siyah],
            onay: "Yoğun temizleme başlatılsın mı? Normal temizlemeden çok daha fazla mürekkep harcar.",
            sure: "yaklaşık 2–3 dakika",
            calisiyorMetni: "Yoğun temizlik yapılıyor…",
            bittiMetni: "Yoğun temizlik bitti. Püskürtme Ucu Denetimi ile kontrol edin; düzelmediyse yazıcıyı 24 saat kapalı bırakıp tekrar deneyin."),
        BakimIslemi(
            tur: .sistemTemizleme, ad: "Sistem Temizleme", simge: "exclamationmark.octagon",
            ozet: "Mürekkep yolunu yeniden dolduran en güçlü temizlik. Son çare; tankları gözle kontrol edin.",
            adimlar: [
                "Yoğun temizlik de işe yaramadıysa kullanın.",
                "Başlamadan önce tankları kontrol edin: Tümü ya da Siyah seçerseniz tüm tanklarda, Renkli seçerseniz renkli tanklarda mürekkep, tank üzerindeki tek nokta işaretinin altında olmamalı. Altındaysa önce doldurun; yoksa yazıcı hasar görebilir.",
                "Siyah seçseniz de renkli mürekkep harcanır.",
                "Kalan mürekkep bildirimi açıksa önce tüm tankları üst sınır çizgisine kadar doldurun.",
                "İşlem uzun sürer ve atık mürekkep emicisini doldurur; sık yapmayın.",
            ],
            murekkep: .cokFazla, kagit: nil, gruplar: [.tum, .siyah, .renkli],
            onay: "Sistem temizleme başlatılsın mı? Çok fazla mürekkep harcar (Siyah seçilse de renkli mürekkep harcanır) ve uzun sürer.",
            sure: "birkaç dakika",
            calisiyorMetni: "Sistem temizliği yapılıyor… Birkaç dakika sürer.",
            bittiMetni: "Sistem temizliği bitti. Püskürtme Ucu Denetimi ile kontrol edin."),
        BakimIslemi(
            tur: .altPlaka, ad: "Alt Plaka Temizleme", simge: "rectangle.bottomhalf.inset.filled",
            ozet: "Kağıdın arkasında mürekkep lekesi çıkıyorsa yazıcının içindeki alt plakayı temizler.",
            adimlar: [
                "A4 düz kağıdı ikiye katlayın, ardından açın.",
                "Katlama çizgisi aşağı bakacak şekilde (açık tarafı size dönük) arka tepsiye yalnız bu kağıdı koyun.",
                "İşlem bitince kağıttaki lekelere bakın; çok kirliyse bir kez daha yapın.",
            ],
            murekkep: .yok, kagit: "1 sayfa A4 düz kağıt (ortadan katlanmış)", gruplar: [],
            onay: "Alt plaka temizliği başlatılsın mı?", sure: "yaklaşık 1 dakika",
            calisiyorMetni: "Alt plaka temizleniyor…",
            bittiMetni: "Bitti. Çıkan kağıttaki lekelere bakın; çok kirliyse bir kez daha yapın."),
        BakimIslemi(
            tur: .silindir, ad: "Silindir Temizleme", simge: "arrow.triangle.2.circlepath",
            ozet: "Kağıt kayıyor, eğri çekiliyor ya da hiç alınmıyorsa kağıt besleme silindirlerini temizler. İki adımda yapılır.",
            adimlar: [
                "Önce arka tepsiden kağıdı çıkarın. 1. adımda silindirler kağıtsız, yaklaşık 1,5 dakika döner.",
                "Yazıcının çalışma gürültüsünün durduğundan emin olun ve arka tepsiye üç sayfa düz kağıt yükleyin. 2. adımda kağıtlar silindirleri silerek çıkar.",
            ],
            murekkep: .yok, kagit: "2. adımda 3 sayfa A4 düz kağıt", gruplar: [],
            onay: "Silindir temizliğinin 1. adımı başlatılsın mı?", sure: "1. adım yaklaşık 1,5 dakika",
            calisiyorMetni: "Silindirler kağıtsız temizleniyor…",
            bittiMetni: "1. adım bitti. Arka tepsiye üç sayfa düz kağıt yükleyip 2. adımı başlatın.",
            canliIpucu: "Silindirler dönüyor. Gürültü durunca 2. adıma geçebilirsiniz."),
        BakimIslemi(
            tur: .silindirKagitli, ad: "Silindir Temizleme (2. adım)", simge: "arrow.triangle.2.circlepath",
            ozet: "Arka tepsideki üç sayfa düz kağıtla silindirleri siler.",
            adimlar: [],
            murekkep: .yok, kagit: "3 sayfa A4 düz kağıt", gruplar: [],
            onay: "Arka tepsiye üç sayfa düz kağıt yüklediniz mi? 2. adım başlatılsın mı?", sure: nil,
            calisiyorMetni: "Silindirler kağıtla temizleniyor…",
            bittiMetni: "Silindir temizliği bitti."),
        BakimIslemi(
            tur: .kafaHizalama, ad: "Yazıcı Kafası Hizalama", simge: "ruler",
            ozet: "Düz çizgiler kayık ya da yazılar bulanıksa kafayı hizalar. Desen basılır, sonra yazıcının tarayıcısıyla okunur.",
            adimlar: [
                "Arka tepsiye bir sayfa A4 düz kağıt koyun ve hizalama desenini basın.",
                "Deseni, basılı yüzü alta gelecek şekilde tarayıcı camına koyun ve belge kapağını kapatın.",
                "Yazıcıdaki Siyah (başlat) düğmesine basın; desen taranınca hizalama biter.",
                "Mevcut değerleri görmek isterseniz \"Hizalama değerlerini yazdır\"ı kullanın.",
            ],
            murekkep: .az, kagit: "1 sayfa A4 düz kağıt", gruplar: [],
            onay: "Kafa hizalama deseni yazdırılsın mı?", sure: "yaklaşık 3 dakika",
            calisiyorMetni: "Hizalama deseni basılıyor…",
            bittiMetni: "Desen basıldıysa basılı yüzü alta gelecek şekilde tarayıcı camına koyun, kapağı kapatın ve yazıcıdaki Siyah düğmesine basın. Tarama bitince hizalama tamamlanır.",
            canliIpucu: "Desen basılınca basılı yüzü alta gelecek şekilde tarayıcı camına koyun ve yazıcıdaki Siyah düğmesine basın."),
        BakimIslemi(
            tur: .hizalamaDegerleri, ad: "Hizalama Değerleri", simge: "list.number",
            ozet: "Yazıcıdaki mevcut kafa hizalama değerlerini bir sayfaya basar.",
            adimlar: [],
            murekkep: .az, kagit: "1 sayfa A4 düz kağıt", gruplar: [],
            onay: "Hizalama değerleri yazdırılsın mı?", sure: "yaklaşık 1 dakika",
            calisiyorMetni: "Hizalama değerleri basılıyor…",
            bittiMetni: "Hizalama değerleri basıldı."),
        BakimIslemi(
            tur: .murekkepSayaci, ad: "Mürekkep Sayacını Sıfırla", simge: "arrow.counterclockwise.circle",
            ozet: "Tankları doldurduktan sonra yazıcının tahmini mürekkep sayacını sıfırlar.",
            adimlar: [
                "Yalnızca TÜM tankları üst çizgiye kadar doldurduysanız sıfırlayın.",
                "G3010 mürekkebi ölçmez, harcamayı sayar; yanlış sıfırlama uyarıların geç gelmesine yol açar.",
                "Yazıcı sıfırlamayı onaylar; onay gelmezse hata gösterilir.",
            ],
            murekkep: .yok, kagit: nil, gruplar: [],
            onay: "Tüm tankları üst çizgiye kadar doldurdunuz mu? Mürekkep sayacı sıfırlansın mı?", sure: nil,
            calisiyorMetni: "Gönderiliyor…",
            bittiMetni: "Yazıcı mürekkep sayacını sıfırladığını onayladı."),
    ]

    static func tur(_ t: Tur) -> BakimIslemi { hepsi.first { $0.tur == t }! }
}

/// Son bakım işleminin canlı durumu (yazıcının CHMP durumu yoklanarak güncellenir).
struct BakimCanliDurum: Identifiable, Equatable, Sendable {
    enum Asama: Sendable, Equatable {
        /// Yazıcıya gönderiliyor ya da gönderildi, yazıcının başlaması bekleniyor.
        case gonderiliyor
        case calisiyor
        /// Yazıcı çalıştı ve boşa döndü.
        case bitti
        /// Gönderildi; yazıcı sonucu bildirmiyor (cihaz işleri).
        case gonderildi
        case uyari
        case hata
    }

    let id = UUID()
    let tur: BakimIslemi.Tur
    let ad: String
    var asama: Asama
    var mesaj: String
    let baslangic: Date
    var bitis: Date?
    /// Yazıcının durumu hâlâ yoklanıyor mu? (Yazıcı bir uyarıyla durduğunda da izleme sürer.)
    var izleniyor = false
    /// Kullanıcı "Durdur"a bastı; yazıcı boşa dönünce sonuç "durduruldu" olur.
    var durdurmaIstendi = false
    /// Yazıcı işe başladı; artık durdurulabilir.
    var durdurulabilir: Bool { izleniyor && asama != .gonderiliyor }

    /// Yeni bir bakım ya da ayar gönderilmemeli.
    var suruyor: Bool { izleniyor || asama == .gonderiliyor }
    var islem: BakimIslemi { BakimIslemi.tur(tur) }
}
