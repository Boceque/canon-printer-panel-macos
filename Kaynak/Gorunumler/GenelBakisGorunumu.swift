import AppKit
import SwiftUI

struct GenelBakisGorunumu: View {
    @Environment(UygulamaModeli.self) private var model
    @State private var onay: GenelBakisOnayi?

    var body: some View {
        Sayfa(baslik: Bolum.genelBakis.ad,
              altBaslik: "Yazıcının ve Mac'teki kuyruğun anlık durumu",
              simge: Bolum.genelBakis.simge) {
            if ilkYukleme {
                yukleniyorGorunumu
            } else if model.kuyruk == nil && model.kuyrukAdi.isEmpty {
                yaziciYokGorunumu
            } else {
                kahramanKarti
                katmanKarti
                if let isi = model.etkinIs {
                    etkinIsKarti(isi)
                }
                sabitlemeKarti
                hizliErisim
                murekkepNotu
            }
        }
        .animation(.snappy, value: model.durumOzeti)
        .animation(.snappy, value: model.etkinIs?.id)
        .animation(.snappy, value: model.sabitleme)
        .confirmationDialog(onay?.baslik ?? "", isPresented: onayGosteriliyor,
                            titleVisibility: .visible, presenting: onay) { o in
            Button(o.dugme, role: o.yikici ? .destructive : nil) { calistir(o) }
            Button("Vazgeç", role: .cancel) {}
        } message: { o in
            Text(o.mesaj)
        }
    }

    // MARK: Durumlar

    private var ilkYukleme: Bool { model.kuyruk == nil && model.kuyrukHatasi == nil }

    private var onayGosteriliyor: Binding<Bool> {
        Binding(get: { onay != nil }, set: { if !$0 { onay = nil } })
    }

    private func calistir(_ o: GenelBakisOnayi) {
        Task {
            switch o {
            case .isIptal(let id, _): await model.isIptal(id)
            case .sabitlemeKaldir: await model.sabitlemeyiKaldir()
            case .kuyrukDurdur: await model.kuyruguDurdur()
            }
        }
    }

    private var modelAdi: String {
        if let m = model.cihaz?.model, !m.isEmpty { return m }
        let k = model.katalog?.model ?? ""
        if k.contains("G3000") { return "Canon G3010" }
        if !k.isEmpty { return k }
        let kuyruk = model.kuyrukAdi
        if kuyruk.contains("G3000") { return "Canon G3010" }
        return kuyruk.isEmpty ? "Yazıcı" : kuyruk.replacingOccurrences(of: "_", with: " ")
    }

