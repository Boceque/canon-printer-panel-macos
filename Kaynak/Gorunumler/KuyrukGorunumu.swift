import SwiftUI

/// "Yazdırma Kuyruğu": etkin işler, geçmiş ve kuyruk eylemleri.
struct KuyrukGorunumu: View {
    @Environment(UygulamaModeli.self) private var model

    @State private var iptalEdilecek: YaziciIsi?
    @State private var yenidenBasilacak: YaziciIsi?
    @State private var tumunuIptalSor = false
    @State private var durdurmaSor = false
    @State private var gecmisTumu = false

    private var etkinIsler: [YaziciIsi] { model.isler.filter { $0.durum.etkin } }
    private var durdurulmus: Bool { model.kuyruk?.durdurulmus ?? false }

    private var altBaslik: String {
        let n = model.bekleyenIsSayisi
        return n > 0 ? "\(n) bekleyen iş" : "Kuyruk boş"
    }

    var body: some View {
        Sayfa(baslik: "Yazdırma Kuyruğu", altBaslik: altBaslik, simge: Bolum.kuyruk.simge) {
            ustUyarilar
            eylemSatiri
            etkinKart
            gecmisKart
        }
        .animation(.snappy, value: durdurulmus)
        .animation(.snappy, value: model.takiliIsSayisi)
    }

    // MARK: Üst uyarılar

