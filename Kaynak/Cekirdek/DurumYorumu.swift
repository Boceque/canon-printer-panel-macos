import Foundation

// Durum yorumu: Mac kuyruğu + yazıcının kendisi + sabitleme → tek cümlelik özet ve önerilen eylemler.
// Uygulama modeli ve Chrome köprüsü aynı mantığı kullanır.

enum DurumSeviyesi: Int, Comparable {
    case hazir = 0, calisiyor, bilinmiyor, uyari, hata
    static func < (a: DurumSeviyesi, b: DurumSeviyesi) -> Bool { a.rawValue < b.rawValue }
}

enum HizliEylem: Hashable, Identifiable {
    case surdur, uyarilariTemizle, bekleyenleriSerbestBirak, gorevliyiBaslat, bekletmeyiKaldir, yenile
    var id: Self { self }

    var ad: String {
        switch self {
        case .surdur: return "Kuyruğu sürdür"
        case .uyarilariTemizle: return "Eski uyarıları temizle"
        case .bekleyenleriSerbestBirak: return "Bekleyen işleri gönder"
        case .gorevliyiBaslat: return "Görevliyi yeniden başlat"
        case .bekletmeyiKaldir: return "İş bekletmeyi kapat"
        case .yenile: return "Yeniden dene"
        }
    }

    var simge: String {
        switch self {
        case .surdur: return "play.fill"
        case .uyarilariTemizle: return "eraser"
        case .bekleyenleriSerbestBirak: return "paperplane"
        case .gorevliyiBaslat: return "arrow.clockwise.circle"
        case .bekletmeyiKaldir: return "hand.raised.slash"
        case .yenile: return "arrow.clockwise"
        }
    }
}

struct DurumOzeti: Equatable {
    var seviye: DurumSeviyesi
    var baslik: String
    var ayrinti: String?
    var eylemler: [HizliEylem]
}

/// Yorum için gereken anlık görüntü. Saf veri: MainActor'a bağlı değil.
struct DurumYorumu {
    let kuyruk: KuyrukDurumu?
    let kuyrukHatasi: String?
    let cihaz: CihazDurumu?
    let cihazHatasi: String?
    let isler: [YaziciIsi]
    let sabitleme: SabitlemeYapilandirmasi
    let gorevliCanli: Bool

    var etkinIs: YaziciIsi? { isler.first { $0.durum == .yazdiriliyor } ?? isler.first { $0.durum == .durdu } }
    var bekleyenIsSayisi: Int { isler.filter { $0.durum.etkin }.count }

    /// Kesin mod açık ama görevli işlemediği için bekleyen işler.
    var takiliIsSayisi: Int {
        sabitleme.aktifKesinMod && !gorevliCanli ? IsDenetleyici.bekleyenSayisi(isler, baslangic: sabitleme.kesinModBaslangic) : 0
    }

    /// Kuyrukta, yazıcının artık bildirmediği hata nedenleri (eski uyarılar).
    var eskiUyarilar: [DurumNedeni] {
        guard let kuyruk, let cihaz, !cihaz.sorunVar else { return [] }
        return kuyruk.nedenler.gercekler.filter { $0.onem == .hata && $0.kok != "paused" }
    }

