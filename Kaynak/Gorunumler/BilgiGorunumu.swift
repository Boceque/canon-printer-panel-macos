import AppKit
import SwiftUI

/// "Yazıcı Bilgisi": donanım, bağlantı, sürücü, mürekkep ve son olaylar.
struct BilgiGorunumu: View {
    @Environment(UygulamaModeli.self) private var model

    /// İçerik alanı iki sütuna yetecek kadar geniş mi?
    @State private var genis = true

    var body: some View {
        Sayfa(baslik: "Yazıcı Bilgisi", altBaslik: "Donanım, bağlantı ve sürücü", simge: Bolum.bilgi.simge) {
            VStack(alignment: .leading, spacing: Tema.bosluk) {
                kahraman
                ikili { donanimKarti } sag: { baglantiKarti }
                ikili { surucuKarti } sag: { murekkepKarti }
                baglantilarKarti
                olaylarKarti
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: Bool.self) { $0.size.width >= 720 } action: { genis = $0 }
        }
    }

    /// Geniş alanda iki kartı yan yana (eşit yükseklikte), dar alanda alt alta dizer.
    private func ikili<Sol: View, Sag: View>(@ViewBuilder _ sol: () -> Sol, @ViewBuilder sag: () -> Sag) -> some View {
        let duzen = genis
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Tema.bosluk))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Tema.bosluk))
        return duzen {
            sol()
            sag()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Kahraman

    private var kahraman: some View {
        let cihaz = model.cihaz
        let ad = (cihaz?.model).flatMap { $0.isEmpty ? nil : $0 } ?? "Canon G3010 series"
        return Kart {
            HStack(spacing: 20) {
                YaziciResmi(boyut: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text(ad)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    if let alt = cihaz?.ad, !alt.isEmpty {
                        Text(alt)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        if cihaz?.tanitmaDestekli == true {
                            Button {
                                Task { await model.yaziciyiTanit() }
                            } label: {
                                Label("Yazıcıyı bul", systemImage: "lightbulb")
                            }
                            .help("Yazıcının ışıklarını yakıp söndürür")
                        }
                        Button {
                            model.yaziciWebSayfasiniAc()
                        } label: {
                            Label("Web sayfası", systemImage: "safari")
                        }
                        .disabled(cihaz?.webAdresi == nil && model.cihazAdresi == nil)
                        if let sayfa = cihaz?.murekkepSayfasi {
                            Button {
                                NSWorkspace.shared.open(sayfa)
                            } label: {
                                Label("Mürekkep sayfası", systemImage: "drop")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Donanım

    private var donanimKarti: some View {
        Kart(baslik: "Donanım", simge: "cpu") {
            VStack(alignment: .leading, spacing: 8) {
                if let cihaz = model.cihaz {
                    let alanlar = cihaz.aygitKimligiAlanlari
                    BilgiSatiri(etiket: "Model", deger: cihaz.model)
                    BilgiSatiri(etiket: "Yazılım sürümü", deger: cihaz.firmware)
                    if let mdl = alanlar["MDL"] {
                        BilgiSatiri(etiket: "Kimlikteki model (MDL)", deger: mdl)
                    }
                    if let ver = alanlar["VER"] {
                        BilgiSatiri(etiket: "Kimlikteki sürüm (VER)", deger: ver)
                    }
                    if let cmd = alanlar["CMD"] {
                        BilgiSatiri(etiket: "Komut dilleri (CMD)", deger: cmd.replacingOccurrences(of: ",", with: ", "))
                    }
                    BilgiSatiri(etiket: "UUID", deger: cihaz.uuid, kopyalanabilir: true)
                    BilgiSatiri(etiket: "Hız", deger: hizMetni(cihaz))
                } else {
                    Label(model.cihazHatasi ?? "Yazıcının kendisinden bilgi bekleniyor…", systemImage: "wifi.slash")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func hizMetni(_ cihaz: CihazDurumu) -> String {
        var parcalar: [String] = []
        if let s = cihaz.dakikadaSayfa { parcalar.append("\(s) sayfa/dk siyah") }
        if let r = cihaz.dakikadaRenkliSayfa { parcalar.append("\(r) sayfa/dk renkli") }
        return parcalar.joined(separator: " · ")
    }

    // MARK: Bağlantı

    private var baglantiKarti: some View {
        Kart(baslik: "Bağlantı", simge: "network") {
            if model.kuyruklar.count > 1 {
                Picker("Yazıcı", selection: Binding(get: { model.kuyrukAdi }, set: { model.kuyrukSec($0) })) {
                    ForEach(model.kuyruklar, id: \.ad) { k in
                        Text(k.bilgi.isEmpty ? k.ad : k.bilgi).tag(k.ad)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        } icerik: {
            VStack(alignment: .leading, spacing: 8) {
                BilgiSatiri(etiket: "Ağ adresi", deger: model.cihazAdresi.map { "\($0.host):\($0.port)\($0.yol)" } ?? "",
                            kopyalanabilir: true)
                if let kuyruk = model.kuyruk {
                    if let bonjour = CihazBulucu.bonjourAdi(kuyruk.aygitAdresi)?.ad {
                        BilgiSatiri(etiket: "Bonjour adı", deger: bonjour)
                    }
                    BilgiSatiri(etiket: "Mac'teki kuyruk adı", deger: model.kuyrukAdi)
                    KucukBilgiSatiri(etiket: "Aygıt adresi", deger: kuyruk.aygitAdresi)
                    BilgiSatiri(etiket: "Hata olunca", deger: hataPolitikasiAdi(kuyruk.hataPolitikasi))
                } else {
                    BilgiSatiri(etiket: "Mac'teki kuyruk adı", deger: model.kuyrukAdi)
                    if let hata = model.kuyrukHatasi {
                        Text(hata)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func hataPolitikasiAdi(_ politika: String?) -> String {
        guard let politika else { return "" }
        switch politika {
        case "stop-printer": return "Kuyruğu durdur"
        case "retry-current-job": return "İşi yeniden dene"
        case "retry-job": return "Daha sonra yeniden dene"
        case "abort-job": return "İşi iptal et"
        default: return politika
        }
    }

    // MARK: Sürücü

    private var surucuKarti: some View {
        Kart(baslik: "Sürücü", simge: "shippingbox") {
            VStack(alignment: .leading, spacing: 8) {
                if let katalog = model.katalog {
                    BilgiSatiri(etiket: "Sürücü", deger: katalog.model)
                    BilgiSatiri(etiket: "PPD sürümü", deger: katalog.surum)
                    BilgiSatiri(etiket: "PPD yolu", deger: katalog.yol, kopyalanabilir: true)
                } else {
                    Text("Sürücü bilgisi (PPD) okunamadı.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                BilgiSatiri(etiket: "Canon metinleri",
                            deger: CanonMetinleri.shared.yuklendi ? "Türkçe durum metinleri yüklü"
                                                                  : "Türkçe durum metinleri bulunamadı")
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Mürekkep

    private var murekkepKarti: some View {
        Kart(baslik: "Mürekkep", simge: "drop") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    ForEach(murekkepler, id: \.ad) { m in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(m.renk)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                                .frame(width: 16, height: 16)
                            Text(m.ad).font(.callout)
                        }
                    }
                }
                Text("G3010 kalan mürekkebi ölçmez; tanklardaki çizgilere bakın. Doldurduktan sonra Bakım › Mürekkep sayacını sıfırla.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// Yazıcının bildirdiği mürekkepler; bildirmiyorsa G3010'un dört tankı.
    private var murekkepler: [Murekkep] {
        let adlar = model.cihaz?.murekkepAdlari ?? []
        let renkler = model.cihaz?.murekkepRenkleri ?? []
        guard !adlar.isEmpty else {
            return [Murekkep(ad: "Siyah", renk: .black), Murekkep(ad: "Camgöbeği", renk: .cyan),
                    Murekkep(ad: "Macenta", renk: Color(red: 0.9, green: 0, blue: 0.55)),
                    Murekkep(ad: "Sarı", renk: .yellow)]
        }
        var sonuc: [Murekkep] = []
        for (i, ham) in adlar.enumerated() {
            let ad = Murekkep.turkceAd(ham)
            guard !sonuc.contains(where: { $0.ad == ad }) else { continue }
            let renk = (i < renkler.count ? Murekkep.renk(hex: renkler[i]) : nil) ?? Murekkep.varsayilanRenk(ham)
            sonuc.append(Murekkep(ad: ad, renk: renk))
        }
        return sonuc
    }

    // MARK: Bağlantılar

    private var baglantilarKarti: some View {
        Kart(baslik: "Bağlantılar", simge: "arrow.up.forward.app") {
            HStack(spacing: 8) {
                Button {
                    model.canonYardimciPrograminiAc()
                } label: {
                    Label("Canon IJ Printer Utility", systemImage: "wrench.and.screwdriver")
                }
                Button {
                    model.sistemYaziciAyarlariniAc()
                } label: {
                    Label("macOS Yazıcı Ayarları", systemImage: "gearshape")
                }
                Button {
                    model.gunlukDosyasiniAc()
                } label: {
                    Label("Günlük dosyası", systemImage: "doc.text")
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Son olaylar

    private var olaylarKarti: some View {
        Kart(baslik: "Son olaylar", simge: "list.bullet.rectangle.portrait") {
            Button("Yenile") { model.gunluguYukle() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        } icerik: {
            let satirlar = Array(model.gunlukSatirlari.prefix(60))
            if satirlar.isEmpty {
                Text("Henüz kayıt yok")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(satirlar.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 220)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .onAppear { model.gunluguYukle() }
    }
}

// MARK: - Yardımcılar

/// Tek bir mürekkep: Türkçe ad ve renk.
private struct Murekkep {
    let ad: String
    let renk: Color

    static func turkceAd(_ ham: String) -> String {
        switch ham.trimmingCharacters(in: .whitespaces).uppercased() {
        case "BK", "PGBK", "BLACK": return "Siyah"
        case "C", "CYAN": return "Camgöbeği"
        case "M", "MAGENTA": return "Macenta"
        case "Y", "YELLOW": return "Sarı"
        case "COLOR", "TRI-COLOR": return "Renkli"
        default: return ham
        }
    }

    static func varsayilanRenk(_ ham: String) -> Color {
        switch turkceAd(ham) {
        case "Siyah": return .black
        case "Camgöbeği": return .cyan
        case "Macenta": return Color(red: 0.9, green: 0, blue: 0.55)
        case "Sarı": return .yellow
        default: return .secondary
        }
    }

    /// "#RRGGBB" → renk (IPP marker-colors). Birden çok renk verilmişse ilki alınır.
    static func renk(hex: String) -> Color? {
        let parcalar = hex.split(separator: "#")
        guard let ilk = parcalar.first, ilk.count == 6, let deger = UInt32(ilk, radix: 16) else { return nil }
        return Color(red: Double((deger >> 16) & 0xFF) / 255,
                     green: Double((deger >> 8) & 0xFF) / 255,
                     blue: Double(deger & 0xFF) / 255)
    }
}

/// BilgiSatiri'nın uzun değerler için küçük yazılı hâli (aygıt adresi gibi).
private struct KucukBilgiSatiri: View {
    let etiket: String
    let deger: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(etiket)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(deger.isEmpty ? "—" : deger)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
            if !deger.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(deger, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .font(.callout)
                .help("Kopyala")
            }
        }
    }
}