    @ViewBuilder private var ustUyarilar: some View {
        if durdurulmus {
            HStack(spacing: 10) {
                IpucuKutusu(metin: "Kuyruk durduruldu — işler yazıcıya gitmiyor",
                            simge: "pause.circle.fill", renk: .orange)
                Button {
                    Task { await model.kuyruguSurdur() }
                } label: {
                    Label("Sürdür", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()
            }
            .transition(.opacity)
        }
        if model.takiliIsSayisi > 0 {
            HStack(spacing: 10) {
                IpucuKutusu(metin: "Kesin mod görevlisi çalışmıyor; \(model.takiliIsSayisi) iş bekliyor",
                            simge: "exclamationmark.octagon.fill", renk: .red)
                Button {
                    Task { await model.bekleyenleriSerbestBirak() }
                } label: {
                    Label("Bekleyenleri gönder", systemImage: "paperplane")
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()
                .disabled(model.mesgul != nil)
                Button {
                    Task { await model.gorevliyiYenidenBaslat() }
                } label: {
                    Label("Görevliyi başlat", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(model.mesgul != nil)
            }
            .transition(.opacity)
        }
    }

    // MARK: Eylem satırı

    private var eylemSatiri: some View {
        HStack(spacing: 8) {
            if !etkinIsler.isEmpty {
                Button(role: .destructive) {
                    tumunuIptalSor = true
                } label: {
                    Label("Tümünü iptal et", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .confirmationDialog("Tüm işler iptal edilsin mi?", isPresented: $tumunuIptalSor) {
                    Button("Tümünü iptal et", role: .destructive) {
                        Task { await model.tumunuIptal() }
                    }
                    Button("Vazgeç", role: .cancel) {}
                } message: {
                    Text("\(etkinIsler.count) iş kuyruktan kaldırılacak. Yazdırılmakta olan sayfa yarıda kalabilir.")
                }
            }

            if durdurulmus {
                Button {
                    Task { await model.kuyruguSurdur() }
                } label: {
                    Label("Kuyruğu sürdür", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    durdurmaSor = true
                } label: {
                    Label("Kuyruğu durdur", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)
                .confirmationDialog("Kuyruk durdurulsun mu?", isPresented: $durdurmaSor) {
                    Button("Kuyruğu durdur") {
                        Task { await model.kuyruguDurdur() }
                    }
                    Button("Vazgeç", role: .cancel) {}
                } message: {
                    Text("İşler yazıcıya gönderilmez; siz sürdürene kadar kuyrukta bekler.")
                }
            }
            Spacer(minLength: 0)
        }
        .disabled(model.kuyrukAdi.isEmpty)
    }

    // MARK: Etkin işler

    private var etkinKart: some View {
        Kart(baslik: "Etkin işler", simge: "printer") {
            if etkinIsler.isEmpty {
                ContentUnavailableView("Kuyruk boş", systemImage: "tray",
                                       description: Text("Bekleyen ya da yazdırılan iş yok."))
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(etkinIsler.enumerated()), id: \.element.id) { sira, iş in
                        if sira > 0 { Divider().padding(.horizontal, 8) }
                        etkinSatir(iş)
                    }
                }
                .padding(.horizontal, -8)
            }
        }
        .animation(.snappy, value: etkinIsler)
        .confirmationDialog("İş iptal edilsin mi?",
                            isPresented: Binding(get: { iptalEdilecek != nil },
                                                 set: { if !$0 { iptalEdilecek = nil } }),
                            presenting: iptalEdilecek) { iş in
            Button("İşi iptal et", role: .destructive) {
                Task { await model.isIptal(iş.id) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { iş in
            Text("“\(iş.ad)” (#\(iş.id)) kuyruktan kaldırılacak.")
        }
    }

    private func etkinSatir(_ iş: YaziciIsi) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Tema.simge(iş.durum))
                .font(.title3)
                .foregroundStyle(Tema.renk(iş.durum))
                .symbolEffect(.pulse, isActive: iş.durum == .yazdiriliyor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(iş.ad)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ayrintiSatiri(iş))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                AkisDuzeni(bosluk: 6) {
                    DurumRozeti(metin: iş.durum.ad, renk: Tema.renk(iş.durum))
                    if let kalite = iş.kaliteAdi {
                        DurumRozeti(metin: kalite, simge: "dial.medium")
                    }
                    if iş.griTonMu {
                        DurumRozeti(metin: "Siyah-beyaz", simge: "circle.lefthalf.filled")
                    }
                    if iş.sabitlemeIsareti == "1" {
                        DurumRozeti(metin: "Sabitlendi", renk: .accentColor, simge: "lock.fill")
                    }
                    if iş.komutIsi {
                        DurumRozeti(metin: "Bakım komutu", simge: "wrench.and.screwdriver")
                    }
                    if let neden = iş.nedenMetni {
                        DurumRozeti(metin: neden, renk: .secondary)
                    }
                }

                if !iş.yaziciMesaji.isEmpty {
                    Text(iş.yaziciMesaji)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let sayfa = iş.basilanSayfa, sayfa > 0 {
                    Text("\(sayfa) sayfa basıldı")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if iş.durum == .beklemede {
                    Button {
                        Task { await model.isSurdur(iş.id) }
                    } label: {
                        Label("Sürdür", systemImage: "play.fill")
                    }
                } else if iş.durum == .sirada {
                    Button {
                        Task { await model.isBeklet(iş.id) }
                    } label: {
                        Label("Beklet", systemImage: "pause.fill")
                    }
                }
                Button(role: .destructive) {
                    iptalEdilecek = iş
                } label: {
                    Label("İptal", systemImage: "xmark")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
        }
        .modifier(UzerindeVurgu())
    }

    private func ayrintiSatiri(_ iş: YaziciIsi) -> String {
        var parcalar = ["#\(iş.id)"]
        if !iş.sahip.isEmpty { parcalar.append(iş.sahip) }
        if iş.olusturma != nil { parcalar.append(Bicim.goreceli(iş.olusturma)) }
        if iş.boyutKB != nil { parcalar.append(Bicim.boyut(kb: iş.boyutKB)) }
        return parcalar.joined(separator: " · ")
    }

    // MARK: Geçmiş

    private var gecmisKart: some View {
        let hepsi = model.tamamlananlar
        let gosterilen = gecmisTumu ? hepsi : Array(hepsi.prefix(20))
        return Kart(baslik: "Geçmiş", simge: "clock.arrow.circlepath") {
            if hepsi.isEmpty {
                Text("Henüz tamamlanan iş yok.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(gosterilen.enumerated()), id: \.element.id) { sira, iş in
                        if sira > 0 { Divider().padding(.horizontal, 8) }
                        gecmisSatir(iş)
                    }
                }
                .padding(.horizontal, -8)

                if !gecmisTumu && hepsi.count > 20 {
                    Button("Tümünü göster (\(hepsi.count))") {
                        withAnimation(.snappy) { gecmisTumu = true }
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }
        }
        .confirmationDialog("İş yeniden yazdırılsın mı?",
                            isPresented: Binding(get: { yenidenBasilacak != nil },
                                                 set: { if !$0 { yenidenBasilacak = nil } }),
                            presenting: yenidenBasilacak) { iş in
            Button("Yeniden yazdır") {
                Task { await model.isYenidenBas(iş.id) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { iş in
            Text("“\(iş.ad)” yeniden basılacak; kağıt ve mürekkep harcanır.")
        }
    }

    private func gecmisSatir(_ iş: YaziciIsi) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Tema.simge(iş.durum))
                .foregroundStyle(Tema.renk(iş.durum))
                .frame(width: 18)
            Text(iş.ad)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                Text(Bicim.tarih(iş.tamamlanma ?? iş.olusturma))
                    .frame(width: 112, alignment: .leading)
                Text(iş.basilanSayfa.map { $0 > 0 ? "\($0) sayfa" : "" } ?? "")
                    .frame(width: 56, alignment: .trailing)
                Text(iş.kaliteAdi ?? "")
                    .frame(width: 84, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            DurumRozeti(metin: iş.durum.ad, renk: Tema.renk(iş.durum))
                .fixedSize()
                .frame(width: 100, alignment: .trailing)
        }
        .font(.callout)
        .modifier(UzerindeVurgu(dikey: 5))
        .contextMenu {
            if iş.belgeSaklandi != false && !iş.komutIsi {
                Button {
                    yenidenBasilacak = iş
                } label: {
                    Label("Yeniden yazdır", systemImage: "arrow.clockwise")
                }
            } else {
                Text("Mac bu belgeyi saklamadı; yeniden yazdırılamaz")
            }
        }
    }
}

// MARK: - Yardımcılar

/// Satırın üstüne gelince hafif zemin.
private struct UzerindeVurgu: ViewModifier {
    var dikey: CGFloat = 8
    @State private var uzerinde = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, dikey)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(uzerinde ? 0.045 : 0))
            )
            .contentShape(Rectangle())
            .onHover { uzerinde = $0 }
    }
}

/// Rozetleri satıra sığdığı kadar yan yana dizer, sığmayanı alt satıra geçirir.
private struct AkisDuzeni: Layout {
    var bosluk: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        yerlesim(genislik: proposal.width, subviews: subviews).boyut
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sonuc = yerlesim(genislik: bounds.width, subviews: subviews)
        for (i, s) in subviews.enumerated() {
            let c = sonuc.cerceveler[i]
            s.place(at: CGPoint(x: bounds.minX + c.minX, y: bounds.minY + c.minY),
                    proposal: ProposedViewSize(width: c.width, height: c.height))
        }
    }

    private func yerlesim(genislik: CGFloat?, subviews: Subviews) -> (boyut: CGSize, cerceveler: [CGRect]) {
        let sinir = genislik ?? .infinity
        var cerceveler: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, satirYuksekligi: CGFloat = 0, enGenis: CGFloat = 0
        for s in subviews {
            var b = s.sizeThatFits(.unspecified)
            b.width = min(b.width, sinir)
            if x > 0, x + b.width > sinir {
                x = 0
                y += satirYuksekligi + bosluk
                satirYuksekligi = 0
            }
            cerceveler.append(CGRect(x: x, y: y, width: b.width, height: b.height))
            x += b.width + bosluk
            satirYuksekligi = max(satirYuksekligi, b.height)
            enGenis = max(enGenis, x - bosluk)
        }
        return (CGSize(width: enGenis, height: y + satirYuksekligi), cerceveler)
    }
}