    var durumOzeti: DurumOzeti {
        guard let kuyruk else {
            return DurumOzeti(seviye: .bilinmiyor, baslik: "Yazıcı bilgisi alınamadı",
                              ayrinti: kuyrukHatasi, eylemler: [.yenile])
        }
        if sabitleme.aktifKesinMod, !gorevliCanli {
            var e: [HizliEylem] = [.gorevliyiBaslat]
            if takiliIsSayisi > 0 { e.append(.bekleyenleriSerbestBirak) }
            let ayrinti = takiliIsSayisi > 0 ? "\(takiliIsSayisi) iş gönderilmeyi bekliyor."
                : (kuyruk.isBeklemeVarsayilani == "indefinite" ? "Yeni işler bekletilecek."
                                                                : "Bekletme kurulu değil; işler denetlenmeden basılıyor.")
            return DurumOzeti(seviye: .hata, baslik: "Kesin mod açık ama arka plan görevlisi çalışmıyor",
                              ayrinti: ayrinti, eylemler: e)
        }
        if !sabitleme.aktifKesinMod, kuyruk.isBeklemeVarsayilani == "indefinite" {
            return DurumOzeti(seviye: .hata, baslik: "Kuyruk tüm yeni işleri bekletiyor",
                              ayrinti: "Kesin mod kapalı ama kuyruğun iş bekletme ayarı açık kalmış; işler basılmıyor. Bekleyen işleri Yazdırma Kuyruğu'ndan sürdürebilirsiniz.",
                              eylemler: [.bekletmeyiKaldir])
        }
        let cihazSorunu = cihaz?.nedenler.gercekler.sorted { $0.onem > $1.onem }.first
        if kuyruk.durdurulmus {
            if let cihaz, !cihaz.sorunVar {
                return DurumOzeti(seviye: .uyari, baslik: "Mac'teki kuyruk durdurulmuş, yazıcı hazır",
                                  ayrinti: "Yazıcı sorun bildirmiyor. Kuyruğu sürdürünce bekleyen işler basılır.",
                                  eylemler: eskiUyarilar.isEmpty ? [.surdur] : [.surdur, .uyarilariTemizle])
            }
            if let cihazSorunu {
                return DurumOzeti(seviye: .hata, baslik: cihazSorunu.baslik,
                                  ayrinti: (cihazSorunu.ayrinti ?? "") + "\nSorunu giderince kuyruğu sürdürün.",
                                  eylemler: [.surdur])
            }
            let neden = kuyruk.nedenler.gercekler.first { $0.kok != "paused" }
            return DurumOzeti(seviye: .hata, baslik: "Kuyruk durduruldu",
                              ayrinti: neden.map { "Son bildirilen: \($0.baslik). " } .map { $0 + "Yazıcıyı kontrol edip sürdürün." }
                                  ?? "Yazıcıyı kontrol edip sürdürün.",
                              eylemler: [.surdur])
        }
        if !kuyruk.isKabulEdiyor {
            return DurumOzeti(seviye: .uyari, baslik: "Kuyruk yeni işleri kabul etmiyor",
                              ayrinti: "Uygulamalardan gönderilen işler reddediliyor. Sürdür, iş kabulünü de açar.",
                              eylemler: [.surdur])
        }
        if let cihaz, cihaz.sorunVar {
            let baslik = cihazSorunu?.baslik ?? cihaz.uyariMetni ?? "Yazıcı bir sorun bildiriyor"
            return DurumOzeti(seviye: (cihazSorunu?.onem ?? .uyari) == .hata ? .hata : .uyari,
                              baslik: baslik, ayrinti: cihazSorunu?.ayrinti ?? cihaz.uyariMetni, eylemler: [])
        }
        if !eskiUyarilar.isEmpty {
            return DurumOzeti(seviye: .uyari, baslik: "Mac'te eski bir uyarı kalmış",
                              ayrinti: "Kuyruk \"\(eskiUyarilar.map(\.baslik).joined(separator: ", "))\" diyor ama yazıcı sorun bildirmiyor.",
                              eylemler: [.uyarilariTemizle])
        }
        let yazdiriyor = kuyruk.durum == .yazdiriyor || etkinIs?.durum == .yazdiriliyor
        let baglantiSorunu = kuyruk.nedenler.gercekler.first {
            ["connecting-to-device", "offline", "timed-out", "com.apple.print.recoverable"].contains($0.kok)
        }
        if yazdiriyor, let n = baglantiSorunu {
            return DurumOzeti(seviye: .uyari, baslik: "Yazıcıya ulaşılamıyor, iş bekliyor",
                              ayrinti: kuyruk.mesaj.isEmpty ? (cihazHatasi ?? n.ayrinti ?? n.baslik) : kuyruk.mesaj,
                              eylemler: [.yenile])
        }
        if yazdiriyor {
            return DurumOzeti(seviye: .calisiyor, baslik: "Yazdırıyor",
                              ayrinti: etkinIs.map { "\($0.ad)" }, eylemler: [])
        }
        if cihaz == nil, cihazHatasi != nil {
            // Yazıcının kapalı olması olağan: bekleyen iş yoksa uyarı sayılmaz (bildirim gitmez).
            let n = bekleyenIsSayisi
            return n > 0
                ? DurumOzeti(seviye: .uyari, baslik: "Yazıcıya ulaşılamıyor, \(n) iş bekliyor", ayrinti: cihazHatasi, eylemler: [.yenile])
                : DurumOzeti(seviye: .bilinmiyor, baslik: "Yazıcı kapalı ya da ağda değil", ayrinti: cihazHatasi, eylemler: [.yenile])
        }
        return DurumOzeti(seviye: .hazir, baslik: "Hazır",
                          ayrinti: bekleyenIsSayisi > 0 ? "\(bekleyenIsSayisi) iş kuyrukta" : nil, eylemler: [])
    }
}
