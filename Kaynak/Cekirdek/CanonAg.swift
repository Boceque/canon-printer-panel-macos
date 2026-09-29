import Darwin
import Foundation

// Canon'un yeni IJ yazıcılarıyla (G3010 dahil) doğrudan konuşma.
//
// Canlı olarak doğrulandı (2026-09-29, bu yazıcıda):
// - Mac sürücüsünün (Command2CanonIJ) bakım komutları eski BJL biçiminde (@CLEANING=1K); yazıcı bunları
//   IPP ile de ham 9100 ile de alıp "tamamlandı, 0 sayfa" deyip YOK SAYIYOR.
// - Doğrusu Canon'un Linux sürücüsünün (cnijfilter2, cmdtocanonij3 + lgmon3) yaptığı: IVEC XML işi
//   (StartJob servicetype="maintenance" → SetJobConfiguration → Cleaning/TestPrint/… → EndJob) ham TCP 9100'e.
// - Durum ve sorgular (GetStatus, GetCapability, GetConfiguration) CHMP ile: HTTP 80, /canon/ij/command2/port1,
//   aynı TCP bağlantısında önce POST (boş 200 onayı) sonra GET (chunked yanıt), başlık "X-CHMP-Version: 1.0.0".
// - Cihaz ayarları (otomatik kapanma vb.) da iş içinde (StartJob servicetype="device" → SetConfiguration → EndJob)
//   9100'den gider; CHMP'den iş başlatılamaz ("NotStart").

struct CanonAgHatasi: LocalizedError {
    let aciklama: String
    var errorDescription: String? { aciklama }
}

enum CanonAg {
    static let kontrolAdresi = "/canon/ij/command2/port1"

    // MARK: - Soket

