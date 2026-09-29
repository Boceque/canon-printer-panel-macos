import SwiftUI

struct BakimGorunumu: View {
    @Environment(UygulamaModeli.self) private var model

    var body: some View {
        Sayfa(baslik: Bolum.bakim.ad,
              altBaslik: "Komutlar yazıcıya doğrudan ağdan, Canon'un yeni komut biçimiyle gönderilir.",
              simge: Bolum.bakim.simge) {
            VStack(alignment: .leading, spacing: Tema.bosluk) {
                if let canli = model.bakimCanli {
                    CanliDurumKarti(canli: canli)
                        .transition(.opacity)
                }

                if model.cihazAdresi == nil, let hata = model.cihazHatasi {
                    IpucuKutusu(baslik: "Yazıcıya ağdan ulaşılamıyor", metin: hata,
                                simge: "wifi.exclamationmark", renk: .orange)
                }

                IpucuKutusu(metin: "Önerilen sıra: Püskürtme ucu denetimi → Temizleme → yeniden denetim → gerekirse Yoğun temizleme. Temizlikler mürekkep harcar; gereksiz yere yapmayın.")

                BakimBolumu(baslik: "Baskı kalitesi") {
                    IslemKarti(islem: .tur(.puskurtmeDenetimi))
                    IslemKarti(islem: .tur(.temizleme))
                    IslemKarti(islem: .tur(.yogunTemizleme))
                    IslemKarti(islem: .tur(.kafaHizalama), ikincil: .tur(.hizalamaDegerleri),
                               ikincilDugme: "Hizalama değerlerini yazdır")
                    IslemKarti(islem: .tur(.sistemTemizleme),
                               ekUyari: "Atık mürekkep emicisini doldurur; yalnız son çare.",
                               vurgu: .orange)
                }

                BakimBolumu(baslik: "Kağıt yolu") {
                    IslemKarti(islem: .tur(.altPlaka))
                    SilindirKarti()
                }

                BakimBolumu(baslik: "Mürekkep") {
                    IslemKarti(islem: .tur(.murekkepSayaci), dugme: "Sıfırla")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Ayarlar")
                        .font(.title3.weight(.semibold))
                    CihazAyarlariKarti()
                }
                .padding(.top, 8)
            }
            .animation(.snappy, value: model.bakimCanli)
        }
    }
}

// MARK: - Bölüm ve ızgara

