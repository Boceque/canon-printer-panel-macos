import CUPS
import Foundation

struct CUPSHatasi: LocalizedError, Sendable {
    let islem: String
    let kod: Int
    let mesaj: String

    var errorDescription: String? { mesaj.isEmpty ? islem : "\(islem): \(mesaj)" }

    /// 401/403: yetki sorunu.
    var yetkiHatasi: Bool {
        kod == Int(IPP_STATUS_ERROR_FORBIDDEN.rawValue) || kod == Int(IPP_STATUS_ERROR_NOT_AUTHORIZED.rawValue)
            || kod == Int(IPP_STATUS_ERROR_NOT_AUTHENTICATED.rawValue)
    }
}

struct KuyrukOzeti: Hashable, Sendable {
    let ad: String
    let varsayilan: Bool
    let bilgi: String
    let model: String
    let aygitAdresi: String
}

/// libcups üzerinden yerel CUPS sunucusuyla ve yazıcının kendisiyle konuşan ince katman.
/// Tüm çağrılar engelleyicidir; arayüz iş parçacığından değil arka plandan çağrılmalıdır.
enum CUPSIstemci {
    static func kuyrukURI(_ kuyruk: String) -> String { "ipp://localhost/printers/\(kuyruk)" }
    static func isURI(_ no: Int) -> String { "ipp://localhost/jobs/\(no)" }
    static func ppdYolu(_ kuyruk: String) -> String { "/etc/cups/ppd/\(kuyruk).ppd" }
    static var kullanici: String { String(cString: cupsUser()) }

    // MARK: - Temel istek