    /// Zaman aşımlı TCP bağlantısı (getaddrinfo: IP ya da .local adı).
    private static func baglan(_ host: String, _ port: Int, zaman: TimeInterval) throws -> Int32 {
        var ipucu = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var sonuc: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &ipucu, &sonuc) == 0, let ilk = sonuc else {
            throw CanonAgHatasi(aciklama: "Yazıcının adresi çözülemedi (\(host)).")
        }
        defer { freeaddrinfo(sonuc) }
        var ai: UnsafeMutablePointer<addrinfo>? = ilk
        while let a = ai {
            let fd = socket(a.pointee.ai_family, a.pointee.ai_socktype, a.pointee.ai_protocol)
            if fd >= 0 {
                var bir: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &bir, socklen_t(MemoryLayout<Int32>.size))
                let bayrak = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, bayrak | O_NONBLOCK)
                var r = connect(fd, a.pointee.ai_addr, a.pointee.ai_addrlen)
                if r != 0 && errno == EINPROGRESS {
                    var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    if poll(&p, 1, Int32(zaman * 1000)) == 1 {
                        var hata: Int32 = 0
                        var uz = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(fd, SOL_SOCKET, SO_ERROR, &hata, &uz)
                        r = hata == 0 ? 0 : -1
                    } else {
                        r = -1
                    }
                }
                if r == 0 {
                    _ = fcntl(fd, F_SETFL, bayrak)   // yeniden engelleyici; okuma/yazma zaman aşımı SO_*TIMEO ile
                    var tv = timeval(tv_sec: Int(zaman), tv_usec: Int32((zaman - floor(zaman)) * 1_000_000))
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                    return fd
                }
                close(fd)
            }
            ai = a.pointee.ai_next
        }
        throw CanonAgHatasi(aciklama: "Yazıcıya bağlanılamadı (\(host):\(port)). Kapalı ya da uyku modunda olabilir.")
    }

    private static func hepsiniYaz(_ fd: Int32, _ veri: Data) throws {
        try veri.withUnsafeBytes { (tampon: UnsafeRawBufferPointer) in
            var gonderilen = 0
            while gonderilen < tampon.count {
                let n = write(fd, tampon.baseAddress!.advanced(by: gonderilen), tampon.count - gonderilen)
                if n <= 0 { throw CanonAgHatasi(aciklama: "Yazıcıya veri gönderilemedi.") }
                gonderilen += n
            }
        }
    }

    // MARK: - Ham 9100 (iş verisi)

    static func gonder9100(host: String, _ veri: Data, zaman: TimeInterval = 10) throws {
        let fd = try baglan(host, 9100, zaman: zaman)
        defer { close(fd) }
        try hepsiniYaz(fd, veri)
        shutdown(fd, SHUT_WR)
        // Yazıcı bağlantıyı kapatana kadar kısa süre bekle (veri tamamen alınsın).
        var tampon = [UInt8](repeating: 0, count: 512)
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = read(fd, &tampon, tampon.count)
    }

    // MARK: - CHMP (HTTP 80)

    /// Aynı bağlantı üzerinden yanıt okumak için küçük tampon.
    private final class Okuyucu {
        let fd: Int32
        var tampon = Data()
        init(_ fd: Int32) { self.fd = fd }

        func doldur() throws {
            var parca = [UInt8](repeating: 0, count: 8192)
            let n = read(fd, &parca, parca.count)
            if n <= 0 { throw CanonAgHatasi(aciklama: "Yazıcı yanıt vermedi.") }
            tampon.append(contentsOf: parca[0..<n])
        }

        func satir() throws -> String {
            while true {
                if let r = tampon.range(of: Data("\r\n".utf8)) {
                    let s = String(decoding: tampon[tampon.startIndex..<r.lowerBound], as: UTF8.self)
                    tampon.removeSubrange(tampon.startIndex..<r.upperBound)
                    return s
                }
                try doldur()
            }
        }

        func bayt(_ n: Int) throws -> Data {
            while tampon.count < n { try doldur() }
            let d = tampon.prefix(n)
            tampon.removeFirst(n)
            return Data(d)
        }

        /// Durum kodu, başlıklar ve gövde. Uzunluğu belirtilmeyen yanıtın gövdesi boş kabul edilir
        /// (CHMP'nin POST onayı böyle gelir; okumaya kalkarsak bağlantı açık olduğu için takılırız).
        func yanit() throws -> (kod: Int, govde: Data) {
            let ilk = try satir()
            let kod = Int(ilk.split(separator: " ").dropFirst().first ?? "") ?? 0
            var basliklar: [String: String] = [:]
            while true {
                let s = try satir()
                if s.isEmpty { break }
                if let i = s.firstIndex(of: ":") {
                    basliklar[s[..<i].lowercased()] = s[s.index(after: i)...].trimmingCharacters(in: .whitespaces)
                }
            }
            if basliklar["transfer-encoding"]?.lowercased() == "chunked" {
                var govde = Data()
                while true {
                    let boyut = Int(try satir().split(separator: ";").first ?? "0", radix: 16) ?? 0
                    if boyut == 0 { _ = try satir(); break }
                    govde.append(try bayt(boyut))
                    _ = try satir()
                }
                return (kod, govde)
            }
            if let u = basliklar["content-length"], let n = Int(u) { return (kod, try bayt(n)) }
            return (kod, Data())
        }
    }

    /// CHMP isteği: POST (komut) → boş onay → aynı bağlantıda GET → gerçek yanıt (XML).
    static func chmp(host: String, _ xml: String, adres: String = kontrolAdresi, zaman: TimeInterval = 10) throws -> String {
        let fd = try baglan(host, 80, zaman: zaman)
        defer { close(fd) }
        let govde = Data(xml.utf8)
        // Başlıklar ve sıraları Canon'un kendi aracının paketleriyle aynı; sürüm 1.0.0 olmazsa yazıcı sessizce atar.
        let post = "POST \(adres) HTTP/1.1\r\nContent-Length: \(govde.count)\r\nX-CHMP-Timeout: 20\r\n"
            + "Connection: Keep-Alive\r\nContent-Type: application/octet-stream\r\nHost: \(host)\r\n"
            + "X-CHMP-Version: 1.0.0\r\n\r\n"
        try hepsiniYaz(fd, Data(post.utf8) + govde)
        let okuyucu = Okuyucu(fd)
        let onay = try okuyucu.yanit()
        guard (200..<300).contains(onay.kod) else {
            throw CanonAgHatasi(aciklama: "Yazıcı komutu kabul etmedi (HTTP \(onay.kod)).")
        }
        let get = "GET \(adres) HTTP/1.1\r\nConnection: Keep-Alive\r\nContent-Type: application/octet-stream\r\n"
            + "Host: \(host)\r\nX-CHMP-Version: 1.0.0\r\n\r\n"
        try hepsiniYaz(fd, Data(get.utf8))
        let cevap = try okuyucu.yanit()
        guard (200..<300).contains(cevap.kod) else {
            throw CanonAgHatasi(aciklama: "Yazıcıdan yanıt alınamadı (HTTP \(cevap.kod)).")
        }
        return String(decoding: cevap.govde, as: UTF8.self)
    }
}

