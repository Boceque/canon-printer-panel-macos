import Foundation

struct PPDSecimi: Hashable, Sendable, Identifiable {
    let kod: String
    let ad: String          // Türkçe varsa Türkçe, yoksa İngilizce
    let ingilizceAd: String
    var id: String { kod }
}

struct PPDSecenegi: Hashable, Sendable, Identifiable {
    let anahtar: String
    let ad: String
    let secimler: [PPDSecimi]
    let varsayilan: String?
    var id: String { anahtar }

    func secim(_ kod: String?) -> PPDSecimi? {
        guard let kod else { return nil }
        return secimler.first { $0.kod == kod }
    }
}

/// Yazıcının PPD dosyasındaki seçenekler, varsayılanlar, Türkçe çeviriler ve üst bilgiler.
struct PPDKatalogu: Sendable {
    let yol: String
    let secenekler: [String: PPDSecenegi]
    let sira: [String]
    let nitelikler: [String: String]

    subscript(_ anahtar: String) -> PPDSecenegi? { secenekler[anahtar] }

    func varsayilan(_ anahtar: String) -> String? { secenekler[anahtar]?.varsayilan }
    func var_(_ anahtar: String) -> Bool { secenekler[anahtar] != nil }

    var model: String { nitelikler["NickName"] ?? nitelikler["ModelName"] ?? "" }
    var surum: String { nitelikler["FileVersion"] ?? "" }
    var simgeYolu: String? { nitelikler["APPrinterIconPath"] }
    var yardimciProgramYolu: String? { nitelikler["APPrinterUtilityPath"] }

    /// PPD metnini okur. Dosya ISOLatin1 bildirse de Canon'un çeviri satırları UTF-8'dir.
    static func oku(_ yol: String) -> PPDKatalogu? {
        guard let veri = FileManager.default.contents(atPath: yol) else { return nil }
        let metin = String(decoding: veri, as: UTF8.self)
        return coz(metin, yol: yol)
    }

    static func coz(_ metin: String, yol: String = "") -> PPDKatalogu {
        struct Taslak {
            var ad: String
            var secimler: [(kod: String, ad: String)] = []
        }
        var taslaklar: [String: Taslak] = [:]
        var sira: [String] = []
        var varsayilanlar: [String: String] = [:]
        var trSecenekAdi: [String: String] = [:]
        var trSecimAdi: [String: String] = [:]   // "anahtar kod" → ad
        var nitelikler: [String: String] = [:]
        var acik: String? = nil
        var cokSatirliDeger = false

        for hamSatir in metin.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let satir = String(hamSatir)
            if cokSatirliDeger {
                if satir.hasSuffix("\"") || satir.hasPrefix("*End") { cokSatirliDeger = false }
                continue
            }
            guard satir.hasPrefix("*"), !satir.hasPrefix("*%") else { continue }

            // Değer kısmı çok satıra yayılıyorsa sonraki satırları atla.
            if let ikiNokta = satir.range(of: ": \"") {
                let deger = satir[ikiNokta.upperBound...]
                if !deger.contains("\"") { cokSatirliDeger = true }
            }

            if satir.hasPrefix("*OpenUI ") {
                // *OpenUI *Anahtar/Metin: PickOne
                let govde = satir.dropFirst("*OpenUI *".count)
                let bas = govde.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
                let parca = bas.split(separator: "/", maxSplits: 1)
                let anahtar = String(parca.first ?? "")
                let ad = parca.count > 1 ? String(parca[1]) : anahtar
                taslaklar[anahtar] = Taslak(ad: ad)
                sira.append(anahtar)
                acik = anahtar
                continue
            }
            if satir.hasPrefix("*CloseUI") { acik = nil; continue }

            if satir.hasPrefix("*Default") {
                let govde = satir.dropFirst("*Default".count)
                let p = govde.split(separator: ":", maxSplits: 1)
                if p.count == 2 {
                    varsayilanlar[String(p[0])] = p[1].trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if satir.hasPrefix("*tr.") {
                let govde = String(satir.dropFirst("*tr.".count))
                guard let bolucu = govde.range(of: ": ", options: .backwards) else { continue }
                let sol = govde[..<bolucu.lowerBound]
                guard let egik = sol.firstIndex(of: "/") else { continue }
                let anahtarKisim = sol[..<egik]
                let ad = String(sol[sol.index(after: egik)...])
                let kelimeler = anahtarKisim.split(separator: " ", maxSplits: 1)
                if kelimeler.first == "Translation", kelimeler.count == 2 {
                    trSecenekAdi[String(kelimeler[1])] = ad
                } else if kelimeler.count == 2 {
                    trSecimAdi["\(kelimeler[0]) \(kelimeler[1])"] = ad
                }
                continue
            }

            if let anahtar = acik, satir.hasPrefix("*\(anahtar) ") {
                // *Anahtar kod/Metin: "…"
                let govde = String(satir.dropFirst(anahtar.count + 2))
                guard let bolucu = govde.range(of: ": ") else { continue }
                let sol = govde[..<bolucu.lowerBound]
                let p = sol.split(separator: "/", maxSplits: 1)
                let kod = String(p.first ?? "")
                let ad = p.count > 1 ? String(p[1]) : kod
                taslaklar[anahtar]?.secimler.append((kod, ad))
                continue
            }

            // Üst düzey nitelik: *Ad: "değer" ya da *Ad: değer
            if acik == nil, let bolucu = satir.range(of: ": ") {
                let ad = String(satir[satir.index(after: satir.startIndex)..<bolucu.lowerBound])
                guard !ad.contains(" "), !ad.contains(".") else { continue }
                var deger = String(satir[bolucu.upperBound...]).trimmingCharacters(in: .whitespaces)
                if deger.hasPrefix("\"") && deger.hasSuffix("\"") && deger.count >= 2 {
                    deger = String(deger.dropFirst().dropLast())
                }
                if nitelikler[ad] == nil { nitelikler[ad] = deger }
            }
        }

        var secenekler: [String: PPDSecenegi] = [:]
        for (anahtar, t) in taslaklar {
            let secimler = t.secimler.map { s in
                PPDSecimi(kod: s.kod, ad: trSecimAdi["\(anahtar) \(s.kod)"] ?? s.ad, ingilizceAd: s.ad)
            }
            secenekler[anahtar] = PPDSecenegi(anahtar: anahtar, ad: trSecenekAdi[anahtar] ?? t.ad,
                                             secimler: secimler, varsayilan: varsayilanlar[anahtar])
        }
        return PPDKatalogu(yol: yol, secenekler: secenekler, sira: sira, nitelikler: nitelikler)
    }
}
