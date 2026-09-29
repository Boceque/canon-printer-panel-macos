import Foundation

/// Uygulama ile arka plan görevlisinin paylaştığı dosyalar:
/// ~/Library/Application Support/Yazıcı Paneli/
enum Depo {
    static let klasor: URL = {
        let temel = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let k = temel.appendingPathComponent("Yazıcı Paneli", isDirectory: true)
        try? FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        return k
    }()

    static func dosya(_ ad: String) -> URL { klasor.appendingPathComponent(ad) }

    static let kodlayici: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let cozucu: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func oku<T: Decodable>(_ tur: T.Type, _ ad: String) -> T? {
        guard let veri = try? Data(contentsOf: dosya(ad)) else { return nil }
        return try? cozucu.decode(tur, from: veri)
    }

    /// Atomik yazım: yarım dosya kalmaz (görevli aynı anda okuyabilir).
    static func yaz<T: Encodable>(_ deger: T, _ ad: String) throws {
        let veri = try kodlayici.encode(deger)
        try veri.write(to: dosya(ad), options: .atomic)
    }

    static func degisimZamani(_ ad: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: dosya(ad).path))?[.modificationDate] as? Date
    }
}

/// Basit metin günlüğü (görevlinin yaptıkları ve uygulanan ayarlar).
enum Gunluk {
    static let dosyaAdi = "gunluk.log"
    private static let kilit = NSLock()
    private static let bicim: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Süreç rolüne göre (Chrome köprüsü "chrome" kurar); açık `kaynak` verilmezse bu yazılır.
    nonisolated(unsafe) static var varsayilanKaynak = "uygulama"

    static func yaz(_ mesaj: String, kaynak: String? = nil) {
        kilit.lock(); defer { kilit.unlock() }
        let satir = "\(bicim.string(from: Date())) [\(kaynak ?? varsayilanKaynak)] \(mesaj)\n"
        let url = Depo.dosya(dosyaAdi)
        if let tutamac = try? FileHandle(forWritingTo: url) {
            defer { try? tutamac.close() }
            _ = try? tutamac.seekToEnd()
            try? tutamac.write(contentsOf: Data(satir.utf8))
        } else {
            try? Data(satir.utf8).write(to: url, options: .atomic)
        }
        kirp(url)
    }

    /// 256 KB'ı geçerse son 1500 satırı tutar.
    private static func kirp(_ url: URL) {
        guard let boyut = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              boyut > 256_000, let metin = try? String(contentsOf: url, encoding: .utf8) else { return }
        let son = metin.split(separator: "\n", omittingEmptySubsequences: false).suffix(1500).joined(separator: "\n")
        try? son.write(to: url, atomically: true, encoding: .utf8)
    }

    static func sonSatirlar(_ adet: Int = 200) -> [String] {
        guard let metin = try? String(contentsOf: Depo.dosya(dosyaAdi), encoding: .utf8) else { return [] }
        return metin.split(separator: "\n").suffix(adet).map(String.init)
    }
}