// MARK: - IVEC komutları

enum IVEC {
    private static let xmlEski = #"<?xml version="1.0" encoding="utf-8" ?>"#
    private static let xmlYeni = #"<?xml version="1.0" encoding="utf-8"?>"#
    /// Canon'un kendi şablonundaki yazım hatası; özgün çıktıyla bayt bayt aynı olsun diye korunuyor.
    private static let xmlBakim = #"<?xml version="1.0" encoding="job_descriptionutf-8" ?>"#
    private static let ns = #" xmlns:ivec="http://www.canon.com/ns/cmd/2008/07/common/""#
    private static let nsIkisi = ns + #" xmlns:vcn="http://www.canon.com/ns/cmd/2008/07/canon/""#
    static let isNo = "00000001"

    private static func komut(_ bas: String, _ ad: String, _ islem: String, servis: String, _ icerik: String) -> String {
        "\(bas)<cmd\(ad)><ivec:contents><ivec:operation>\(islem)</ivec:operation><ivec:param_set servicetype=\"\(servis)\">\(icerik)</ivec:param_set></ivec:contents></cmd>"
    }

    static func sorgu(_ islem: String, servis: String) -> String {
        komut(xmlEski, ns, islem, servis: servis, "")
    }

    private static func isBaslat(_ servis: String) -> String {
        komut(xmlEski, nsIkisi, "StartJob", servis: servis,
              "<ivec:jobID>\(isNo)</ivec:jobID><ivec:bidi>0</ivec:bidi><ivec:jobname/><ivec:username/><ivec:computername/>"
              + "<ivec:job_description><![CDATA[\(UUID().uuidString.lowercased())]]></ivec:job_description>"
              + "<vcn:host_environment>mac</vcn:host_environment>")
    }

    private static func isBitir(_ servis: String) -> String {
        komut(xmlEski, ns, "EndJob", servis: servis, "<ivec:jobID>\(isNo)</ivec:jobID>")
    }

