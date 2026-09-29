import SwiftUI

/// Baskı Ayarları: ayarları düzenle, kilitle ve bu Mac'teki tüm baskılar için sabitle.
struct BaskiAyarlariGorunumu: View {
    @Environment(UygulamaModeli.self) private var model
    @State private var kaldirOnayi = false
    @State private var kaydetAcik = false

    var body: some View {
        Sayfa(baslik: "Baskı Ayarları",
              altBaslik: "Kilitlediğiniz ayarlar bu Mac'ten yapılan tüm baskılarda geçerli olur.",
              simge: Bolum.baskiAyarlari.simge) {
            durumSeridi
            kaliteKarti
            renkKarti
            HStack(alignment: .top, spacing: Tema.bosluk) {
                kagitTuruKarti
                kagitBoyutuKarti
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: Tema.bosluk) {
                parlaklikKarti
                yariTonKarti
            }
            .fixedSize(horizontal: false, vertical: true)
            yontemKarti
            eylemCubugu
            ayrintilar
        }
        .confirmationDialog("Sabitleme kaldırılsın mı?", isPresented: $kaldirOnayi, titleVisibility: .visible) {
            Button("Sabitlemeyi kaldır", role: .destructive) {
                Task { await model.sabitlemeyiKaldir() }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Tüm ayarlar sabitlemeden önceki hâline döner.")
        }
        .sheet(isPresented: $kaydetAcik) {
            AyarKaydetPenceresi(ozet: model.duzenlenen.sadece(model.kilitli).ozet(katalog: model.katalog)) { ad, simge, aciklama in
                model.hazirAyarKaydet(ad: ad, simge: simge, aciklama: aciklama,
                                      ayarlar: model.duzenlenen.sadece(model.kilitli))
            }
        }
    }

    // MARK: - Bağlamalar

    /// Kilit düğmesi için bağlama.
    private func kilitBaglami(_ anahtar: AyarAnahtari) -> Binding<Bool> {
        let m = model
        return Binding(
            get: { m.kilitli.contains(anahtar) },
            set: { acik in
                if acik { m.kilitli.insert(anahtar) } else { m.kilitli.remove(anahtar) }
            })
    }

    /// Bir ayarın değeri; değişince o ayar otomatik kilitlenir.
    private func ayarBaglami<T>(_ anahtar: AyarAnahtari, _ yol: WritableKeyPath<BaskiAyarSeti, T?>,
                                varsayilan: T) -> Binding<T> {
        let m = model
        return Binding(
            get: { m.duzenlenen[keyPath: yol] ?? varsayilan },
            set: { yeni in
                m.duzenlenen[keyPath: yol] = yeni
                withAnimation(.snappy) { _ = m.kilitli.insert(anahtar) }
            })
    }

    private func kilitAksesuari(_ anahtar: AyarAnahtari) -> some View {
        KilitDugmesi(kilitli: kilitBaglami(anahtar))
    }

    // MARK: - 1. Durum şeridi

    @ViewBuilder private var durumSeridi: some View {
        Group {
            if model.sabitleme.etkin {
                Kart(vurgu: .accentColor) {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill").foregroundStyle(.tint)
                        Text("Şu an sabit: \(Text(model.sabitlemeOzeti).fontWeight(.semibold))")
                            .font(.callout)
                            .lineLimit(2)
                        if model.sabitleme.kesinMod {
                            DurumRozeti(metin: "Kesin mod", renk: .accentColor, simge: "checkmark.shield.fill")
                        }
                        Spacer(minLength: 8)
                        Button("Kaldır") { kaldirOnayi = true }
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "lock.open")
                    Text("Sabitleme kapalı — her iş, yazdırma penceresinde seçilen ayarlarla basılır.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: model.sabitleme.etkin)
    }

    // MARK: - 2. Ayar kartları

    private var seciliKalite: Kalite { model.duzenlenen.kalite ?? .standart }

    /// Kağıt türü kilitli ve düz kağıt değilse kalite uygulanmaz (Canon kağıda göre seçer).
    private var fotoKagidi: Bool {
        guard model.kilitli.contains(.ortam), let ortam = model.duzenlenen.ortam else { return false }
        return ortam != "0"
    }

    private var kaliteKarti: some View {
        Kart(baslik: AyarAnahtari.kalite.ad, simge: AyarAnahtari.kalite.simge,
             aksesuar: { kilitAksesuari(.kalite) }) {
            HStack(spacing: 10) {
                ForEach(Kalite.allCases) { k in
                    kaliteKarosu(k)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .opacity(fotoKagidi ? 0.45 : 1)
            .animation(.snappy, value: model.duzenlenen.kalite)

            VStack(alignment: .leading, spacing: 3) {
                Text(seciliKalite.aciklama)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Canon penceresindeki karşılığı: \(seciliKalite.canonKarsiligi)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if fotoKagidi {
                IpucuKutusu(metin: "Fotoğraf kağıdında kaliteyi Canon kağıda göre seçer; kalite sabitlenmez.",
                            simge: "photo")
            }
        }
        .animation(.snappy, value: fotoKagidi)
    }

    private func kaliteKarosu(_ k: Kalite) -> some View {
        let secili = model.duzenlenen.kalite == k
        let sekil = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let baglam = ayarBaglami(.kalite, \.kalite, varsayilan: Kalite.standart)
        return Button {
            baglam.wrappedValue = k
        } label: {
            VStack(spacing: 7) {
                Image(systemName: k.simge)
                    .font(.title2)
                    .foregroundStyle(secili ? Color.accentColor : .secondary)
                    .frame(height: 26)
                Text(k.ad)
                    .font(.callout.weight(secili ? .semibold : .regular))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                MurekkepCubugu(oran: k.murekkepOrani)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(sekil.fill(secili ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03)))
            .overlay(sekil.strokeBorder(secili ? Color.accentColor : Color.primary.opacity(0.10),
                                        lineWidth: secili ? 2 : 1))
            .contentShape(sekil)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(k.aciklama)
        .accessibilityAddTraits(secili ? .isSelected : [])
    }

    private var renkKarti: some View {
        Kart(baslik: AyarAnahtari.griTon.ad, simge: AyarAnahtari.griTon.simge,
             aksesuar: { kilitAksesuari(.griTon) }) {
            Picker("Renk", selection: ayarBaglami(.griTon, \.griTon, varsayilan: false)) {
                Text("Renkli").tag(false)
                Text("Siyah-beyaz").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text("Siyah-beyaz renkli mürekkep harcamaz (Canon'un gri tonlamalı yazdırması).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Kataloğun seçimleri; şu anki değer listede yoksa sona eklenir (Picker boş kalmasın).
    private func secimler(_ anahtar: String, varsayilan: [PPDSecimi], suan: String?,
                          ad: (String) -> String, atla: (PPDSecimi) -> Bool = { _ in false }) -> [PPDSecimi] {
        var liste = (model.katalog?[anahtar]?.secimler ?? varsayilan).filter { !atla($0) }
        if liste.isEmpty { liste = varsayilan }
        if let suan, !liste.contains(where: { $0.kod == suan }) {
            liste.append(PPDSecimi(kod: suan, ad: ad(suan), ingilizceAd: suan))
        }
        return liste
    }

    private var kagitTuruKarti: some View {
        let k = model.katalog
        let liste = secimler("CNIJMediaType",
                             varsayilan: [PPDSecimi(kod: "0", ad: "Düz Kağıt", ingilizceAd: "Plain Paper")],
                             suan: model.duzenlenen.ortam,
                             ad: { BaskiAyarSeti.ortamAdi($0, katalog: k) })
        return Kart(baslik: AyarAnahtari.ortam.ad, simge: AyarAnahtari.ortam.simge,
                    aksesuar: { kilitAksesuari(.ortam) }) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Kağıt türü", selection: ayarBaglami(.ortam, \.ortam, varsayilan: "0")) {
                    ForEach(liste) { s in
                        Text(s.ad).tag(s.kod)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 340, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var kagitBoyutuKarti: some View {
        let k = model.katalog
        let liste = secimler("PageSize",
                             varsayilan: [PPDSecimi(kod: "A4", ad: "A4", ingilizceAd: "A4")],
                             suan: model.duzenlenen.kagit,
                             ad: { BaskiAyarSeti.kagitAdi($0, katalog: k) },
                             atla: { $0.kod.hasPrefix("Custom") })
        return Kart(baslik: AyarAnahtari.kagit.ad, simge: AyarAnahtari.kagit.simge,
                    aksesuar: { kilitAksesuari(.kagit) }) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Kağıt boyutu", selection: ayarBaglami(.kagit, \.kagit, varsayilan: "A4")) {
                    ForEach(liste) { s in
                        Text(s.ad).tag(s.kod)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 340, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var parlaklikKarti: some View {
        Kart(baslik: AyarAnahtari.parlaklik.ad, simge: AyarAnahtari.parlaklik.simge,
             aksesuar: { kilitAksesuari(.parlaklik) }) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Parlaklık", selection: ayarBaglami(.parlaklik, \.parlaklik, varsayilan: Parlaklik.normal)) {
                    ForEach(Parlaklik.allCases) { p in
                        Text(p.ad).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var yariTonKarti: some View {
        Kart(baslik: AyarAnahtari.yariTon.ad, simge: AyarAnahtari.yariTon.simge,
             aksesuar: { kilitAksesuari(.yariTon) }) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Yarı ton", selection: ayarBaglami(.yariTon, \.yariTon, varsayilan: YariTon.dagilma)) {
                    ForEach(YariTon.allCases) { y in
                        Text(y.ad).tag(y)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text((model.duzenlenen.yariTon ?? .dagilma).aciklama)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - 3. Nasıl sabitlensin?

    private var yontemKarti: some View {
        Kart(baslik: "Nasıl sabitlensin?", simge: "square.3.layers.3d") {
            yontemSatiri(simge: "printer", baslik: "Yazıcı varsayılanı",
                         aciklama: "Pencereye sormadan basan programlar bunu kullanır. Chrome kaliteyi, kağıt türünü, parlaklığı ve yarı tonu buradan alır; renk, çözünürlük ve kağıt boyutunu ise kendi penceresindeki seçimle gönderir.") {
                Label("Her zaman açık", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            yontemSatiri(simge: "macwindow", baslik: "Yazdırma penceresini de ayarla",
                         aciklama: "Safari, Önizleme gibi uygulamalarda açılan macOS yazdırma penceresi son kullanılan ayarları hatırlar; bu seçenek onları sabit ayarlarla doldurur.") {
                Toggle("Yazdırma penceresini de ayarla", isOn: Bindable(model).pencereKatmaniSecili)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider()

            yontemSatiri(simge: "checkmark.shield", baslik: "Kesin mod — her işi denetle",
                         aciklama: "Her baskı bir an bekletilir, arka plan görevlisi sabit ayarları yazıp gönderir. Pencerede başka ayar seçseniz bile sabit ayar geçerli olur. Kağıt türü kilitli değilse fotoğraf kağıdındaki işlerde kaliteye dokunulmaz; kilitliyse her iş o kağıt türü ve kaliteyle basılır.") {
                Toggle("Kesin mod — her işi denetle", isOn: Bindable(model).kesinModSecili)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if model.kesinModSecili && GorevliYoneticisi.korumaliKlasorde {
                IpucuKutusu(metin: "Uygulama Masaüstü'nden çalışıyor. Kesin mod için /Applications'taki kopyayı açın.",
                            simge: "exclamationmark.triangle.fill", renk: .orange)
            }

            if model.sabitleme.aktifKesinMod {
                gorevliDurumu
            }

            Divider()

            // Chrome'dan basınca ne olacağı (düzenleyicideki seçimlere göre).
            yontemSatiri(simge: "globe", baslik: "Chrome'dan basınca",
                         aciklama: ChromeKoprusu.chromeNotu(chromeOnizleme)) {
                Button("Chrome eklentisi…") { model.secilenBolum = .tercihler }
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
        }
        .animation(.snappy, value: model.kesinModSecili)
    }

    /// Düzenleyicideki seçimlerle sabitlenseydi Chrome notu ne derdi.
    private var chromeOnizleme: SabitlemeYapilandirmasi {
        var c = SabitlemeYapilandirmasi()
        c.etkin = !model.kilitli.isEmpty
        c.ayarlar = model.duzenlenen.sadece(model.kilitli)
        c.kesinMod = model.kesinModSecili
        return c
    }

    private func yontemSatiri<Denetim: View>(simge: String, baslik: String, aciklama: String,
                                              @ViewBuilder denetim: () -> Denetim) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: simge)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(baslik).font(.body.weight(.medium))
                Text(aciklama)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            denetim()
        }
    }

    private var gorevliDurumu: some View {
        let canli = model.gorevliCanli
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(canli ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(canli ? "Arka plan görevlisi çalışıyor" : "Arka plan görevlisi çalışmıyor")
                if let g = model.gorevli, canli {
                    Text("· \(g.islenenSayisi) iş işlendi").foregroundStyle(.secondary)
                }
                if !canli && model.takiliIsSayisi > 0 {
                    Text("· \(model.takiliIsSayisi) iş gönderilmeyi bekliyor").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            if let son = model.gorevli?.sonIslemler.last {
                Text("Son işlem: \(son)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, 32)
    }

    // MARK: - 4. Eylem çubuğu

    private var sabitlenecekOzet: String {
        model.duzenlenen.sadece(model.kilitli).ozet(katalog: model.katalog)
    }

    private var eylemCubugu: some View {
        let etkin = model.sabitleme.etkin
        let sabitlenebilir = !model.kilitli.isEmpty && model.duzenleyiciDegisti && model.mesgul == nil
        return Kart {
            HStack(spacing: 10) {
                Button {
                    Task { await model.duzenleyicidekileriSabitle() }
                } label: {
                    Label(etkin ? "Güncelle" : "Sabitle", systemImage: "lock.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!sabitlenebilir)

                Button("Geri al") { model.duzenleyiciyiSifirla() }
                    .buttonStyle(.bordered)

                Button("Hazır ayar olarak kaydet…") { kaydetAcik = true }
                    .buttonStyle(.bordered)
                    .disabled(model.kilitli.isEmpty)

                Spacer(minLength: 8)

                if etkin {
                    Button("Sabitlemeyi kaldır", role: .destructive) { kaldirOnayi = true }
                        .buttonStyle(.bordered)
                        .disabled(model.mesgul != nil)
                }
            }
            Group {
                if model.kilitli.isEmpty {
                    Text("Sabitlemek için en az bir ayarı kilitleyin.")
                } else if etkin && !model.duzenleyiciDegisti {
                    Text("Sabit ayarlar güncel.")
                } else {
                    Text("Sabitlenecek: \(sabitlenecekOzet)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - 5. Ayrıntılar

    private var ayrintilar: some View {
        let degerler = model.duzenlenen.sadece(model.kilitli)
            .ppdSecenekleri(katalog: model.katalog)
            .sorted { $0.key < $1.key }
        return Kart {
            DisclosureGroup("Ayrıntılar") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Yazıcı varsayılanına yazılacak değerler")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if degerler.isEmpty {
                        Text("Yazılacak değer yok.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(degerler, id: \.key) { d in
                                Text(verbatim: "\(d.key)=\(d.value)")
                            }
                        }
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    }
                    Divider()
                    Group {
                        if let y = model.yedek {
                            if y.aktif {
                                Text("Özgün ayarlar \(Bicim.tarih(y.alinma)) yedeklendi; sabitleme kaldırılınca bunlara dönülür.")
                            } else {
                                Text("Son yedek: \(Bicim.tarih(y.alinma)) (geri yüklendi).")
                            }
                        } else {
                            Text("Henüz yedek yok. İlk sabitlemede yazıcının özgün ayarları yedeklenir.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Hazır ayar olarak kaydet

private struct AyarKaydetPenceresi: View {
    let ozet: String
    let kaydet: (_ ad: String, _ simge: String, _ aciklama: String) -> Void

    @Environment(\.dismiss) private var kapat
    @State private var ad = ""
    @State private var simge = "star"
    @State private var aciklama = ""

    private var temizAd: String { ad.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hazır ayar olarak kaydet").font(.title3.weight(.semibold))
                Text("Kilitli ayarlar kaydedilir: \(ozet)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                TextField("Ad", text: $ad, prompt: Text("Ör. Deneme sınavı"))
                LabeledContent("Simge") {
                    AyarSimgeSecici(secili: $simge)
                }
                TextField("Açıklama", text: $aciklama, prompt: Text("İsteğe bağlı"))
            }

            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { kapat() }
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet") {
                    kaydet(temizAd, simge, aciklama.trimmingCharacters(in: .whitespacesAndNewlines))
                    kapat()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(temizAd.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct AyarSimgeSecici: View {
    @Binding var secili: String

    private static let simgeler = ["doc.plaintext", "paintpalette", "hare", "doc.text",
                                   "photo", "star", "graduationcap", "book"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.simgeler, id: \.self) { s in
                let secildi = secili == s
                let sekil = RoundedRectangle(cornerRadius: 7, style: .continuous)
                Button {
                    secili = s
                } label: {
                    Image(systemName: s)
                        .foregroundStyle(secildi ? Color.accentColor : .primary)
                        .frame(width: 30, height: 30)
                        .background(sekil.fill(secildi ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
                        .overlay(sekil.strokeBorder(secildi ? Color.accentColor : .clear, lineWidth: 1.5))
                        .contentShape(sekil)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(secildi ? .isSelected : [])
            }
        }
    }
}
