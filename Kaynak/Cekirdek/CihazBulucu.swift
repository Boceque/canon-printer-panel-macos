import Foundation

/// Yazıcının ağdaki IPP adresi (şifresiz IPP; Canon 631'de düz IPP de kabul ediyor).
struct CihazAdresi: Codable, Hashable, Sendable {
    var host: String
    var port: Int
    var yol: String
    var uri: String { "ipp://\(host):\(port)\(yol)" }
}

/// Kuyruğun aygıt adresinden (dnssd://…, ipp://…) yazıcının ağ adresini bulur.
@MainActor
final class CihazBulucu: NSObject, NetServiceDelegate {
    private var servis: NetService?
    private var devam: CheckedContinuation<CihazAdresi?, Never>?
    private var bitti = true
    /// Her çözüm denemesinin kimliği: eski denemenin zaman aşımı yenisini bitirmesin.
    private var nesil = 0

    nonisolated private static let onbellekAnahtari = "cihazAdresi"

    nonisolated static func onbellek(_ aygitAdresi: String) -> CihazAdresi? {
        guard let veri = UserDefaults.standard.data(forKey: "\(onbellekAnahtari).\(aygitAdresi)") else { return nil }
        return try? JSONDecoder().decode(CihazAdresi.self, from: veri)
    }

    nonisolated static func onbellegeYaz(_ adres: CihazAdresi, _ aygitAdresi: String) {
        if let veri = try? JSONEncoder().encode(adres) {
            UserDefaults.standard.set(veri, forKey: "\(onbellekAnahtari).\(aygitAdresi)")
        }
    }

    /// Bonjour hizmet adını çıkarır: "dnssd://Canon%20G3010%20series._ipps._tcp.local./?uuid=…"
    /// → ("Canon G3010 series", "local.")
    nonisolated static func bonjourAdi(_ aygitAdresi: String) -> (ad: String, alan: String)? {
        guard aygitAdresi.hasPrefix("dnssd://") else { return nil }
        let govde = aygitAdresi.dropFirst("dnssd://".count)
        let host = govde.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        let cozulmus = host.removingPercentEncoding ?? host
        for tur in ["._ipps._tcp.", "._ipp._tcp.", "._printer._tcp.", "._pdl-datastream._tcp."] {
            if let r = cozulmus.range(of: tur) {
                let alan = String(cozulmus[r.upperBound...])
                return (String(cozulmus[..<r.lowerBound]), alan.isEmpty ? "local." : alan)
            }
        }
        return nil
    }

    /// Doğrudan ipp:// ya da ipps:// adresi ise ayrıştırır.
    nonisolated static func dogrudan(_ aygitAdresi: String) -> CihazAdresi? {
        guard aygitAdresi.hasPrefix("ipp://") || aygitAdresi.hasPrefix("ipps://"),
              let url = URL(string: aygitAdresi), let host = url.host else { return nil }
        return CihazAdresi(host: host, port: url.port ?? 631, yol: url.path.isEmpty ? "/ipp/print" : url.path)
    }

    func coz(_ aygitAdresi: String, zamanAsimi: TimeInterval = 5) async -> CihazAdresi? {
        if let d = CihazBulucu.dogrudan(aygitAdresi) { return d }
        guard let (ad, alan) = CihazBulucu.bonjourAdi(aygitAdresi) else { return nil }
        // Aynı anda tek çözüm: süren varsa bekleme, önbellekteki adresle yetin.
        guard bitti else { return CihazBulucu.onbellek(aygitAdresi) }
        for tur in ["_ipp._tcp.", "_ipps._tcp."] {
            if let adres = await bonjour(ad: ad, tur: tur, alan: alan, zamanAsimi: zamanAsimi) {
                CihazBulucu.onbellegeYaz(adres, aygitAdresi)
                return adres
            }
        }
        return nil
    }

    private func bonjour(ad: String, tur: String, alan: String, zamanAsimi: TimeInterval) async -> CihazAdresi? {
        await withCheckedContinuation { (c: CheckedContinuation<CihazAdresi?, Never>) in
            devam = c
            bitti = false
            nesil += 1
            let bu = nesil
            let s = NetService(domain: alan, type: tur, name: ad)
            s.delegate = self
            servis = s
            s.resolve(withTimeout: zamanAsimi)
            // Güvenlik ağı: çözüm hiç dönmezse.
            DispatchQueue.main.asyncAfter(deadline: .now() + zamanAsimi + 1) { [weak self] in
                guard let self, self.nesil == bu else { return }
                self.bitir(nil)
            }
        }
    }

    private func bitir(_ adres: CihazAdresi?) {
        guard !bitti else { return }
        bitti = true
        servis?.stop()
        servis = nil
        devam?.resume(returning: adres)
        devam = nil
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let host = sender.hostName
        let port = sender.port
        var yol = "/ipp/print"
        if let txt = sender.txtRecordData() {
            let sozluk = NetService.dictionary(fromTXTRecord: txt)
            if let rp = sozluk["rp"].map({ String(decoding: $0, as: UTF8.self) }), !rp.isEmpty {
                yol = rp.hasPrefix("/") ? rp : "/\(rp)"
            }
        }
        MainActor.assumeIsolated {
            guard let host, port > 0 else { bitir(nil); return }
            let temiz = host.hasSuffix(".") ? String(host.dropLast()) : host
            bitir(CihazAdresi(host: temiz, port: port, yol: yol))
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        MainActor.assumeIsolated { bitir(nil) }
    }
}