private struct BakimBolumu<Icerik: View>: View {
    let baslik: String
    @ViewBuilder var icerik: () -> Icerik

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(baslik)
                .font(.title3.weight(.semibold))
            // En az 320 pt: sayfanın en geniş hâlinde (944 pt) bile en çok iki sütun olur.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Tema.bosluk, alignment: .top)],
                      alignment: .leading, spacing: Tema.bosluk) {
                icerik()
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Canlı durum

private struct CanliDurumKarti: View {
    @Environment(UygulamaModeli.self) private var model
    let canli: BakimCanliDurum

    private var gorunum: (metin: String, simge: String, renk: Color) {
        switch canli.asama {
        case .gonderiliyor: return ("Gönderiliyor", "paperplane", .blue)
        case .calisiyor: return ("Çalışıyor", "gearshape.2", .blue)
        case .bitti: return ("Bitti", "checkmark.circle.fill", .green)
        case .gonderildi: return ("Gönderildi", "paperplane.fill", .secondary)
        case .uyari: return ("Uyarı", "exclamationmark.triangle.fill", .orange)
        case .hata: return (canli.izleniyor ? "Yazıcı durdu" : "Hata", "xmark.octagon.fill", .red)
        }
    }

    var body: some View {
        let g = gorunum
        Kart(baslik: canli.ad, simge: canli.islem.simge, vurgu: canli.suruyor ? nil : g.renk) {
            DurumRozeti(metin: g.metin, renk: g.renk, simge: g.simge)
        } icerik: {
            HStack(alignment: .center, spacing: 8) {
                if canli.suruyor && canli.asama != .hata {
                    ProgressView().controlSize(.small)
                }
                Text(canli.mesaj)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canli.suruyor, let ipucu = canli.islem.canliIpucu {
                Text(ipucu)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canli.asama == .hata && canli.izleniyor {
                Text("Sorun giderilince yazıcı kaldığı yerden sürer; izleme devam ediyor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { baglam in
                    let son = canli.bitis ?? baglam.date
                    Label((canli.suruyor ? "Geçen süre: " : "Süre: ")
                          + sureMetni(son.timeIntervalSince(canli.baslangic)),
                          systemImage: "clock")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if canli.durdurulabilir {
                    Button(canli.durdurmaIstendi ? "Durduruluyor…" : "Durdur", systemImage: "stop.fill") {
                        Task { await model.bakimiDurdur() }
                    }
                    .disabled(canli.durdurmaIstendi)
                    .help("Yazıcıya işi iptal ettirir. Başlamış bir temizlik biraz mürekkep harcamış olabilir.")
                }
                if !canli.suruyor {
                    Button("Kapat") { model.bakimSonucunuKapat() }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

private func sureMetni(_ saniye: TimeInterval) -> String {
    let s = max(0, Int(saniye))
    return s < 60 ? "\(s) sn" : "\(s / 60) dk \(s % 60) sn"
}

// MARK: - Ortak parçalar

private struct SuruyorEtiketi: View {
    var metin = "Sürüyor…"

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(metin)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct KagitVeSure: View {
    let islem: BakimIslemi

    var body: some View {
        if islem.kagit != nil || islem.sure != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let kagit = islem.kagit {
                    Label(kagit, systemImage: "doc")
                }
                if let sure = islem.sure {
                    Label(sure, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct AdimListesi: View {
    let adimlar: [String]

    var body: some View {
        DisclosureGroup("Adımlar") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(adimlar.enumerated()), id: \.offset) { i, adim in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(i + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(adim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.callout)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

// MARK: - Genel işlem kartı

private struct IslemKarti: View {
    @Environment(UygulamaModeli.self) private var model
    let islem: BakimIslemi
    var dugme = "Başlat"
    var ekUyari: String? = nil
    var vurgu: Color? = nil
    /// Aynı karttan başlatılan ikinci işlem (ör. hizalama değerlerini yazdırmak).
    var ikincil: BakimIslemi? = nil
    var ikincilDugme: String? = nil

    @State private var grup: TemizlikGrubu = .tum
    @State private var onaylanacak: BakimIslemi?

    private var seciliGrup: TemizlikGrubu {
        islem.gruplar.contains(grup) ? grup : (islem.gruplar.first ?? .tum)
    }

    private var kapali: Bool {
        model.bakimSuruyor || model.cihazAyarUygulaniyor || model.cihazAdresi == nil
    }

    private var buSuruyor: Bool {
        guard let c = model.bakimCanli, c.suruyor else { return false }
        return c.tur == islem.tur || c.tur == ikincil?.tur
    }

    private func onayMesaji(_ i: BakimIslemi) -> String {
        var parcalar: [String] = []
        if i.murekkep == .yok && i.kagit == nil {
            parcalar.append(i.ozet)
        } else {
            parcalar.append(i.murekkep.ad + ".")
        }
        if i.gruplar.count > 1 { parcalar.append("Grup: \(seciliGrup.ad).") }
        if let k = i.kagit { parcalar.append("Arka tepsiye koyun: \(k).") }
        if i.tur == islem.tur, let ekUyari { parcalar.append(ekUyari) }
        return parcalar.joined(separator: "\n")
    }

    var body: some View {
        Kart(baslik: islem.ad, simge: islem.simge, vurgu: vurgu) {
            DurumRozeti(metin: islem.murekkep.ad, renk: Tema.renk(islem.murekkep))
        } icerik: {
            Text(islem.ozet)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let ekUyari {
                Label(ekUyari, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            KagitVeSure(islem: islem)

            if islem.gruplar.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Grup", selection: $grup) {
                        ForEach(islem.gruplar) { g in
                            Text(g.kisaAd).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(seciliGrup.ad)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !islem.adimlar.isEmpty {
                AdimListesi(adimlar: islem.adimlar)
            }

            Spacer(minLength: 0)

            if let ikincil, let ikincilDugme {
                Button {
                    onaylanacak = ikincil
                } label: {
                    Label(ikincilDugme, systemImage: ikincil.simge)
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .disabled(kapali)
            }

            HStack(spacing: 8) {
                if buSuruyor { SuruyorEtiketi() }
                Spacer(minLength: 8)
                Button(dugme) { onaylanacak = islem }
                    .buttonStyle(.borderedProminent)
                    .tint(vurgu)
                    .disabled(kapali)
            }
        }
        .confirmationDialog(onaylanacak?.onay ?? "",
                            isPresented: Binding(get: { onaylanacak != nil }, set: { if !$0 { onaylanacak = nil } }),
                            titleVisibility: .visible,
                            presenting: onaylanacak) { i in
            let ana = i.tur == islem.tur
            Button(ana ? dugme : (ikincilDugme ?? "Yazdır"), role: (ana && vurgu != nil) ? .destructive : nil) {
                gonder(i)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { i in
            Text(onayMesaji(i))
        }
    }

    private func gonder(_ i: BakimIslemi) {
        let g = seciliGrup
        Task { await model.bakimBaslat(i, grup: g) }
    }
}

// MARK: - Silindir temizliği (iki adım)

private enum AdimDurumu {
    case bekliyor, sirada, suruyor, bitti
}

private struct AdimSatiri: View {
    let no: Int
    let metin: String
    let durum: AdimDurumu

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                switch durum {
                case .bitti:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .suruyor:
                    ProgressView().controlSize(.small)
                case .sirada:
                    Image(systemName: "\(no).circle.fill").foregroundStyle(.tint)
                case .bekliyor:
                    Image(systemName: "\(no).circle").foregroundStyle(.secondary)
                }
            }
            .frame(width: 18)
            Text(metin)
                .font(.callout)
                .foregroundStyle(durum == .bekliyor || durum == .bitti ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SilindirKarti: View {
    @Environment(UygulamaModeli.self) private var model
    private let adim1 = BakimIslemi.tur(.silindir)
    private let adim2 = BakimIslemi.tur(.silindirKagitli)

    @State private var onayAcik = false

    /// Adımların durumu, son bakım işleminden türetilir (bölüm değişse de kaybolmaz).
    private var durumlar: (bir: AdimDurumu, iki: AdimDurumu) {
        guard let c = model.bakimCanli else { return (.sirada, .bekliyor) }
        switch c.tur {
        case .silindir where c.suruyor: return (.suruyor, .bekliyor)
        case .silindir where c.asama == .bitti: return (.bitti, .sirada)
        case .silindirKagitli where c.suruyor: return (.bitti, .suruyor)
        default: return (.sirada, .bekliyor)
        }
    }

    private var kapali: Bool {
        model.bakimSuruyor || model.cihazAyarUygulaniyor || model.cihazAdresi == nil
    }

    var body: some View {
        let d = durumlar
        let ikinci = d.bir != .sirada
        let dugme = ikinci ? "2. adımı başlat" : "1. adımı başlat"
        Kart(baslik: adim1.ad, simge: adim1.simge) {
            DurumRozeti(metin: adim1.murekkep.ad, renk: Tema.renk(adim1.murekkep))
        } icerik: {
            Text(adim1.ozet)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            KagitVeSure(islem: adim1)

            VStack(alignment: .leading, spacing: 8) {
                AdimSatiri(no: 1, metin: adim1.adimlar[0], durum: d.bir)
                AdimSatiri(no: 2, metin: adim1.adimlar[1], durum: d.iki)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if d.bir == .suruyor || d.iki == .suruyor {
                    SuruyorEtiketi()
                } else if ikinci {
                    Button("Baştan başla") { model.bakimSonucunuKapat() }
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
                Spacer(minLength: 8)
                Button(dugme) { onayAcik = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(kapali)
            }
        }
        .confirmationDialog(ikinci ? adim2.onay : adim1.onay, isPresented: $onayAcik, titleVisibility: .visible) {
            Button(dugme) { gonder(ikinci ? adim2 : adim1) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(ikinci ? "Arka tepside üç sayfa A4 düz kağıt olmalı. Kağıtlar silindirleri silerek çıkar."
                        : "Arka tepside kağıt olmamalı. Silindirler kağıtsız, yaklaşık 1,5 dakika döner.")
        }
    }

    private func gonder(_ islem: BakimIslemi) {
        Task { await model.bakimBaslat(islem) }
    }
}

// MARK: - Cihaz ayarları

private struct AyarDegisikligi: Identifiable {
    let id: String
    let aciklama: String
    let xml: String
    let dogrula: @Sendable (IVEC.CihazAyarlari) -> Bool
}

private struct AyarSatiri<Kontrol: View>: View {
    let baslik: String
    var aciklama: String? = nil
    /// Değiştirildiyse yazıcıdaki mevcut değer.
    var yazicida: String? = nil
    @ViewBuilder var kontrol: () -> Kontrol

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(baslik)
                if let aciklama {
                    Text(aciklama)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let yazicida {
                    Text("Yazıcıda şu an: \(yazicida)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 12)
            kontrol()
        }
    }
}

private func acikKapali(_ b: Bool?) -> String {
    guard let b else { return "—" }
    return b ? "Açık" : "Kapalı"
}

private func kapanmaSuresiAdi(_ dakika: Int) -> String {
    dakika % 60 == 0 ? "\(dakika / 60) saat" : "\(dakika) dakika"
}

private func saatMetni(_ hhmm: String?) -> String {
    guard let h = hhmm, h.count == 4 else { return "—" }
    return "\(h.prefix(2)):\(h.suffix(2))"
}

private func sessizModAdi(_ mod: String?, _ bas: String?, _ bit: String?) -> String {
    switch mod {
    case "ON": return "Açık"
    case "OFF": return "Kapalı"
    case "time": return "Zamanlı (\(saatMetni(bas))–\(saatMetni(bit)))"
    default: return mod ?? "—"
    }
}

/// "2100" → bugünün 21:00'i.
private func saatTarihi(_ hhmm: String?) -> Date {
    let s = hhmm ?? "0000"
    let saat = Int(s.prefix(2)) ?? 0
    let dakika = Int(s.dropFirst(2).prefix(2)) ?? 0
    return Calendar.current.date(bySettingHour: min(max(saat, 0), 23), minute: min(max(dakika, 0), 59),
                                 second: 0, of: Date()) ?? Date()
}

/// Tarih → "HHMM" (yazıcının beklediği biçim).
private func hhmmBicimi(_ t: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: t)
    return String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0)
}

private struct CihazAyarlariKarti: View {
    @Environment(UygulamaModeli.self) private var model

    /// Ekranda düzenlenen değerler; yazıcıdan okunan değerlerle başlar.
    @State private var taslak = IVEC.CihazAyarlari()
    @State private var onayAcik = false
    @State private var uygulaniyor = false

    var body: some View {
        Kart(baslik: "Cihaz ayarları", simge: "gearshape.2") {
            if model.cihazAyarOkunuyor && !uygulaniyor {
                ProgressView().controlSize(.small)
            }
        } icerik: {
            if let mevcut = model.cihazAyarlari {
                ayarFormu(mevcut)
            } else if let hata = model.cihazAyarHatasi, !model.cihazAyarOkunuyor {
                okumaHatasi(hata)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Yazıcının ayarları okunuyor…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: model.cihazAdresi?.host) { await model.cihazAyarlariniOku() }
        .onAppear { if let m = model.cihazAyarlari { taslak = m } }
        .onChange(of: model.cihazAyarlari) { _, yeni in
            if !uygulaniyor, let yeni { taslak = yeni }
        }
        .confirmationDialog("Ayarlar yazıcıya uygulansın mı?", isPresented: $onayAcik, titleVisibility: .visible) {
            Button("Yazıcıya uygula") { uygula() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(onayMetni)
        }
    }

    // MARK: Görünüm parçaları

    private func okumaHatasi(_ metin: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Yazıcının ayarları okunamadı. \(metin)", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Yeniden dene") { Task { await model.cihazAyarlariniOku() } }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func ayarFormu(_ mevcut: IVEC.CihazAyarlari) -> some View {
        let bekleyenler = degisiklikler(mevcut)
        VStack(alignment: .leading, spacing: 12) {
            if mevcut.otomatikAcilma != nil {
                AyarSatiri(baslik: "Otomatik açılma",
                           aciklama: "USB kablosuyla bağlıyken baskı gelince yazıcı kendiliğinden açılır. Wi‑Fi'da çalışmaz.",
                           yazicida: taslak.otomatikAcilma != mevcut.otomatikAcilma ? acikKapali(mevcut.otomatikAcilma) : nil) {
                    Toggle("Otomatik açılma", isOn: bagla(\.otomatikAcilma))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Divider()
            }

            if mevcut.otomatikKapanma != nil {
                AyarSatiri(baslik: "Otomatik kapanma",
                           aciklama: "Boşta kalınca yazıcı kendini kapatır.",
                           yazicida: kapanmaDegisti(mevcut) ? kapanmaAdi(mevcut) : nil) {
                    HStack(spacing: 10) {
                        if taslak.otomatikKapanma == true {
                            Picker("Kapanma süresi", selection: kapanmaSuresi) {
                                ForEach(kapanmaSecenekleri(mevcut), id: \.self) { d in
                                    Text(kapanmaSuresiAdi(d)).tag(d)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        Toggle("Otomatik kapanma", isOn: bagla(\.otomatikKapanma))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                Divider()
            }

            if mevcut.sessizMod != nil {
                AyarSatiri(baslik: "Sessiz mod",
                           aciklama: "Yazıcı daha sessiz ama daha yavaş çalışır.",
                           yazicida: sessizDegisti(mevcut)
                               ? sessizModAdi(mevcut.sessizMod, mevcut.sessizBaslangic, mevcut.sessizBitis) : nil) {
                    Picker("Sessiz mod", selection: sessizMod) {
                        Text("Kapalı").tag("OFF")
                        Text("Açık").tag("ON")
                        Text("Zamanlı").tag("time")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if taslak.sessizMod == "time" {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Text("Başlangıç").foregroundStyle(.secondary)
                        DatePicker("Başlangıç", selection: saatBagla(\.sessizBaslangic), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("Bitiş").foregroundStyle(.secondary)
                        DatePicker("Bitiş", selection: saatBagla(\.sessizBitis), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .font(.callout)
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                }
                Divider()
            }

            if mevcut.murekkepBildirimi != nil {
                AyarSatiri(baslik: "Kalan mürekkep bildirimi",
                           aciklama: "Mürekkep azalınca yazıcı uyarır. Kapalıyken tankları gözle takip edersiniz.",
                           yazicida: taslak.murekkepBildirimi != mevcut.murekkepBildirimi
                               ? acikKapali(mevcut.murekkepBildirimi) : nil) {
                    Toggle("Kalan mürekkep bildirimi", isOn: bagla(\.murekkepBildirimi))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                if taslak.murekkepBildirimi == true && mevcut.murekkepBildirimi == false {
                    Label("Açmadan önce tüm tankları üst çizgiye kadar doldurun (Canon'un şartı); yoksa uyarılar gerçek seviyeyle uyuşmaz.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let hata = model.cihazAyarHatasi {
                HStack(spacing: 8) {
                    Label("Son okuma başarısız: \(hata)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Yeniden dene") { Task { await model.cihazAyarlariniOku() } }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            HStack(spacing: 8) {
                if uygulaniyor {
                    SuruyorEtiketi(metin: "Uygulanıyor…")
                } else if !bekleyenler.isEmpty {
                    Text(bekleyenler.count == 1 ? "1 değişiklik" : "\(bekleyenler.count) değişiklik")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Geri al") { taslak = mevcut }
                    .buttonStyle(.bordered)
                    .disabled(bekleyenler.isEmpty || uygulaniyor)
                Button("Yazıcıya uygula") { onayAcik = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(bekleyenler.isEmpty || uygulaniyor || model.bakimSuruyor || model.cihazAdresi == nil)
            }
        }
        .disabled(uygulaniyor)
    }

    // MARK: Bağlamalar

    private func bagla(_ yol: WritableKeyPath<IVEC.CihazAyarlari, Bool?>) -> Binding<Bool> {
        Binding(get: { taslak[keyPath: yol] ?? false }, set: { taslak[keyPath: yol] = $0 })
    }

    private func saatBagla(_ yol: WritableKeyPath<IVEC.CihazAyarlari, String?>) -> Binding<Date> {
        Binding(get: { saatTarihi(taslak[keyPath: yol]) }, set: { taslak[keyPath: yol] = hhmmBicimi($0) })
    }

    private var kapanmaSuresi: Binding<Int> {
        Binding(get: { taslak.kapanmaDakika ?? 240 }, set: { taslak.kapanmaDakika = $0 })
    }

    private var sessizMod: Binding<String> {
        Binding(get: { taslak.sessizMod ?? "OFF" }, set: { taslak.sessizMod = $0 })
    }

    /// Yazıcının süreleri; yazıcıdaki değer listede yoksa o da eklenir.
    private func kapanmaSecenekleri(_ m: IVEC.CihazAyarlari) -> [Int] {
        var s = IVEC.Ayar.kapanmaSureleri
        for d in [m.kapanmaDakika, taslak.kapanmaDakika].compactMap({ $0 }) where !s.contains(d) { s.append(d) }
        return s.sorted()
    }

    // MARK: Değişiklikler

    private func kapanmaAdi(_ a: IVEC.CihazAyarlari) -> String {
        guard let acik = a.otomatikKapanma else { return "—" }
        guard acik else { return "Kapalı" }
        return a.kapanmaDakika.map { "\(kapanmaSuresiAdi($0)) sonra" } ?? "Açık"
    }

    private func kapanmaDegisti(_ m: IVEC.CihazAyarlari) -> Bool {
        taslak.otomatikKapanma != m.otomatikKapanma
            || (taslak.otomatikKapanma == true && taslak.kapanmaDakika != m.kapanmaDakika)
    }

    private func sessizDegisti(_ m: IVEC.CihazAyarlari) -> Bool {
        taslak.sessizMod != m.sessizMod
            || (taslak.sessizMod == "time" && (taslak.sessizBaslangic != m.sessizBaslangic || taslak.sessizBitis != m.sessizBitis))
    }

    /// Her değişiklik ayrı bir iş olarak gönderilir ve tek tek doğrulanır.
    private func degisiklikler(_ m: IVEC.CihazAyarlari) -> [AyarDegisikligi] {
        let t = taslak
        var liste: [AyarDegisikligi] = []
        if let v = t.otomatikAcilma, v != m.otomatikAcilma {
            liste.append(AyarDegisikligi(id: "acilma", aciklama: "Otomatik açılma: \(acikKapali(v))",
                                         xml: IVEC.Ayar.otomatikAcilma(v),
                                         dogrula: { $0.otomatikAcilma == v }))
        }
        if let acik = t.otomatikKapanma, kapanmaDegisti(m) {
            let dk = t.kapanmaDakika ?? m.kapanmaDakika ?? 240
            liste.append(AyarDegisikligi(id: "kapanma",
                                         aciklama: "Otomatik kapanma: \(acik ? "\(kapanmaSuresiAdi(dk)) sonra" : "Kapalı")",
                                         xml: IVEC.Ayar.otomatikKapanma(acik: acik, dakika: dk),
                                         dogrula: { $0.otomatikKapanma == acik && (!acik || $0.kapanmaDakika == dk) }))
        }
        if let mod = t.sessizMod, sessizDegisti(m) {
            let bas = t.sessizBaslangic ?? m.sessizBaslangic ?? "2100"
            let bit = t.sessizBitis ?? m.sessizBitis ?? "0700"
            liste.append(AyarDegisikligi(id: "sessiz", aciklama: "Sessiz mod: \(sessizModAdi(mod, bas, bit))",
                                         xml: IVEC.Ayar.sessizMod(mod, baslangic: bas, bitis: bit),
                                         dogrula: { a in
                                             a.sessizMod == mod
                                                 && (mod != "time" || (a.sessizBaslangic == bas && a.sessizBitis == bit))
                                         }))
        }
        if let v = t.murekkepBildirimi, v != m.murekkepBildirimi {
            liste.append(AyarDegisikligi(id: "murekkep", aciklama: "Kalan mürekkep bildirimi: \(acikKapali(v))",
                                         xml: IVEC.Ayar.murekkepBildirimi(v),
                                         dogrula: { $0.murekkepBildirimi == v }))
        }
        return liste
    }

    private var onayMetni: String {
        guard let m = model.cihazAyarlari else { return "" }
        var metin = degisiklikler(m).map(\.aciklama).joined(separator: "\n")
        if taslak.murekkepBildirimi == true && m.murekkepBildirimi == false {
            metin += "\n\nÖnce tüm tankları üst çizgiye kadar doldurun; yoksa uyarılar gerçek seviyeyle uyuşmaz."
        }
        return metin
    }

    private func uygula() {
        guard let mevcut = model.cihazAyarlari else { return }
        let liste = degisiklikler(mevcut)
        guard !liste.isEmpty else { return }
        uygulaniyor = true
        Task {
            for d in liste {
                guard await model.cihazAyariUygula(xml: d.xml, dogrula: d.dogrula, aciklama: d.aciklama) else { break }
            }
            uygulaniyor = false
            if let yeni = model.cihazAyarlari { taslak = yeni }
        }
    }
}