    private static func istek(_ op: ipp_op_t) -> OpaquePointer {
        let r = ippNewRequest(op)!
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_NAME, "requesting-user-name", nil, cupsUser())
        return r
    }

    private static func sonHata(_ islem: String) -> CUPSHatasi {
        CUPSHatasi(islem: islem, kod: Int(cupsLastError().rawValue), mesaj: String(cString: cupsLastErrorString()))
    }

    /// İsteği gönderir (istek tüketilir). Başarılıysa yanıtı döndürür; çağıran `ippDelete` etmelidir.
    private static func gonder(_ r: OpaquePointer, kaynak: String, http: OpaquePointer? = nil,
                               islem: String) throws -> OpaquePointer {
        guard let yanit = cupsDoRequest(http, r, kaynak) else { throw sonHata(islem) }
        let durum = Int(ippGetStatusCode(yanit).rawValue)
        if durum > 0x00FF {
            let hata = CUPSHatasi(islem: islem, kod: durum, mesaj: String(cString: cupsLastErrorString()))
            ippDelete(yanit)
            throw hata
        }
        return yanit
    }

    private static func istenenler(_ r: OpaquePointer, _ adlar: [String]) {
        cDizgeleriyle(adlar) {
            _ = ippAddStrings(r, IPP_TAG_OPERATION, IPP_TAG_KEYWORD, "requested-attributes",
                              Int32(adlar.count), nil, $0)
        }
    }

    private static func secenekleriKodla(_ r: OpaquePointer, _ secenekler: [String: String], grup: ipp_tag_t) {
        var n: Int32 = 0
        var liste: UnsafeMutablePointer<cups_option_t>? = nil
        for (ad, deger) in secenekler.sorted(by: { $0.key < $1.key }) {
            n = cupsAddOption(ad, deger, n, &liste)
        }
        cupsEncodeOptions2(r, n, liste, grup)
        cupsFreeOptions(n, liste)
    }

    // MARK: - Kuyruklar

    static func kuyruklar() -> [KuyrukOzeti] {
        var hedefler: UnsafeMutablePointer<cups_dest_t>? = nil
        let n = cupsGetDests2(nil, &hedefler)
        defer { cupsFreeDests(n, hedefler) }
        guard let h = hedefler, n > 0 else { return [] }
        var sonuc: [KuyrukOzeti] = []
        for i in 0..<Int(n) {
            let d = h[i]
            if d.instance != nil { continue }
            func secenek(_ ad: String) -> String {
                guard let p = cupsGetOption(ad, d.num_options, d.options) else { return "" }
                return String(cString: p)
            }
            sonuc.append(KuyrukOzeti(ad: String(cString: d.name), varsayilan: d.is_default != 0,
                                     bilgi: secenek("printer-info"), model: secenek("printer-make-and-model"),
                                     aygitAdresi: secenek("device-uri")))
        }
        return sonuc
    }

    /// Canon kuyruğunu bulur: önce varsayılan Canon, sonra herhangi bir Canon, sonra varsayılan.
    static func canonKuyrugu() -> String? {
        let hepsi = kuyruklar()
        func canonMu(_ k: KuyrukOzeti) -> Bool {
            (k.ad + k.model + k.bilgi).localizedCaseInsensitiveContains("canon")
        }
        if let k = hepsi.first(where: { $0.varsayilan && canonMu($0) }) { return k.ad }
        if let k = hepsi.first(where: canonMu) { return k.ad }
        return hepsi.first(where: \.varsayilan)?.ad ?? hepsi.first?.ad
    }

    static func kuyrukOznitelikleri(_ kuyruk: String) throws -> IPPOznitelikler {
        let r = istek(IPP_OP_GET_PRINTER_ATTRIBUTES)
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", nil, kuyrukURI(kuyruk))
        istenenler(r, ["all", "printer-description", "job-template", "printer-error-policy",
                       "printer-error-policy-supported", "job-hold-until-default", "device-uri"])
        let y = try gonder(r, kaynak: "/", islem: "Kuyruk durumu alınamadı")
        defer { ippDelete(y) }
        return IPPCozucu.tumu(y)
    }

    // MARK: - Yazıcının kendisi (ağ)

    static let cihazOznitelikAdlari = [
        "printer-state", "printer-state-reasons", "printer-state-message", "printer-alert",
        "printer-alert-description", "printer-firmware-string-version", "printer-firmware-name",
        "printer-make-and-model", "printer-info", "printer-name", "printer-dns-sd-name",
        "printer-device-id", "printer-uuid", "printer-up-time", "printer-more-info",
        "printer-supply-info-uri", "printer-icons", "printer-is-accepting-jobs", "queued-job-count",
        "marker-names", "marker-levels", "marker-colors", "marker-types", "printer-input-tray",
        "printer-output-tray", "media-default", "media-supported", "print-color-mode-supported",
        "pages-per-minute", "pages-per-minute-color", "printer-kind", "identify-actions-supported",
        "printer-uri-supported", "printer-location", "copies-supported", "sides-supported",
        "print-quality-supported", "printer-resolution-supported", "media-type-supported",
        "media-source-supported", "document-format-supported",
    ]

    private static func cihazBaglantisi(_ adres: CihazAdresi, zamanAsimiMs: Int) throws -> OpaquePointer {
        guard let http = httpConnect2(adres.host, Int32(adres.port), nil, AF_UNSPEC,
                                      HTTP_ENCRYPTION_IF_REQUESTED, 1, Int32(zamanAsimiMs), nil) else {
            throw CUPSHatasi(islem: "Yazıcıya ağdan ulaşılamadı", kod: -1, mesaj: "\(adres.host):\(adres.port)")
        }
        httpSetTimeout(http, Double(zamanAsimiMs) / 1000, nil, nil)
        return http
    }

    static func cihazOznitelikleri(_ adres: CihazAdresi, zamanAsimiMs: Int = 4000) throws -> IPPOznitelikler {
        let http = try cihazBaglantisi(adres, zamanAsimiMs: zamanAsimiMs)
        defer { httpClose(http) }
        let r = ippNewRequest(IPP_OP_GET_PRINTER_ATTRIBUTES)!
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", nil, adres.uri)
        istenenler(r, cihazOznitelikAdlari)
        let y = try gonder(r, kaynak: adres.yol, http: http, islem: "Yazıcı durumu okunamadı")
        defer { ippDelete(y) }
        return IPPCozucu.tumu(y)
    }

    /// Identify-Printer: yazıcının ışıklarını yakıp söndürür.
    static func yaziciyiTanit(_ adres: CihazAdresi) throws {
        let http = try cihazBaglantisi(adres, zamanAsimiMs: 4000)
        defer { httpClose(http) }
        let r = ippNewRequest(IPP_OP_IDENTIFY_PRINTER)!
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", nil, adres.uri)
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_NAME, "requesting-user-name", nil, cupsUser())
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_KEYWORD, "identify-actions", nil, "flash")
        let y = try gonder(r, kaynak: adres.yol, http: http, islem: "Yazıcı bulunamadı")
        ippDelete(y)
    }

    // MARK: - İşler

    static let isOznitelikAdlari = [
        "job-id", "job-name", "job-state", "job-state-reasons", "job-printer-state-message",
        "job-originating-user-name", "time-at-creation", "time-at-processing", "time-at-completed",
        "job-k-octets", "job-media-sheets-completed", "job-impressions-completed", "job-impressions",
        "job-hold-until", "document-format", "document-format-supplied", "document-format-detected",
        "number-of-documents", "copies", "CNIJPrintQuality", "CNIJMediaType", "CNIJGrayScale",
        "Resolution", "PageSize", Sabitleme.isaretOzniteligi,
    ]

    static func isler(_ kuyruk: String, tamamlanan: Bool, oznitelikler: [String] = isOznitelikAdlari) throws -> [IPPOznitelikler] {
        let r = istek(IPP_OP_GET_JOBS)
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", nil, kuyrukURI(kuyruk))
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_KEYWORD, "which-jobs", nil, tamamlanan ? "completed" : "not-completed")
        ippAddBoolean(r, IPP_TAG_OPERATION, "my-jobs", 0)
        istenenler(r, oznitelikler)
        let y = try gonder(r, kaynak: "/", islem: "İş listesi alınamadı")
        defer { ippDelete(y) }
        return IPPCozucu.kayitlar(y, grup: IPP_TAG_JOB)
    }

    static func isAyrintisi(_ no: Int) throws -> IPPOznitelikler {
        let r = istek(IPP_OP_GET_JOB_ATTRIBUTES)
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_URI, "job-uri", nil, isURI(no))
        istenenler(r, ["all"])
        let y = try gonder(r, kaynak: "/jobs", islem: "İş ayrıntısı alınamadı")
        defer { ippDelete(y) }
        return IPPCozucu.kayitlar(y, grup: IPP_TAG_JOB).first ?? IPPOznitelikler()
    }

    private static func isIslemi(_ op: ipp_op_t, _ no: Int, islem: String,
                                 ek: ((OpaquePointer) -> Void)? = nil) throws {
        let r = istek(op)
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_URI, "job-uri", nil, isURI(no))
        ek?(r)
        let y = try gonder(r, kaynak: "/jobs", islem: islem)
        ippDelete(y)
    }

    static func isIptal(_ no: Int) throws { try isIslemi(IPP_OP_CANCEL_JOB, no, islem: "İş iptal edilemedi") }
    static func isBeklet(_ no: Int) throws { try isIslemi(IPP_OP_HOLD_JOB, no, islem: "İş bekletilemedi") }
    static func isSurdur(_ no: Int) throws { try isIslemi(IPP_OP_RELEASE_JOB, no, islem: "İş sürdürülemedi") }
    static func isYenidenBas(_ no: Int) throws { try isIslemi(IPP_OP_RESTART_JOB, no, islem: "İş yeniden yazdırılamadı") }

    /// Set-Job-Attributes: PPD seçenekleri dahil her şeyi işe yazar. `job-hold-until=no-hold` işi serbest bırakır.
    static func isAyarla(_ no: Int, _ secenekler: [String: String]) throws {
        try isIslemi(IPP_OP_SET_JOB_ATTRIBUTES, no, islem: "İş ayarları değiştirilemedi") { r in
            secenekleriKodla(r, secenekler, grup: IPP_TAG_JOB)
        }
    }

    // MARK: - Yazdırma

    static func dosyaYazdir(kuyruk: String, dosya: URL, baslik: String, secenekler: [String: String]) throws -> Int {
        var n: Int32 = 0
        var liste: UnsafeMutablePointer<cups_option_t>? = nil
        for (ad, deger) in secenekler.sorted(by: { $0.key < $1.key }) { n = cupsAddOption(ad, deger, n, &liste) }
        defer { cupsFreeOptions(n, liste) }
        let no = cupsPrintFile2(nil, kuyruk, dosya.path, baslik, n, liste)
        if no <= 0 { throw sonHata("Yazdırılamadı") }
        return Int(no)
    }

    // MARK: - Yönetim (parolasız: kullanıcı _lpadmin grubunda)

    /// CUPS-Add-Modify-Printer ile kuyruk özniteliği değiştirir (durum, hata politikası, uyarıları temizleme).
    static func kuyrukAyarla(_ kuyruk: String, islem: String, _ doldur: (OpaquePointer) -> Void) throws {
        let r = istek(IPP_OP_CUPS_ADD_MODIFY_PRINTER)
        ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", nil, kuyrukURI(kuyruk))
        doldur(r)
        let y = try gonder(r, kaynak: "/admin/", islem: islem)
        ippDelete(y)
    }

    /// Kuyruğu durdurur (yeni işler bekler, yazıcıya gönderilmez).
    static func kuyruguDurdur(_ kuyruk: String) throws {
        try kuyrukAyarla(kuyruk, islem: "Kuyruk durdurulamadı") { r in
            ippAddInteger(r, IPP_TAG_PRINTER, IPP_TAG_ENUM, "printer-state", Int32(IPP_PSTATE_STOPPED.rawValue))
        }
    }

    /// Eski uyarıları (ör. geçmişten kalan "kağıt yok") siler.
    static func uyarilariTemizle(_ kuyruk: String) throws {
        try kuyrukAyarla(kuyruk, islem: "Uyarılar temizlenemedi") { r in
            ippAddString(r, IPP_TAG_PRINTER, IPP_TAG_KEYWORD, "printer-state-reasons", nil, "none")
        }
    }
}
