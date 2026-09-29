import AppKit
import SwiftUI

struct MenuCubugu: View {
    @Environment(UygulamaModeli.self) private var model
    /// Menü panelinde diyalog güvenilir değil: iptal onayı satır içinde sorulur.
    @State private var iptalOnayi: Int?
    @Environment(\.openWindow) private var openWindow
    @State private var kaldirmaOnayi = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ust
            if !yukleniyor && !model.durumOzeti.eylemler.isEmpty {
                eylemDugmeleri
            }
            if let isi = model.etkinIs {
                etkinIsSatiri(isi)
            }
            Divider()
            sabitAyarBolumu
            Divider()
            alt
        }
        .padding(14)
        .frame(width: 320)
        .animation(.snappy, value: model.durumOzeti)
        .animation(.snappy, value: kaldirmaOnayi)
        .onDisappear { kaldirmaOnayi = false }
    }

    private var yukleniyor: Bool { model.kuyruk == nil && model.kuyrukHatasi == nil }

    // MARK: Üst

    private var ust: some View {
        let ozet = model.durumOzeti
        return HStack(alignment: .top, spacing: 10) {
            YaziciResmi(boyut: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("Canon G3010").font(.headline)
                if yukleniyor {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Durum okunuyor…").font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    HStack(alignment: .center, spacing: 5) {
                        DurumSimgesi(seviye: ozet.seviye, boyut: 12)
                        Text(ozet.baslik)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let ayrinti = ozet.ayrinti, !ayrinti.isEmpty {
                        Text(ayrinti)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var eylemDugmeleri: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.durumOzeti.eylemler.enumerated()), id: \.element) { sira, e in
                MenuEylemDugmesi(eylem: e, birincil: sira == 0) {
                    Task { await model.eylem(e) }
                }
            }
        }
        .controlSize(.small)
        .disabled(model.mesgul != nil)
    }

    private func etkinIsSatiri(_ isi: YaziciIsi) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Tema.simge(isi.durum))
                .foregroundStyle(Tema.renk(isi.durum))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(isi.ad)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(isMetni(isi))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if iptalOnayi == isi.id {
                Button("Vazgeç") { iptalOnayi = nil }
                    .controlSize(.small)
                Button("İptal et", role: .destructive) {
                    iptalOnayi = nil
                    Task { await model.isIptal(isi.id) }
                }
                .controlSize(.small)
            } else {
                Button("İptal") { iptalOnayi = isi.id }
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func isMetni(_ isi: YaziciIsi) -> String {
        if let s = isi.basilanSayfa, s > 0 { return "\(isi.durum.ad) · \(s) sayfa" }
        return isi.durum.ad
    }

    // MARK: Sabit ayar

    private var sabitAyarBolumu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sabit ayar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

            ForEach(model.hazirAyarlar) { h in
                let secili = model.etkinHazirAyar?.id == h.id
                MenuSatiri(simge: h.simge, metin: h.ad, secili: secili) {
                    guard !secili else { return }
                    Task { await model.hazirAyariSabitle(h) }
                }
            }
            .disabled(model.mesgul != nil)

            if model.sabitleme.etkin && model.etkinHazirAyar == nil {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("Özel: \(model.sabitlemeOzeti)")
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                }
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }

            if model.sabitleme.etkin {
                if kaldirmaOnayi {
                    HStack(spacing: 6) {
                        Text("Özgün ayarlar geri yüklensin mi?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button("Vazgeç") { kaldirmaOnayi = false }
                        Button("Kaldır", role: .destructive) {
                            kaldirmaOnayi = false
                            Task { await model.sabitlemeyiKaldir() }
                        }
                    }
                    .controlSize(.small)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                } else {
                    MenuSatiri(simge: "lock.open", metin: "Sabitlemeyi kaldır") {
                        kaldirmaOnayi = true
                    }
                    .disabled(model.mesgul != nil)
                }
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Kesin mod").font(.callout)
                    Text(model.sabitleme.etkin ? "Her iş sabit ayarlarla basılır" : "Önce bir ayar sabitleyin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Toggle("Kesin mod", isOn: kesinModBaglantisi)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .disabled(!model.sabitleme.etkin || model.mesgul != nil)
        }
    }

    private var kesinModBaglantisi: Binding<Bool> {
        Binding(get: { model.sabitleme.kesinMod },
                set: { yeni in Task { await model.kesinModuAyarla(yeni) } })
    }

    // MARK: Alt

    private var alt: some View {
        HStack(spacing: 8) {
            Button("Paneli aç") {
                openWindow(id: "ana")
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer(minLength: 6)
            if let mesgul = model.mesgul {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text(mesgul)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(model.bekleyenIsSayisi == 0 ? "Kuyruk boş" : "\(model.bekleyenIsSayisi) iş kuyrukta")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button("Çık") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }
}

// MARK: - Yardımcılar

private struct MenuEylemDugmesi: View {
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

/// Düz menü satırı: üzerine gelince hafif vurgulanır.
private struct MenuSatiri: View {
    let simge: String
    let metin: String
    let secili: Bool
    let eylem: () -> Void
    @State private var uzerinde = false
    @Environment(\.isEnabled) private var etkin

    init(simge: String, metin: String, secili: Bool = false, eylem: @escaping () -> Void) {
        self.simge = simge
        self.metin = metin
        self.secili = secili
        self.eylem = eylem
    }

    var body: some View {
        Button(action: eylem) {
            HStack(spacing: 8) {
                Image(systemName: simge)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(metin)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if secili {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                }
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(uzerinde && etkin ? Color.primary.opacity(0.08) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { uzerinde = $0 }
    }
}
