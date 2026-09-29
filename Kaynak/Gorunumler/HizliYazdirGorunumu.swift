import SwiftUI
import UniformTypeIdentifiers

struct HizliYazdirGorunumu: View {
    @Environment(UygulamaModeli.self) private var model

    @State private var dosyalar: [URL] = []
    @State private var bilgiler: [URL: DosyaBilgisi] = [:]
    @State private var ayarKaynagi: AyarKaynagi = .sabit
    @State private var ozelAyarlar = BaskiAyarSeti(kalite: .standart, griTon: false)
    @State private var secenekler = YazdirmaSecenekleri()

    @State private var hedefte = false
    @State private var secimAcik = false
    @State private var gonderiliyor = false
    @State private var onay: BekleyenOnay?

    var body: some View {
        Sayfa(baslik: "Hızlı Yazdır",
              altBaslik: "Dosyaları sürükleyin; seçtiğiniz ayarlarla doğrudan yazıcıya gitsin.",
              simge: Bolum.hizliYazdir.simge) {
            if model.kuyruk?.durdurulmus == true {
                kuyrukUyarisi
            }
            birakmaAlani
            if !dosyalar.isEmpty {
                dosyaListesi
            }
            ayarlarKarti
            seceneklerKarti
            yazdirSatiri
            elleCiftTarafKarti
        }
        .fileImporter(isPresented: $secimAcik, allowedContentTypes: [.pdf, .image, .plainText],
                      allowsMultipleSelection: true) { sonuc in
            switch sonuc {
            case .success(let urls): ekle(urls)
            case .failure(let hata): model.goster(hata.localizedDescription, .hata)
            }
        }
        .confirmationDialog(onay?.baslik ?? "", isPresented: onayGosteriliyor, titleVisibility: .visible,
                            presenting: onay) { o in
            Button(o.dugme) { onayla(o) }
            Button("Vazgeç", role: .cancel) {}
        } message: { o in
            Text(o.mesaj)
        }
        .onChange(of: ayarKaynagi) { eski, yeni in
            // "Özel"e geçince bir önceki seçimin kalite ve rengiyle başla.
            guard yeni == .ozel else { return }
            let a = ayarlar(icin: eski)
            ozelAyarlar = BaskiAyarSeti(kalite: a.kalite ?? .standart, griTon: a.griTon ?? false)
        }
        .onChange(of: model.hazirAyarlar.map(\.id)) { _, kimlikler in
            if case .hazir(let id) = ayarKaynagi, !kimlikler.contains(id) { ayarKaynagi = .sabit }
        }
        .animation(.snappy, value: dosyalar)
        .animation(.snappy, value: ayarKaynagi)
        .animation(.snappy, value: secenekler)
        .animation(.snappy, value: model.ciftTarafOturumu != nil)
        .animation(.snappy, value: model.kuyruk?.durdurulmus == true)
    }

    // MARK: - Kuyruk uyarısı