    private var yukleniyorGorunumu: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(model.mesgul ?? "Yazıcının durumu okunuyor…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var yaziciYokGorunumu: some View {
        ContentUnavailableView {
            Label("Yazıcı bulunamadı", systemImage: "printer")
        } description: {
            Text("Bu Mac'te kurulu bir yazıcı yok. Canon G3010'u Sistem Ayarları › Yazıcılar ve Tarayıcılar bölümünden ekleyin, sonra uygulamayı yeniden açın.")
        } actions: {
            Button("Yazıcı ayarlarını aç") { model.sistemYaziciAyarlariniAc() }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: 1. Kahraman kartı

    private var kahramanKarti: some View {
        let ozet = model.durumOzeti
        return Kart(vurgu: Tema.renk(ozet.seviye)) {
            HStack(alignment: .top, spacing: 18) {
                YaziciResmi(boyut: 96)
                VStack(alignment: .leading, spacing: 8) {
                    Text(modelAdi)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(alignment: .center, spacing: 8) {
                        DurumSimgesi(seviye: ozet.seviye, boyut: 20)
                        Text(ozet.baslik)
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let ayrinti = ozet.ayrinti, !ayrinti.isEmpty {
                        Text(ayrinti)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if !ozet.eylemler.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(ozet.eylemler.enumerated()), id: \.element) { sira, e in
                                GenelEylemDugmesi(eylem: e, birincil: sira == 0) {
                                    Task { await model.eylem(e) }
                                }
                            }
                        }
                        .padding(.top, 4)
                        .disabled(model.mesgul != nil)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 2. İki katman

    private var katmanKarti: some View {
        Kart(baslik: "Yazıcı ve Mac ne diyor?", simge: "square.2.layers.3d") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    yaziciBolmesi
                    Divider()
                    kuyrukBolmesi
                }
                .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    yaziciBolmesi
                    Divider()
                    kuyrukBolmesi
                }
            }
            if let ipucu = celiskiIpucu {
                IpucuKutusu(baslik: ipucu.baslik, metin: ipucu.metin, simge: "clock.arrow.circlepath")
            }
        }
    }

    private var yaziciBolmesi: some View {
        VStack(alignment: .leading, spacing: 8) {
            GenelBolmeBasligi(baslik: "Yazıcı", altBaslik: "Cihazın kendisi, ağdan okunur", simge: "printer")
            if let c = model.cihaz {
                GenelDurumSatiri(seviye: cihazSeviyesi(c), metin: c.durum.ad)
                let nedenler = c.nedenler.gercekler
                if nedenler.isEmpty {
                    GenelSorunYok()
                } else {
                    ForEach(nedenler) { GenelNedenSatiri(neden: $0) }
                }
                if let uyari = c.uyariMetni {
                    Text(uyari)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                GenelDurumSatiri(seviye: .bilinmiyor, metin: "Ulaşılamıyor")
            }
            if let hata = model.cihazHatasi {
                Label(sadeHata(hata), systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(hata)
            }
            Text(model.cihazSonOkuma == nil ? "Henüz okunmadı" : "Son okuma: \(Bicim.goreceli(model.cihazSonOkuma))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: .infinity, alignment: .topLeading)
    }

    private var kuyrukBolmesi: some View {
        VStack(alignment: .leading, spacing: 8) {
            GenelBolmeBasligi(baslik: "Mac'teki kuyruk", altBaslik: "macOS yazdırma sistemi", simge: "desktopcomputer")
            if let k = model.kuyruk {
                if k.durdurulmus {
                    GenelDurumSatiri(seviye: .uyari, metin: "Durduruldu")
                    Text("Yeni işler yazıcıya gönderilmiyor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    GenelDurumSatiri(seviye: kuyrukSeviyesi(k), metin: k.durum.ad)
                }
                Label(k.isKabulEdiyor ? "Yeni işleri kabul ediyor" : "Yeni işleri kabul etmiyor",
                      systemImage: k.isKabulEdiyor ? "tray.and.arrow.down" : "nosign")
                    .font(.callout)
                    .foregroundStyle(k.isKabulEdiyor ? Color.secondary : Color.red)
                let nedenler = k.nedenler.gercekler.filter { $0.kok != "paused" }
                if nedenler.isEmpty {
                    GenelSorunYok()
                } else {
                    ForEach(nedenler) { GenelNedenSatiri(neden: $0) }
                }
                Label(model.bekleyenIsSayisi == 0 ? "Kuyrukta iş yok" : "\(model.bekleyenIsSayisi) iş kuyrukta",
                      systemImage: "doc.on.doc")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !k.mesaj.isEmpty {
                    Text(k.mesaj)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                GenelDurumSatiri(seviye: .bilinmiyor, metin: "Okunamadı")
                if let hata = model.kuyrukHatasi {
                    Text(hata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: .infinity, alignment: .topLeading)
    }

    private func cihazSeviyesi(_ c: CihazDurumu) -> DurumSeviyesi {
        if c.durum == .durdu || c.nedenler.enYuksekOnem == .hata { return .hata }
        if c.sorunVar { return .uyari }
        switch c.durum {
        case .yazdiriyor: return .calisiyor
        case .bilinmiyor: return .bilinmiyor
        default: return .hazir
        }
    }

    private func kuyrukSeviyesi(_ k: KuyrukDurumu) -> DurumSeviyesi {
        if !k.isKabulEdiyor { return .uyari }
        switch k.durum {
        case .yazdiriyor: return .calisiyor
        case .bosta: return .hazir
        case .durdu: return .uyari
        case .bilinmiyor: return .bilinmiyor
        }
    }

    /// Teknik ayrıntıyı (parantez içi) ipucuna bırakır.
    private func sadeHata(_ metin: String) -> String {
        guard let r = metin.range(of: " (") else { return metin }
        return String(metin[..<r.lowerBound])
    }

    /// İki katman birbirini tutmuyorsa kısa açıklama.
    private var celiskiIpucu: (baslik: String, metin: String)? {
        guard let k = model.kuyruk else { return nil }
        let eski = model.eskiUyarilar
        let durduHazir = k.durdurulmus && (model.cihaz.map { !$0.sorunVar } ?? false)
        if !eski.isEmpty {
            let adlar = eski.map(\.baslik).joined(separator: ", ")
            var metin = "Mac'teki kuyruk \"\(adlar)\" diyor ama yazıcının kendisi sorun bildirmiyor. "
                + "Bu uyarı, sorun giderildikten sonra Mac'te kalmış; yazıcı aslında hazır."
            if durduHazir {
                metin += " Kuyruk da bu yüzden durdurulmuş; sürdürünce bekleyen işler basılır."
            }
            return ("Mac eski bir hatayı hatırlıyor", metin)
        }
        if durduHazir {
            return ("Kuyruk durdurulmuş, yazıcı hazır",
                    "Yazıcı sorun bildirmiyor ama Mac'teki kuyruk durdurulmuş. Bu genelde eski bir hatadan "
                    + "(ör. kağıt bitmesi) sonra ya da kuyruk elle durdurulunca olur; macOS kuyruğu kendiliğinden "
                    + "sürdürmez. Sürdürünce bekleyen işler basılır.")
        }
        return nil
    }

    // MARK: 3. Etkin iş

    private func etkinIsKarti(_ isi: YaziciIsi) -> some View {
        Kart(baslik: "Şu anki iş", simge: "printer.dotmatrix") {
            DurumRozeti(metin: isi.durum.ad, renk: Tema.renk(isi.durum), simge: Tema.simge(isi.durum))
        } icerik: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(isi.ad)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(verbatim: "#\(isi.id)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("İptal", role: .destructive) {
                    onay = .isIptal(id: isi.id, ad: isi.ad)
                }
                .buttonStyle(.bordered)
            }
            let sayfa = isi.basilanSayfa ?? 0
            if sayfa > 0 || isi.nedenMetni != nil {
                HStack(spacing: 14) {
                    if sayfa > 0 {
                        Label("\(sayfa) sayfa basıldı", systemImage: "doc")
                    }
                    if let neden = isi.nedenMetni {
                        Text(neden)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if isi.durum == .yazdiriliyor {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
    }

    // MARK: 4. Sabitleme

    private var sabitlemeKarti: some View {
        let s = model.sabitleme
        return Kart(baslik: "Sabit ayarlar", simge: s.etkin ? "lock.fill" : "lock.open",
                    vurgu: s.etkin ? Color.accentColor : nil) {
            if s.etkin {
                Text(model.sabitlemeOzeti)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if s.pencereKatmani || s.kesinMod {
                    HStack(spacing: 6) {
                        if s.pencereKatmani {
                            DurumRozeti(metin: "Yazdırma penceresi", renk: .accentColor, simge: "macwindow")
                        }
                        if s.kesinMod {
                            DurumRozeti(metin: "Kesin mod", renk: .accentColor, simge: "checkmark.shield.fill")
                        }
                    }
                }
                if s.kesinMod {
                    if model.gorevliCanli {
                        Label {
                            Text("Arka plan görevlisi çalışıyor").foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .font(.callout)
                    } else {
                        Label(model.takiliIsSayisi > 0
                              ? "Arka plan görevlisi çalışmıyor · \(model.takiliIsSayisi) iş bekliyor"
                              : (model.kuyruk?.isBeklemeVarsayilani == "indefinite"
                                 ? "Arka plan görevlisi çalışmıyor; yeni işler bekletilecek"
                                 : "Arka plan görevlisi çalışmıyor; işler denetlenmeden basılıyor"),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 8) {
                    Button("Düzenle") { model.secilenBolum = .baskiAyarlari }
                        .buttonStyle(.bordered)
                    Button("Kaldır", role: .destructive) {
                        onay = .sabitlemeKaldir(kesinMod: s.kesinMod)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.mesgul != nil)
                }
                .padding(.top, 2)
            } else {
                Text("Şu an sabit ayar yok: her iş, yazdırma penceresinde seçilen ayarlarla basılır. Bir ayarı sabitlerseniz bütün çıktılar onunla basılır.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let yerlesikler = Array(model.hazirAyarlar.filter { $0.yerlesik }.prefix(3))
                VStack(spacing: 0) {
                    ForEach(Array(yerlesikler.enumerated()), id: \.element.id) { sira, h in
                        if sira > 0 { Divider() }
                        HStack(spacing: 10) {
                            Image(systemName: h.simge)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.ad).font(.callout.weight(.medium))
                                Text(h.aciklama)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Button("Sabitle") { Task { await model.hazirAyariSabitle(h) } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        .padding(.vertical, 7)
                    }
                }
                .disabled(model.mesgul != nil)
                Button("Ayarları seç…") { model.secilenBolum = .baskiAyarlari }
                    .buttonStyle(.link)
            }
        }
    }

    // MARK: 5. Hızlı erişim

    private var hizliErisim: some View {
        GenelAkisDuzeni(bosluk: 8) {
            Button { model.secilenBolum = .hizliYazdir } label: {
                Label("Dosya yazdır", systemImage: "doc.on.doc")
            }
            Button { model.secilenBolum = .bakim } label: {
                Label("Püskürtme ucu denetimi", systemImage: "wrench.and.screwdriver")
            }
            if let k = model.kuyruk {
                if k.durdurulmus {
                    Button { Task { await model.kuyruguSurdur() } } label: {
                        Label("Kuyruğu sürdür", systemImage: "play.fill")
                    }
                    .disabled(model.mesgul != nil)
                } else {
                    Button { onay = .kuyrukDurdur } label: {
                        Label("Kuyruğu durdur", systemImage: "pause.fill")
                    }
                    .disabled(model.mesgul != nil)
                }
            }
            if model.cihaz?.webAdresi != nil || model.cihazAdresi != nil {
                Button { model.yaziciWebSayfasiniAc() } label: {
                    Label("Yazıcının web sayfası", systemImage: "globe")
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: 6. Mürekkep notu

    private var murekkepNotu: some View {
        Kart {
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    ForEach(Array(murekkepler.enumerated()), id: \.offset) { _, m in
                        Circle()
                            .fill(m.renk)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 0.5))
                            .help(m.ad)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mürekkep renkleri: " + murekkepler.map(\.ad).joined(separator: ", "))
                VStack(alignment: .leading, spacing: 3) {
                    Text("G3010 mürekkep seviyesini ölçmez; tankları gözle kontrol edin.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        Text("Temizlik ve diğer mürekkep işlemleri:")
                            .foregroundStyle(.secondary)
                        Button("Bakım") { model.secilenBolum = .bakim }
                            .buttonStyle(.link)
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var murekkepler: [GenelMurekkep] {
        if let c = model.cihaz, !c.murekkepRenkleri.isEmpty {
            var liste: [GenelMurekkep] = []
            for (i, hex) in c.murekkepRenkleri.enumerated() {
                guard let renk = GenelMurekkep.renk(hex) else { continue }
                let ad = i < c.murekkepAdlari.count ? c.murekkepAdlari[i] : ""
                liste.append(GenelMurekkep(ad: GenelMurekkep.turkceAd(ad), renk: renk))
            }
            if !liste.isEmpty { return Array(liste.prefix(4)) }
        }
        return GenelMurekkep.varsayilanlar
    }
}

// MARK: - Yardımcılar

private enum GenelBakisOnayi {
    case isIptal(id: Int, ad: String)
    case sabitlemeKaldir(kesinMod: Bool)
    case kuyrukDurdur

    var baslik: String {
        switch self {
        case .isIptal: return "İş iptal edilsin mi?"
        case .sabitlemeKaldir: return "Sabitleme kaldırılsın mı?"
        case .kuyrukDurdur: return "Kuyruk durdurulsun mu?"
        }
    }

    var mesaj: String {
        switch self {
        case .isIptal(let id, let ad):
            return "\"\(ad)\" (#\(id)) iptal edilecek. Yazıcıdaki sayfa yarım kalabilir."
        case .sabitlemeKaldir(let kesinMod):
            return "Yazıcının özgün ayarları geri yüklenir; sonraki işler yazdırma penceresinde seçilen ayarlarla basılır."
                + (kesinMod ? " Kesin mod da kapanır." : "")
        case .kuyrukDurdur:
            return "Yeni işler yazıcıya gönderilmez; siz sürdürene kadar Mac'te bekler."
        }
    }

    var dugme: String {
        switch self {
        case .isIptal: return "İşi iptal et"
        case .sabitlemeKaldir: return "Kaldır"
        case .kuyrukDurdur: return "Durdur"
        }
    }

    var yikici: Bool {
        if case .kuyrukDurdur = self { return false }
        return true
    }
}

private struct GenelEylemDugmesi: View {
    let eylem: HizliEylem
    let birincil: Bool
    let calistir: () -> Void

    var body: some View {
        if birincil {
            Button(action: calistir) { Label(eylem.ad, systemImage: eylem.simge) }
                .buttonStyle(.borderedProminent)
        } else {
            Button(action: calistir) { Label(eylem.ad, systemImage: eylem.simge) }
                .buttonStyle(.bordered)
        }
    }
}

private struct GenelBolmeBasligi: View {
    let baslik: String
    let altBaslik: String
    let simge: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(baslik, systemImage: simge)
                .font(.subheadline.weight(.semibold))
            Text(altBaslik)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }
}

private struct GenelDurumSatiri: View {
    let seviye: DurumSeviyesi
    let metin: String

    var body: some View {
        HStack(spacing: 6) {
            DurumSimgesi(seviye: seviye, boyut: 13)
            Text(metin)
                .font(.body.weight(.semibold))
                .foregroundStyle(seviye >= .uyari ? Tema.renk(seviye) : Color.primary)
        }
    }
}

private struct GenelNedenSatiri: View {
    let neden: DurumNedeni

    var body: some View {
        Label {
            Text(neden.baslik).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: simge)
        }
        .font(.callout)
        .foregroundStyle(Tema.renk(neden.onem))
        .help(neden.ayrinti ?? neden.ham)
    }

    private var simge: String {
        switch neden.onem {
        case .hata: return "xmark.circle.fill"
        case .uyari: return "exclamationmark.triangle.fill"
        case .bilgi: return "info.circle"
        }
    }
}

private struct GenelSorunYok: View {
    var body: some View {
        Label("Sorun bildirmiyor", systemImage: "checkmark")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

private struct GenelMurekkep {
    let ad: String
    let renk: Color

    static let varsayilanlar: [GenelMurekkep] = [
        GenelMurekkep(ad: "Siyah", renk: Color(white: 0.12)),
        GenelMurekkep(ad: "Camgöbeği", renk: Color(red: 0.0, green: 0.68, blue: 0.94)),
        GenelMurekkep(ad: "Macenta", renk: Color(red: 0.93, green: 0.0, blue: 0.55)),
        GenelMurekkep(ad: "Sarı", renk: Color(red: 1.0, green: 0.87, blue: 0.0)),
    ]

    /// "#RRGGBB" (ya da "#RRGGBB#…") → Color.
    static func renk(_ hex: String) -> Color? {
        let s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        let alti = s.dropFirst().prefix(6)
        guard alti.count == 6, let v = UInt32(alti, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    static func turkceAd(_ ad: String) -> String {
        let k = ad.lowercased()
        if k.contains("black") || k.hasSuffix("bk") { return "Siyah" }
        if k.contains("cyan") || k == "c" { return "Camgöbeği" }
        if k.contains("magenta") || k == "m" { return "Macenta" }
        if k.contains("yellow") || k == "y" { return "Sarı" }
        return ad.isEmpty ? "Mürekkep" : ad
    }
}

/// Düğmeleri satıra dizer, sığmayanı alt satıra geçirir.
private struct GenelAkisDuzeni: Layout {
    var bosluk: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sinir = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, satir: CGFloat = 0, enGenis: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x > 0, x + b.width > sinir {
                y += satir + bosluk
                x = 0
                satir = 0
            }
            enGenis = max(enGenis, x + b.width)
            x += b.width + bosluk
            satir = max(satir, b.height)
        }
        return CGSize(width: enGenis, height: y + satir)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, satir: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x > 0, x + b.width > bounds.width {
                y += satir + bosluk
                x = 0
                satir = 0
            }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: .unspecified)
            x += b.width + bosluk
            satir = max(satir, b.height)
        }
    }
}
