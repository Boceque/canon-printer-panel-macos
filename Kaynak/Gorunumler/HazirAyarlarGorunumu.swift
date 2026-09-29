import SwiftUI

/// Hazır Ayarlar: tek tıkla sabitlenen ayar grupları.
struct HazirAyarlarGorunumu: View {
    @Environment(UygulamaModeli.self) private var model
    @State private var yeniAcik = false
    @State private var yenidenAdlandirilan: HazirAyar?
    @State private var yeniAd = ""
    @State private var silinecek: HazirAyar?

    private let sutunlar = [GridItem(.adaptive(minimum: 250), spacing: Tema.bosluk)]

    var body: some View {
        Sayfa(baslik: "Hazır Ayarlar", altBaslik: "Tek tıkla sabitlenen ayar grupları",
              simge: Bolum.hazirAyarlar.simge) {
            LazyVGrid(columns: sutunlar, alignment: .leading, spacing: Tema.bosluk) {
                ForEach(model.hazirAyarlar) { h in
                    kart(h)
                }
                yeniKarti
            }
            .animation(.snappy, value: model.hazirAyarlar)

            Text("Bir hazır ayarı sabitlemek, Baskı Ayarları'ndaki 'yazdırma penceresi' ve 'kesin mod' seçimlerini korur.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $yeniAcik) {
            YeniHazirAyarPenceresi(katalog: model.katalog) { ad, simge, aciklama, ayarlar in
                model.hazirAyarKaydet(ad: ad, simge: simge, aciklama: aciklama, ayarlar: ayarlar)
            }
        }
        .alert("Yeniden adlandır", isPresented: adlandirmaAcik, presenting: yenidenAdlandirilan) { h in
            TextField("Ad", text: $yeniAd)
            Button("Kaydet") {
                let ad = yeniAd.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !ad.isEmpty else { return }
                var guncel = h
                guncel.ad = ad
                model.hazirAyarGuncelle(guncel)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { h in
            Text("\"\(h.ad)\" için yeni bir ad yazın.")
        }
        .confirmationDialog(silinecek.map { "\"\($0.ad)\" silinsin mi?" } ?? "",
                            isPresented: silmeAcik, titleVisibility: .visible, presenting: silinecek) { h in
            Button("Sil", role: .destructive) { model.hazirAyarSil(h) }
            Button("Vazgeç", role: .cancel) {}
        } message: { _ in
            Text("Hazır ayar listeden kaldırılır. Şu an sabit olan ayarlar değişmez.")
        }
    }

    private var adlandirmaAcik: Binding<Bool> {
        Binding(get: { yenidenAdlandirilan != nil }, set: { if !$0 { yenidenAdlandirilan = nil } })
    }

    private var silmeAcik: Binding<Bool> {
        Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } })
    }

    // MARK: - Kart

    private func kart(_ h: HazirAyar) -> some View {
        let etkin = model.etkinHazirAyar?.id == h.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: h.simge)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 34, alignment: .leading)
                Spacer(minLength: 4)
                if etkin {
                    DurumRozeti(metin: "Sabit", renk: .accentColor, simge: "lock.fill")
                }
                if h.yerlesik {
                    DurumRozeti(metin: "Yerleşik")
                } else {
                    Menu {
                        ozelEylemler(h)
                    } label: {
                        Label("Diğer", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Diğer")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(h.ad).font(.headline)
                if !h.aciklama.isEmpty {
                    Text(h.aciklama)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Label(h.ayarlar.ozet(katalog: model.katalog), systemImage: "slider.horizontal.3")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    Task { await model.hazirAyariSabitle(h) }
                } label: {
                    Label(etkin ? "Etkin" : "Sabitle", systemImage: etkin ? "checkmark" : "lock.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(etkin || model.mesgul != nil)

                Button("Düzenle") { model.hazirAyariDuzenleyiciyeYukle(h) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(Tema.bosluk)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(KartZemini(vurgu: etkin ? .accentColor : nil))
        .contextMenu {
            if !h.yerlesik { ozelEylemler(h) }
        }
    }

    @ViewBuilder private func ozelEylemler(_ h: HazirAyar) -> some View {
        Button("Yeniden adlandır…") {
            yeniAd = h.ad
            yenidenAdlandirilan = h
        }
        Button("Sil", role: .destructive) { silinecek = h }
    }

    private var yeniKarti: some View {
        let sekil = RoundedRectangle(cornerRadius: Tema.kose, style: .continuous)
        return Button {
            yeniAcik = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                Text("Yeni hazır ayar").font(.headline)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(sekil.strokeBorder(Color.secondary.opacity(0.45),
                                           style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .contentShape(sekil)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Yeni hazır ayar

private struct YeniHazirAyarPenceresi: View {
    let katalog: PPDKatalogu?
    let kaydet: (_ ad: String, _ simge: String, _ aciklama: String, _ ayarlar: BaskiAyarSeti) -> Void

    @Environment(\.dismiss) private var kapat
    @State private var ad = ""
    @State private var simge = "star"
    @State private var aciklama = ""
    @State private var kalite: Kalite?
    @State private var griTon: Bool?
    @State private var ortam: String?

    private var temizAd: String { ad.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var ayarlar: BaskiAyarSeti { BaskiAyarSeti(kalite: kalite, griTon: griTon, ortam: ortam) }

    private var ortamSecimleri: [PPDSecimi] {
        katalog?["CNIJMediaType"]?.secimler ?? [PPDSecimi(kod: "0", ad: "Düz Kağıt", ingilizceAd: "Plain Paper")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Yeni hazır ayar").font(.title3.weight(.semibold))

            Form {
                Section {
                    TextField("Ad", text: $ad, prompt: Text("Ör. Deneme sınavı"))
                    LabeledContent("Simge") {
                        HazirSimgeSecici(secili: $simge)
                    }
                    TextField("Açıklama", text: $aciklama, prompt: Text("İsteğe bağlı"))
                }
                Section {
                    Picker("Baskı kalitesi", selection: $kalite) {
                        Text("Dokunma").tag(Kalite?.none)
                        Divider()
                        ForEach(Kalite.allCases) { k in
                            Text(k.ad).tag(Optional(k))
                        }
                    }
                    Picker("Renk", selection: $griTon) {
                        Text("Dokunma").tag(Bool?.none)
                        Divider()
                        Text("Renkli").tag(Optional(false))
                        Text("Siyah-beyaz").tag(Optional(true))
                    }
                    Picker("Kağıt türü", selection: $ortam) {
                        Text("Dokunma").tag(String?.none)
                        Divider()
                        ForEach(ortamSecimleri) { s in
                            Text(s.ad).tag(Optional(s.kod))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if kalite != nil, let ortam, ortam != "0" {
                    Text("Fotoğraf kağıdında kaliteyi Canon kağıda göre seçer; kalite sabitlenmez.")
                }
                Text("\"Dokunma\" seçilen ayarlar sabitlenmez.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { kapat() }
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet") {
                    kaydet(temizAd, simge, aciklama.trimmingCharacters(in: .whitespacesAndNewlines), ayarlar)
                    kapat()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(temizAd.isEmpty || ayarlar.bos)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

private struct HazirSimgeSecici: View {
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
