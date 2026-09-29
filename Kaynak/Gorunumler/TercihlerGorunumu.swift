import AppKit
import SwiftUI

struct TercihlerGorunumu: View {
    @Environment(UygulamaModeli.self) private var model

    /// Hata politikası değiştirilirken gösterilecek değer (CUPS'tan yenisi gelene dek).
    @State private var bekleyenPolitika: Bool?
    @State private var gorevliBaslatiliyor = false
    /// Eklenti dosyaları güncellendi ama Chrome eklentiyi henüz yeniden yüklemedi.
    @State private var eklentiYenidenYuklenmeli = false

    var body: some View {
        @Bindable var model = model
        Sayfa(baslik: "Tercihler", altBaslik: nil, simge: Bolum.tercihler.simge) {
            // 1. Uygulama
            Kart(baslik: "Uygulama", simge: "macwindow") {
                AnahtarSatiri(baslik: "Girişte başlat",
                              acik: Binding(get: { model.girisBaslat }, set: { model.girisBaslatAyarla($0) }))
                Divider()
                AnahtarSatiri(baslik: "Menü çubuğunda göster", acik: $model.menuCubugunda)
                Divider()
                AnahtarSatiri(baslik: "Pencere kapanınca menü çubuğunda çalışmaya devam et", acik: $model.arkaPlandaCalis)
                    .disabled(!model.menuCubugunda)
                Divider()
                AnahtarSatiri(baslik: "Sorun olunca bildirim gönder",
                              aciklama: "Uygulama arka plandayken yazıcı hata verirse (kağıt bitti vb.) macOS bildirimi gelir.",
                              acik: $model.bildirimlerAcik)
            }

            // 2. Yazıcı davranışı
            Kart(baslik: "Yazıcı davranışı", simge: "printer") {
                AnahtarSatiri(baslik: "Hata olunca Mac'teki kuyruğu durdur",
                              aciklama: "macOS varsayılanı: kağıt bitince ya da yazıcıya ulaşılamayınca kuyruk durdurulur ve elle sürdürmek gerekir. Kapatırsanız iş yeniden denenir; kağıt koyunca baskı kendiliğinden devam eder.",
                              acik: Binding(get: { bekleyenPolitika ?? model.kagitBitinceDurdur },
                                            set: { yeni in
                                                bekleyenPolitika = yeni
                                                Task {
                                                    await model.hataPolitikasiAyarla(kagitBitinceDurdur: yeni)
                                                    bekleyenPolitika = nil
                                                }
                                            }))
                    .disabled(model.kuyruk == nil || bekleyenPolitika != nil)
                Text(politikaMetni)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            // 3. Kesin mod görevlisi
            gorevliKarti

            // Chrome eklentisi
            chromeKarti

            // 4. Veriler
            Kart(baslik: "Veriler", simge: "folder") {
                Text("Sabitleme ayarları, yedek ve günlük bu klasörde tutulur.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([Depo.klasor])
                    } label: {
                        Label("Ayar klasörünü göster", systemImage: "folder")
                    }
                    Button {
                        model.gunlukDosyasiniAc()
                    } label: {
                        Label("Günlüğü aç", systemImage: "doc.text")
                    }
                }
                .buttonStyle(.bordered)
            }

            // 5. Hakkında
            Kart(baslik: "Hakkında", simge: "info.circle") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Yazıcı Paneli").font(.body.weight(.semibold))
                        Text("Sürüm \(surum)").font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Canon G3010 için; Canon IJ sürücüsü ve CUPS ile çalışır.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Kesin mod görevlisi

    private var chromeKarti: some View {
        Kart(baslik: "Chrome eklentisi", simge: "globe") {
            Text("Chrome'un yazdırma penceresine “\(ChromeKoprusu.yaziciAdi(model.sabitleme))” hedefini ekler; bu hedeften yapılan baskıda sabit ayarlar her zaman geçerlidir. Sabitlenen ayar pencerede tek seçenek olur: kağıt boyutu, kalite, kağıt türü ve parlaklık “(sabit)” diye görünür; renk sabitse Chrome renk satırını hiç göstermez. Sabitlenmeyen ayarlar pencereden seçilebilir. Araç çubuğundaki düğmesi yazıcı durumunu ve hazır ayarları gösterir.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                chromeDurumSatiri(model.chromeKopruKurulu, "Köprü kurulu", "Köprü kurulu değil")
                chromeDurumSatiri(model.chromeEklentiYuklu, "Eklenti Chrome'da yüklü", "Eklenti Chrome'da yok ya da kapalı")
            }
            if let uyari = chromeKonumUyarisi {
                IpucuKutusu(metin: uyari, simge: "exclamationmark.triangle.fill", renk: .orange)
            }
            if !model.chromeEklentiYuklu {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bir kereye mahsus kurulum:").font(.callout.weight(.semibold))
                    Text("1. Chrome'da adres çubuğuna chrome://extensions yazın.")
                    Text("2. Sağ üstten “Geliştirici modu”nu açın.")
                    Text("3. “Paketlenmemiş öğe yükle”ye tıklayın, açılan pencerede ⇧⌘G'ye basıp aşağıdaki yolu yapıştırın, Return'e basın ve Seç'e tıklayın.")
                    Text("4. Araç çubuğundaki yapboz simgesine tıklayıp Yazıcı Paneli'nin yanındaki iğneye basın; düğme araç çubuğuna sabitlenir.")
                    Text("Eklenti yüklü ama kapalıysa chrome://extensions'ta anahtarını açmanız yeterli.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            } else if eklentiYenidenYuklenmeli {
                IpucuKutusu(baslik: "Eklenti dosyaları güncellendi — Chrome'da yeniden yükleyin",
                            metin: "chrome://extensions'ta Yazıcı Paneli'nin ↻ düğmesine basın. Chrome eklentinin arka planını kendiliğinden yenilemez; yenilenmezse eski sürüm çalışmaya devam eder.",
                            simge: "arrow.clockwise.circle.fill", renk: .orange)
            } else {
                Text("Uygulama güncellenince chrome://extensions'ta Yazıcı Paneli'nin ↻ düğmesine basın; Chrome eklentinin arka planını kendiliğinden yenilemez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(ChromeKoprusu.eklentiKlasoru.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ChromeKoprusu.eklentiKlasoru.path, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Yolu kopyala")
            }
            HStack(spacing: 8) {
                Button("Klasörü göster") { model.chromeEklentiKlasorunuGoster() }
                Button("Chrome'u aç") { model.chromeEklentilerSayfasiniAc() }
                if !model.chromeKopruKurulu {
                    Button("Köprüyü kur") { Task { await chromeDurumunuOku(kur: true) } }
                        .buttonStyle(.borderedProminent)
                }
                if model.chromeEklentiYuklu && eklentiYenidenYuklenmeli {
                    Button("Yeniden yükledim") {
                        ChromeKoprusu.eklentiGuncellemesiniOnayla()
                        eklentiYenidenYuklenmeli = false
                    }
                }
                Spacer()
                Button {
                    Task { await chromeDurumunuOku() }
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Yeniden denetle")
            }
            .controlSize(.small)
        }
        .task { await chromeDurumunuOku() }
    }

    /// Köprü/eklenti durumunu ve "eklenti güncellendi, Chrome'da yeniden yükleyin" işaretini okur.
    private func chromeDurumunuOku(kur: Bool = false) async {
        await model.chromeDurumunuYenile(kur: kur)
        eklentiYenidenYuklenmeli = await Task.detached { ChromeKoprusu.eklentiYenidenYuklenmeli }.value
    }

    /// Uygulama /Applications dışından çalışıyorsa Chrome köprüsü bu kopyayı kullanmaz ya da Chrome onu çalıştıramayabilir.
    private var chromeKonumUyarisi: String? {
        let kurulum = GorevliYoneticisi.kurulumYolu
        guard URL(fileURLWithPath: Bundle.main.bundlePath).standardizedFileURL.path != kurulum else { return nil }
        if FileManager.default.fileExists(atPath: kurulum) {
            return "Bu kopya /Applications dışından çalışıyor. Chrome köprüsü ve eklenti \(kurulum) kopyasından gelir; bu kopyadaki değişiklikler Chrome'da görünmez."
        }
        return "Uygulama /Applications dışından çalışıyor; Chrome bu konumdaki köprüyü çalıştıramayabilir. Chrome köprüsü için \(kurulum) kullanılmalı."
    }

    private func chromeDurumSatiri(_ tamam: Bool, _ evet: String, _ hayir: String) -> some View {
        Label {
            Text(tamam ? evet : hayir).foregroundStyle(tamam ? .primary : .secondary)
        } icon: {
            Image(systemName: tamam ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(tamam ? .green : .secondary)
        }
        .font(.callout)
    }

    private var gorevliKarti: some View {
        Kart(baslik: "Kesin mod görevlisi", simge: "gearshape.2") {
            gorevliRozeti
        } icerik: {
            if let g = model.gorevli {
                VStack(alignment: .leading, spacing: 6) {
                    BilgiSatiri(etiket: "Başlangıç", deger: Bicim.tarih(g.baslangic))
                    BilgiSatiri(etiket: "İşlenen iş", deger: "\(g.islenenSayisi)")
                    BilgiSatiri(etiket: "Son kontrol", deger: Bicim.goreceli(g.sonKontrol))
                }
                if !g.sonIslemler.isEmpty {
                    DisclosureGroup("Son işlemler") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(g.sonIslemler.suffix(5).reversed().enumerated()), id: \.offset) { _, satir in
                                Text(satir)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }
            } else {
                Text("Görevliden henüz kayıt yok.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.sabitleme.aktifKesinMod {
                HStack(spacing: 8) {
                    Button {
                        gorevliBaslatiliyor = true
                        Task {
                            await model.gorevliyiYenidenBaslat()
                            gorevliBaslatiliyor = false
                        }
                    } label: {
                        Label("Yeniden başlat", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(gorevliBaslatiliyor)
                    if gorevliBaslatiliyor {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            if GorevliYoneticisi.korumaliKlasorde {
                IpucuKutusu(metin: "Uygulama Masaüstü'nden çalışıyor; arka plan görevlisi için /Applications/Yazıcı Paneli.app kullanılmalı.",
                            simge: "exclamationmark.triangle.fill", renk: .orange)
            }

            if let yol = GorevliYoneticisi.program {
                ProgramYolu(yol: yol)
            }
        }
    }

    @ViewBuilder private var gorevliRozeti: some View {
        if model.sabitleme.aktifKesinMod {
            if model.gorevliCanli {
                DurumRozeti(metin: "Çalışıyor", renk: .green)
            } else {
                DurumRozeti(metin: "Çalışmıyor", renk: .red)
            }
        } else {
            DurumRozeti(metin: "Kapalı (kesin mod kullanılmıyor)", renk: .secondary)
        }
    }

    // MARK: Yardımcılar

    private var politikaMetni: String {
        let deger: String
        if let p = model.kuyruk?.hataPolitikasi, !p.isEmpty {
            deger = Self.politikaAdlari[p].map { "\(p) (\($0))" } ?? p
        } else {
            deger = "bilinmiyor"
        }
        return "Kalıcı olarak CUPS'a yazılır · şu anki değer: \(deger)"
    }

    private static let politikaAdlari: [String: String] = [
        "stop-printer": "kuyruğu durdur",
        "retry-current-job": "işi hemen yeniden dene",
        "retry-job": "işi sonra yeniden dene",
        "abort-job": "işi iptal et",
    ]

    private var surum: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "geliştirme"
    }
}

// MARK: - Anahtar satırı

private struct AnahtarSatiri: View {
    let baslik: String
    var aciklama: String? = nil
    @Binding var acik: Bool

    var body: some View {
        Toggle(isOn: $acik) {
            VStack(alignment: .leading, spacing: 2) {
                Text(baslik)
                    .fixedSize(horizontal: false, vertical: true)
                if let aciklama {
                    Text(aciklama)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
    }
}

// MARK: - Program yolu

private struct ProgramYolu: View {
    let yol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Program yolu")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(yol)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(yol, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Kopyala")
            }
        }
    }
}