    private static var simdi: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss"
        return f.string(from: Date())
    }

    /// Bakım işi: StartJob → SetJobConfiguration → işlem → EndJob (9100'e gönderilir).
    static func bakimIsi(islem: String, icerik: String) -> Data {
        let s = isBaslat("maintenance")
            + komut(xmlBakim, nsIkisi, "SetJobConfiguration", servis: "maintenance",
                    "<ivec:jobID>\(isNo)</ivec:jobID><ivec:datetime>\(simdi)</ivec:datetime>")
            + komut(xmlYeni, ns, islem, servis: "maintenance", icerik + "<ivec:jobID>\(isNo)</ivec:jobID>")
            + isBitir("maintenance")
        return Data(s.utf8)
    }

    /// Süren bakım işini iptal eder (CHMP'den; Canon sürücüsünün CancelJob_Maintenance'ı). Canlı denendi:
    /// temizlik de silindir temizliği de "OK" alıp birkaç saniyede boşa döner.
    static func iptal(servis: String = "maintenance") -> String {
        komut(xmlYeni, ns, "CancelJob", servis: servis, "<ivec:jobID>\(isNo)</ivec:jobID>")
    }

    /// Tüm renklerin mürekkep sayacını sıfırlar. SetConfiguration öğesi DEĞİL (yazıcı her biçimini reddetti);
    /// iş gerektirmeyen üretici komutu: CHMP'den VendorCmd + vcn:ijoperation ResetCounter → "OK" (canlı doğrulandı).
    static func murekkepSayaciSifirla() -> String {
        komut(xmlEski, nsIkisi, "VendorCmd", servis: "device",
              "<ivec:jobID>\(isNo)</ivec:jobID><vcn:ijoperation>ResetCounter</vcn:ijoperation>"
              + #"<vcn:type id="ink"><vcn:resetink>all</vcn:resetink></vcn:type>"#)
    }

    /// Cihaz ayarı işi: StartJob → SetConfiguration → EndJob (9100'e gönderilir).
    static func cihazIsi(_ ayarlar: String) -> Data {
        let s = isBaslat("device")
            + komut(xmlEski, nsIkisi, "SetConfiguration", servis: "device", "<ivec:jobID>\(isNo)</ivec:jobID>" + ayarlar)
            + isBitir("device")
        return Data(s.utf8)
    }

    // MARK: Ayrıştırma

    static func deger(_ xml: String, _ etiket: String) -> String? {
        guard let bas = xml.range(of: "<\(etiket)>"),
              let son = xml.range(of: "</\(etiket)>", range: bas.upperBound..<xml.endIndex) else { return nil }
        return xml[bas.upperBound..<son.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Durum: Sendable, Equatable {
        var durum: String            // idle, processing, stopped, …
        var ayrinti: String          // status_detail
        var bakimIslemi: String?     // jobinfo/maintenance_operation (ör. Cleaning, TestPrint)
        var bakimTuru: String?
        var destekKodu: String?      // current_support_code (ör. 1000)

        var bosta: Bool { durum == "idle" }

        /// Kullanıcıya gösterilecek kısa ad.
        var durumAdi: String {
            switch durum {
            case "idle": return "hazır"
            case "processing": return "çalışıyor"
            case "stopped": return "durdu"
            default: return durum
            }
        }
    }

    static func durumCoz(_ xml: String) -> Durum {
        let is_ = deger(xml, "ivec:jobinfo") ?? ""
        let kod = deger(xml, "ivec:current_support_code")
        return Durum(durum: deger(xml, "ivec:status") ?? "?",
                     ayrinti: deger(xml, "ivec:status_detail") ?? "",
                     bakimIslemi: deger(is_, "ivec:maintenance_operation"),
                     bakimTuru: deger(is_, "ivec:type"),
                     destekKodu: (kod?.isEmpty ?? true) ? nil : kod)
    }

    struct CihazAyarlari: Sendable, Equatable {
        var otomatikAcilma: Bool?
        var otomatikKapanma: Bool?
        var kapanmaDakika: Int?
        var sessizMod: String?          // ON, OFF, time
        var sessizBaslangic: String?    // "2100"
        var sessizBitis: String?        // "0700"
        var murekkepBildirimi: Bool?
    }

    static func cihazAyarlariCoz(_ xml: String) -> CihazAyarlari {
        let kapanma = deger(xml, "ivec:autopoweroff") ?? ""
        let sessiz = deger(xml, "ivec:silentmode") ?? ""
        return CihazAyarlari(
            otomatikAcilma: deger(xml, "ivec:autopoweron").map { $0 == "ON" },
            otomatikKapanma: deger(kapanma, "ivec:mode").map { $0 == "ON" },
            kapanmaDakika: deger(kapanma, "ivec:time").flatMap { Int($0) },
            sessizMod: deger(sessiz, "ivec:mode"),
            sessizBaslangic: deger(sessiz, "ivec:starttime"),
            sessizBitis: deger(sessiz, "ivec:endtime"),
            murekkepBildirimi: deger(xml, "ivec:ink_detect").map { $0 == "ON" })
    }

    /// Yanıttaki response/response_detail (OK/NG).
    static func yanitDurumu(_ xml: String) -> (tamam: Bool, ayrinti: String) {
        (deger(xml, "ivec:response") == "OK", deger(xml, "ivec:response_detail") ?? "")
    }
}

// MARK: - Yüksek düzey: durum, ayar okuma, bakım ve ayar gönderme

enum CanonCihaz {
    static func durum(host: String) throws -> IVEC.Durum {
        IVEC.durumCoz(try CanonAg.chmp(host: host, IVEC.sorgu("GetStatus", servis: "print"), zaman: 6))
    }

    static func ayarlar(host: String) throws -> IVEC.CihazAyarlari {
        let xml = try CanonAg.chmp(host: host, IVEC.sorgu("GetConfiguration", servis: "device"), zaman: 8)
        let (tamam, ayrinti) = IVEC.yanitDurumu(xml)
        guard tamam else { throw CanonAgHatasi(aciklama: "Yazıcı ayarları okunamadı (\(ayrinti)).") }
        return IVEC.cihazAyarlariCoz(xml)
    }

    /// Yazıcı boşta değilse hata verir (çalışan baskıyı ya da bakımı bölmesin).
    private static func bostaOlmali(host: String) throws {
        let d = try durum(host: host)
        guard d.bosta else {
            throw CanonAgHatasi(aciklama: "Yazıcı şu an meşgul (\(d.durumAdi)). Bitince tekrar deneyin.")
        }
    }

    /// Bakım işini gönderir. Yazıcı meşgulse hata verir.
    static func bakimGonder(host: String, islem: String, icerik: String) throws {
        try bostaOlmali(host: host)
        try CanonAg.gonder9100(host: host, IVEC.bakimIsi(islem: islem, icerik: icerik))
    }

    /// Süren bakım işini durdurur. Yazıcı kafayı yerine alıp birkaç saniyede boşa döner.
    static func bakimiDurdur(host: String) throws {
        let (tamam, ayrinti) = IVEC.yanitDurumu(try CanonAg.chmp(host: host, IVEC.iptal(), zaman: 8))
        guard tamam else {
            throw CanonAgHatasi(aciklama: ayrinti == "NotStart" ? "Yazıcıda durdurulacak bir bakım işi yok."
                                                               : "Yazıcı durdurmayı kabul etmedi (\(ayrinti)).")
        }
    }

    /// Mürekkep sayacını sıfırlar; yazıcı onaylamazsa hata verir.
    static func murekkepSayaciniSifirla(host: String) throws {
        try bostaOlmali(host: host)
        let (tamam, ayrinti) = IVEC.yanitDurumu(try CanonAg.chmp(host: host, IVEC.murekkepSayaciSifirla(), zaman: 8))
        guard tamam else {
            throw CanonAgHatasi(aciklama: "Yazıcı sayaç sıfırlamayı kabul etmedi" + (ayrinti.isEmpty ? "." : " (\(ayrinti))."))
        }
    }

    /// Cihaz işini doğrulamadan gönderir (ör. mürekkep sayacı: yazıcı sonucu bildirmez).
    static func cihazIsiGonder(host: String, _ xml: String) throws {
        try bostaOlmali(host: host)
        try CanonAg.gonder9100(host: host, IVEC.cihazIsi(xml))
    }

    /// Cihaz ayarını gönderir ve okuyarak doğrular; doğrulanan son ayarları döndürür.
    static func ayarGonder(host: String, _ xml: String, dogrula: (IVEC.CihazAyarlari) -> Bool) throws -> IVEC.CihazAyarlari {
        try cihazIsiGonder(host: host, xml)
        for _ in 0..<8 {
            usleep(700_000)
            if let a = try? ayarlar(host: host), dogrula(a) { return a }
        }
        throw CanonAgHatasi(aciklama: "Ayar gönderildi ama yazıcıda doğrulanamadı.")
    }
}

// MARK: - Cihaz ayarı öğeleri (SetConfiguration içine)

extension IVEC {
    /// Biçimler yazıcının GetConfiguration(device) yanıtıyla aynı; değer kümeleri GetCapability(device) yanıtından.
    enum Ayar {
        /// Otomatik kapanma süreleri (dakika).
        static let kapanmaSureleri = [15, 30, 60, 120, 240]

        static func otomatikAcilma(_ acik: Bool) -> String {
            "<ivec:autopoweron>\(acik ? "ON" : "OFF")</ivec:autopoweron>"
        }

        static func otomatikKapanma(acik: Bool, dakika: Int) -> String {
            "<ivec:autopoweroff><ivec:mode>\(acik ? "ON" : "OFF")</ivec:mode><ivec:time>\(dakika)</ivec:time></ivec:autopoweroff>"
        }

        /// `mod`: ON, OFF ya da time. Saatler HHMM ("2100"). Yazıcı saatleri YALNIZ mod "time" iken kaydeder;
        /// ON/OFF ile gönderilen saatleri yok sayar (canlı denendi).
        static func sessizMod(_ mod: String, baslangic: String, bitis: String) -> String {
            "<ivec:silentmode><ivec:mode>\(mod)</ivec:mode><ivec:starttime>\(baslangic)</ivec:starttime>"
                + "<ivec:endtime>\(bitis)</ivec:endtime></ivec:silentmode>"
        }

        static func murekkepBildirimi(_ acik: Bool) -> String {
            "<ivec:ink_detect>\(acik ? "ON" : "OFF")</ivec:ink_detect>"
        }
    }
}