    private var kuyrukUyarisi: some View {
        HStack(spacing: 12) {
            IpucuKutusu(baslik: "Mac'teki kuyruk durdurulmuş",
                        metin: "Gönderdiğiniz dosyalar yazıcıya gitmez, kuyrukta bekler. Yazıcıda sorun yoksa kuyruğu sürdürün.",
                        simge: "pause.circle.fill", renk: .orange)
            Button {
                Task { await model.kuyruguSurdur() }
            } label: {
                Label("Kuyruğu sürdür", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Bırakma alanı

    private var birakmaAlani: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: dosyalar.isEmpty ? 38 : 28, weight: .light))
                .foregroundStyle(hedefte ? Color.accentColor : Color.secondary)
            Text("Dosyaları buraya bırakın")
                .font(.title3.weight(.medium))
            Text("ya da")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Dosya seç…") { secimAcik = true }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, dosyalar.isEmpty ? 40 : 22)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Tema.kose, style: .continuous)
                    .fill(hedefte ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.02))
                RoundedRectangle(cornerRadius: Tema.kose, style: .continuous)
                    .strokeBorder(hedefte ? Color.accentColor : Color.secondary.opacity(0.5),
                                  style: StrokeStyle(lineWidth: hedefte ? 2 : 1.5, dash: [7, 5]))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Tema.kose, style: .continuous))
        .dropDestination(for: URL.self) { urls, _ in
            ekle(urls)
            return true
        } isTargeted: { ustunde in
            hedefte = ustunde
        }
        .animation(.snappy, value: hedefte)
    }

    // MARK: - Dosya listesi

    private var dosyaListesi: some View {
        Kart(baslik: "Dosyalar", simge: "doc.on.doc", aksesuar: {
            Button("Tümünü temizle") { tumunuTemizle() }
                .buttonStyle(.borderless)
                .disabled(gonderiliyor)
        }) {
            VStack(spacing: 0) {
                ForEach(Array(dosyalar.enumerated()), id: \.element) { sira, url in
                    if sira > 0 { Divider() }
                    dosyaSatiri(url)
                }
            }
        }
    }

    private func dosyaSatiri(_ url: URL) -> some View {
        let bilgi = bilgiler[url]
        let tur = bilgi?.tur ?? .diger
        return HStack(spacing: 10) {
            Image(systemName: tur.simge)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(bilgi?.ayrinti ?? tur.ad)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                kaldir(url)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .disabled(gonderiliyor)
            .help("Listeden kaldır")
        }
        .padding(.vertical, 7)
    }

    // MARK: - Baskı ayarları

    private var ayarlarKarti: some View {
        Kart(baslik: "Baskı ayarları", simge: "dial.medium") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Ayarlar")
                        .gridColumnAlignment(.trailing)
                    Picker("Ayarlar", selection: $ayarKaynagi) {
                        Text(sabitEtiketi).tag(AyarKaynagi.sabit)
                        Divider()
                        ForEach(model.hazirAyarlar) { h in
                            Label(h.ad, systemImage: h.simge).tag(AyarKaynagi.hazir(h.id))
                        }
                        Divider()
                        Text("Özel").tag(AyarKaynagi.ozel)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if ayarKaynagi == .ozel {
                    GridRow {
                        Text("Kalite")
                        Picker("Kalite", selection: kaliteBaglami) {
                            ForEach(Kalite.allCases) { k in
                                Text(k.ad).tag(k)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    GridRow {
                        Text("Renk")
                        Picker("Renk", selection: renkBaglami) {
                            Text("Renkli").tag(false)
                            Text("Siyah-beyaz").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            Text(ozetMetni)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sabitEtiketi: String {
        model.sabitleme.etkin ? "Sabit ayarlar (\(model.sabitlemeOzeti))" : "Yazıcı varsayılanları"
    }

    private var kaliteBaglami: Binding<Kalite> {
        Binding(get: { ozelAyarlar.kalite ?? .standart }, set: { ozelAyarlar.kalite = $0 })
    }

    private var renkBaglami: Binding<Bool> {
        Binding(get: { ozelAyarlar.griTon ?? false }, set: { ozelAyarlar.griTon = $0 })
    }

    private var kullanilacakAyarlar: BaskiAyarSeti { ayarlar(icin: ayarKaynagi) }

    private func ayarlar(icin kaynak: AyarKaynagi) -> BaskiAyarSeti {
        switch kaynak {
        case .sabit:
            return model.etkinAyarlar
        case .hazir(let id):
            guard let h = model.hazirAyarlar.first(where: { $0.id == id }) else { return model.etkinAyarlar }
            return model.etkinAyarlar.birlestir(h.ayarlar)
        case .ozel:
            return model.etkinAyarlar.birlestir(ozelAyarlar)
        }
    }

    private var ozetMetni: String {
        let a = kullanilacakAyarlar
        var gosterilen = a
        if !a.kaliteUygulanabilir { gosterilen.kalite = nil }
        guard !gosterilen.bos else { return "Yazıcının kendi ayarları kullanılacak." }
        var metin = "Kullanılacak: " + gosterilen.ozet(katalog: model.katalog)
        if a.kalite != nil, !a.kaliteUygulanabilir { metin += " · kaliteyi bu kağıt türünde Canon belirler" }
        return metin
    }

    // MARK: - Seçenekler

    private var aralikGecerli: Bool { YazdirmaSecenekleri.aralikGecerli(secenekler.sayfaAraligi) }

    private var seceneklerKarti: some View {
        Kart(baslik: "Seçenekler", simge: "switch.2") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Kopya")
                        .gridColumnAlignment(.trailing)
                    HStack(spacing: 16) {
                        Stepper(value: $secenekler.kopya, in: 1...99) {
                            Text("\(secenekler.kopya)")
                                .monospacedDigit()
                                .frame(minWidth: 20, alignment: .trailing)
                        }
                        .fixedSize()
                        if secenekler.kopya > 1 {
                            Toggle("Harmanla", isOn: $secenekler.harmanla)
                                .help("Kopyaları sırayla bas: 1-2-3, 1-2-3")
                        }
                    }
                }
                GridRow {
                    Text("Sayfa aralığı")
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Sayfa aralığı", text: $secenekler.sayfaAraligi, prompt: Text("Tümü — ör. 1-3, 5"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                        if !aralikGecerli {
                            Text("Geçersiz aralık. Örnek: 1-3, 5")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                GridRow {
                    Text("Yön")
                    Picker("Yön", selection: $secenekler.yon) {
                        ForEach(SayfaYonu.allCases) { y in
                            Text(y.ad).tag(y)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text("Ölçek")
                    Toggle("Sayfaya sığdır", isOn: $secenekler.sigdir)
                }
                GridRow {
                    Text("Yaprak başına sayfa")
                    Picker("Yaprak başına sayfa", selection: $secenekler.yaprakBasinaSayfa) {
                        ForEach(YazdirmaSecenekleri.yaprakSecenekleri, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text("Sayfalar")
                    Picker("Sayfalar", selection: $secenekler.sayfaKumesi) {
                        ForEach(SayfaKumesi.allCases) { k in
                            Text(k.ad).tag(k)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text("Çıkış sırası")
                    Picker("Çıkış sırası", selection: $secenekler.cikisSirasi) {
                        ForEach(CikisSirasi.allCases) { c in
                            Text(c.ad).tag(c)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - Yazdır

    private var yazdirSatiri: some View {
        HStack {
            Spacer()
            Button {
                yazdirIstendi()
            } label: {
                Label("Yazdır", systemImage: "printer.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("p", modifiers: .command)
            .disabled(dosyalar.isEmpty || !aralikGecerli || gonderiliyor)
            .help("Seçilen dosyaları yazdır (⌘P)")
        }
    }

    // MARK: - Elle çift taraf

    private var tekPDF: URL? {
        guard dosyalar.count == 1, let url = dosyalar.first, bilgiler[url]?.tur == .pdf else { return nil }
        return url
    }

    private var elleCiftTarafKarti: some View {
        Kart(baslik: "Elle çift taraf", simge: "book.pages") {
            if let oturum = model.ciftTarafOturumu {
                ikinciAdim(oturum)
            } else if let url = tekPDF {
                birinciAdim(url)
            } else {
                Text("G3010 kağıdın iki yüzüne kendiliğinden basamaz. Tek bir PDF seçtiğinizde burada iki adımda basabilirsiniz: önce tek, sonra çift sayfalar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func birinciAdim(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("G3010 otomatik çift taraf basamaz. Önce tek sayfalar basılır; kağıtları çevirip arka tepsiye koyduktan sonra çift sayfalar basılır.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !secenekler.sayfaAraligi.trimmingCharacters(in: .whitespaces).isEmpty || secenekler.sayfaKumesi != .tumu
                || secenekler.cikisSirasi != .yazici {
                Text("Sayfa aralığı, “Sayfalar” ve “Çıkış sırası” burada kullanılmaz; belgenin tamamı basılır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("1. Tek sayfaları bas") { tekSayfalariBasIstendi() }
                .buttonStyle(.bordered)
                .disabled(gonderiliyor)
            IpucuKutusu(metin: "İlk kullanımda 4 sayfalık bir belgeyle deneyin.", simge: "lightbulb")
        }
    }

    private func ikinciAdim(_ oturum: ElleCiftTarafOturumu) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("“\(oturum.ad)” için tek sayfalar gönderildi. Baskı bitince:", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(ElleCiftTarafOturumu.talimatlar.enumerated()), id: \.offset) { sira, metin in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(sira + 1).")
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(metin)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if oturum.hazirlik.bosSayfaEklendi {
                    Text("Basılı yüz sayısı tek olduğu için sona boş sayfa eklendi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Toggle("Çift sayfaları diğer sırayla bas",
                       isOn: Binding(get: { model.ciftTarafSirayiCevir }, set: { model.ciftTarafSirayiCevir = $0 }))
                Text("Arka yüzler yanlış yaprağa denk gelirse (ör. 2. sayfa son yaprağın arkasına çıkarsa) bunu açıp tekrar deneyin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            HStack(spacing: 10) {
                Button("2. Çift sayfaları bas") { ciftSayfalariBas() }
                    .buttonStyle(.borderedProminent)
                    .disabled(gonderiliyor)
                Button("Vazgeç") { ciftTarafiSifirla() }
                    .buttonStyle(.bordered)
                    .disabled(gonderiliyor)
            }
        }
    }

    // MARK: - Onay

    private var onayGosteriliyor: Binding<Bool> {
        Binding(get: { onay != nil }, set: { if !$0 { onay = nil } })
    }

    private func onayla(_ o: BekleyenOnay) {
        switch o.tur {
        case .yazdir: yazdir()
        case .tekSayfalar: tekSayfalariBas()
        }
    }

    // MARK: - Eylemler

    private func ekle(_ urls: [URL]) {
        var reddedilen = 0
        for ham in urls {
            guard ham.isFileURL else { reddedilen += 1; continue }
            let url = ham.standardizedFileURL
            guard !dosyalar.contains(url) else { continue }
            let bilgi = DosyaBilgisi.oku(url)
            guard bilgi.tur != .diger else { reddedilen += 1; continue }
            bilgiler[url] = bilgi
            dosyalar.append(url)
        }
        if reddedilen > 0 {
            model.goster(reddedilen == 1 ? "Bu dosya türü yazdırılamıyor. PDF, görsel ya da düz metin ekleyin."
                                         : "\(reddedilen) dosya eklenmedi: yalnız PDF, görsel ve düz metin yazdırılabilir.",
                         .bilgi)
        }
    }

    private func kaldir(_ url: URL) {
        dosyalar.removeAll { $0 == url }
        bilgiler[url] = nil
    }

    private func tumunuTemizle() {
        dosyalar.removeAll()
        bilgiler.removeAll()
    }

    private func yazdirIstendi() {
        guard !dosyalar.isEmpty, aralikGecerli else { return }
        let yaprak = HizliYazdirGorunumu.tahminiYaprak(sayfalar: dosyalar.map { bilgiler[$0]?.sayfa ?? 1 },
                                                        secenekler: secenekler)
        if secenekler.kopya > 5 || yaprak > 20 {
            onay = BekleyenOnay(tur: .yazdir, yaprak: yaprak, kopya: secenekler.kopya)
        } else {
            yazdir()
        }
    }

    private func yazdir() {
        let gonderilen = dosyalar, a = kullanilacakAyarlar, s = secenekler
        guard !gonderilen.isEmpty else { return }
        gonderiliyor = true
        Task {
            let numaralar = await model.dosyalariYazdir(gonderilen, ayarlar: a, secenekler: s)
            gonderiliyor = false
            // Yalnız gerçekten gönderilenler listeden çıkar; hata alanlar yeniden denenebilsin.
            let giden = Set(numaralar.keys)
            dosyalar.removeAll { giden.contains($0) }
            for u in giden { bilgiler[u] = nil }
        }
    }

    private func tekSayfalariBasIstendi() {
        guard let url = tekPDF else { return }
        var s = secenekler
        s.sayfaKumesi = .tek
        s.sayfaAraligi = ""
        let yaprak = HizliYazdirGorunumu.tahminiYaprak(sayfalar: [bilgiler[url]?.sayfa ?? 1], secenekler: s)
        if s.kopya > 5 || yaprak > 20 {
            onay = BekleyenOnay(tur: .tekSayfalar, yaprak: yaprak, kopya: s.kopya)
        } else {
            tekSayfalariBas()
        }
    }

    private func tekSayfalariBas() {
        guard let url = tekPDF else { return }
        let a = kullanilacakAyarlar, s = secenekler
        gonderiliyor = true
        Task {
            await model.elleCiftTarafBaslat(url, ayarlar: a, secenekler: s)
            gonderiliyor = false
        }
    }

    private func ciftSayfalariBas() {
        guard model.ciftTarafOturumu != nil else { return }
        gonderiliyor = true
        Task {
            await model.elleCiftTarafBitir()   // başarısızsa oturum kalır, yeniden denenebilir
            gonderiliyor = false
        }
    }

    private func ciftTarafiSifirla() {
        model.elleCiftTarafVazgec()
    }

    // MARK: - Kağıt tahmini

    /// Kabaca kaç yaprak kağıt gideceği (aralık, yaprak başına sayfa, tek/çift ve kopya hesaba katılır).
    private static func tahminiYaprak(sayfalar: [Int], secenekler s: YazdirmaSecenekleri) -> Int {
        let nup = max(1, s.yaprakBasinaSayfa)
        var toplam = 0
        for n in sayfalar {
            let secili = aralikSayfaSayisi(s.sayfaAraligi, toplam: max(1, n))
            let yuz = (secili + nup - 1) / nup
            switch s.sayfaKumesi {
            case .tumu: toplam += yuz
            case .tek: toplam += (yuz + 1) / 2
            case .cift: toplam += yuz / 2
            }
        }
        return toplam * max(1, s.kopya)
    }

    /// "1-3, 5" gibi bir aralığın `toplam` sayfalık belgede kaç sayfa seçtiği (boşsa hepsi).
    private static func aralikSayfaSayisi(_ metin: String, toplam n: Int) -> Int {
        let t = metin.replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty, YazdirmaSecenekleri.aralikGecerli(t) else { return n }
        var kume = IndexSet()
        for parca in t.split(separator: ",") {
            let uclar = parca.split(separator: "-").compactMap { Int($0) }
            guard let bas = uclar.first else { continue }
            let son = uclar.count > 1 ? uclar[1] : bas
            let a = max(1, bas), b = min(n, son)
            if a <= b { kume.insert(integersIn: a...b) }
        }
        return kume.count
    }
}

// MARK: - Yardımcı türler

private enum AyarKaynagi: Hashable {
    case sabit
    case hazir(UUID)
    case ozel
}

private enum DosyaTuru {
    case pdf, gorsel, metin, diger

    init(_ tur: UTType?) {
        guard let tur else { self = .diger; return }
        if tur.conforms(to: .pdf) { self = .pdf }
        else if tur.conforms(to: .image) { self = .gorsel }
        else if tur.conforms(to: .plainText) { self = .metin }
        else { self = .diger }
    }

    var ad: String {
        switch self {
        case .pdf: return "PDF"
        case .gorsel: return "Görsel"
        case .metin: return "Metin"
        case .diger: return "Dosya"
        }
    }

    var simge: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .gorsel: return "photo"
        case .metin: return "doc.plaintext"
        case .diger: return "doc"
        }
    }
}

private struct DosyaBilgisi {
    let tur: DosyaTuru
    let boyut: Int64?
    let sayfa: Int?

    /// "PDF · 1,2 MB · 12 sayfa"
    var ayrinti: String {
        var p = [tur.ad]
        if let boyut { p.append(ByteCountFormatter.string(fromByteCount: boyut, countStyle: .file)) }
        if let sayfa { p.append("\(sayfa) sayfa") }
        return p.joined(separator: " · ")
    }

    static func oku(_ url: URL) -> DosyaBilgisi {
        let erisim = url.startAccessingSecurityScopedResource()
        defer { if erisim { url.stopAccessingSecurityScopedResource() } }
        let icerikTuru = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        let tur = DosyaTuru(icerikTuru)
        let oznitelikler = try? FileManager.default.attributesOfItem(atPath: url.path)
        let boyut = (oznitelikler?[.size] as? NSNumber)?.int64Value
        let sayfa = tur == .pdf ? ElleCiftTaraf.sayfaSayisi(url) : nil
        return DosyaBilgisi(tur: tur, boyut: boyut, sayfa: sayfa)
    }
}

private struct BekleyenOnay {
    enum Tur { case yazdir, tekSayfalar }
    let tur: Tur
    let yaprak: Int
    let kopya: Int

    var baslik: String { tur == .yazdir ? "Yazdırılsın mı?" : "Tek sayfalar basılsın mı?" }
    var dugme: String { tur == .yazdir ? "Yazdır" : "Bas" }
    var mesaj: String {
        kopya > 1 ? "\(kopya) kopya · yaklaşık \(yaprak) yaprak kağıt kullanılacak."
                  : "Yaklaşık \(yaprak) yaprak kağıt kullanılacak."
    }
}
