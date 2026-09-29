import Foundation

/// Canon sürücüsünün kendi Türkçe durum/hata metinleri (makinede kurulu sürücüden okunur).
/// `com.canon-1000` → `Error1000` → "Kağıt yok. Kağıdı düzgün şekilde yükleyin…"
final class CanonMetinleri: @unchecked Sendable {
    static let shared = CanonMetinleri()

    static let durumTablosu = "/Library/Printers/Canon/BJPrinter/Frameworks/BJStatus2.framework/Versions/A/Resources/tr.lproj/Localizable.strings"

    private let kilit = NSLock()
    private var tablo: [String: String]?
    /// Canon'un neden adındaki kod → mesaj anahtarı ("10000D" → "Error1000_0D").
    private var dizin: [String: String] = [:]

    private func yukle() -> [String: String] {
        kilit.lock(); defer { kilit.unlock() }
        if let tablo { return tablo }
        let t = (NSDictionary(contentsOfFile: CanonMetinleri.durumTablosu) as? [String: String]) ?? [:]
        for anahtar in t.keys {
            for onek in ["Error", "Confirm"] where anahtar.hasPrefix(onek) {
                let kod = anahtar.dropFirst(onek.count).filter { $0 != "_" && $0 != " " }
                if !kod.isEmpty, dizin[String(kod)] == nil { dizin[String(kod)] = anahtar }
            }
        }
        tablo = t
        return t
    }

    var yuklendi: Bool { !yukle().isEmpty }

    /// Ham Canon metni: "Destek Kodu: …" satırı ve yer tutucular atılır, satır sonları düzeltilir.
    func hata(kod: String) -> String? {
        let t = yukle()
        // Önce modele özgü tam anahtar (G3010: Error1000_0D "Başlat düğmesi"), yoksa genel 4 haneli.
        let anahtar: String? = {
            kilit.lock(); defer { kilit.unlock() }
            return dizin[kod]
        }()
        if let anahtar, let ham = t[anahtar] { return CanonMetinleri.temizle(ham) }
        guard let ham = t["Error\(kod.prefix(4))"] else { return nil }
        return CanonMetinleri.temizle(ham)
    }

    /// İlk cümle (ör. "Kağıt yok").
    func kisaBaslik(kod: String) -> String? {
        guard let metin = hata(kod: kod) else { return nil }
        let ilkSatir = metin.split(separator: "\n").first.map(String.init) ?? metin
        if let nokta = ilkSatir.firstIndex(of: "."), ilkSatir.distance(from: ilkSatir.startIndex, to: nokta) < 90 {
            return String(ilkSatir[..<nokta])
        }
        return ilkSatir.count > 90 ? String(ilkSatir.prefix(87)) + "…" : ilkSatir
    }

    /// Canon'un "meşgul" durum metni (ör. BusyCL → "Yazıcı kafası temizleniyor.").
    func mesgul(_ anahtar: String) -> String? { yukle()[anahtar].map(CanonMetinleri.temizle) }

    static func temizle(_ ham: String) -> String {
        var satirlar = ham.replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        if let ilk = satirlar.first, ilk.hasPrefix("Destek Kodu") { satirlar.removeFirst() }
        let birlesik = satirlar
            .map { $0.replacingOccurrences(of: #"__[A-Z0-9_]+__"#, with: "", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        return birlesik
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
