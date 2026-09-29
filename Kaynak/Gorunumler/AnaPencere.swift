import SwiftUI

struct AnaPencere: View {
    @Environment(UygulamaModeli.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            KenarCubugu()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            icerik
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let mesgul = model.mesgul {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(mesgul).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await model.yenile(cihazDahil: true) }
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
                .help("Durumu yenile (⌘R)")
            }
        }
        .overlay(alignment: .bottom) {
            if let b = model.bildirim {
                BildirimBalonu(bildirim: b)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { model.bildirim = nil }
            }
        }
        .animation(.snappy, value: model.bildirim)
    }

    @ViewBuilder private var icerik: some View {
        switch model.secilenBolum {
        case .genelBakis: GenelBakisGorunumu()
        case .baskiAyarlari: BaskiAyarlariGorunumu()
        case .hazirAyarlar: HazirAyarlarGorunumu()
        case .hizliYazdir: HizliYazdirGorunumu()
        case .kuyruk: KuyrukGorunumu()
        case .bakim: BakimGorunumu()
        case .bilgi: BilgiGorunumu()
        case .tercihler: TercihlerGorunumu()
        }
    }
}

struct KenarCubugu: View {
    @Environment(UygulamaModeli.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { Optional(model.secilenBolum) }, set: { if let b = $0 { model.secilenBolum = b } })) {
            Section {
                ForEach([Bolum.genelBakis, .baskiAyarlari, .hazirAyarlar, .hizliYazdir, .kuyruk, .bakim]) { b in
                    satir(b)
                }
            }
            Section {
                satir(.bilgi)
                satir(.tercihler)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { baslik }
        .safeAreaInset(edge: .bottom) { sabitlemeAlani }
    }

    private func satir(_ b: Bolum) -> some View {
        Label(b.ad, systemImage: b.simge)
            .badge(rozet(b))
            .tag(b)
    }

    private func rozet(_ b: Bolum) -> Text? {
        switch b {
        case .kuyruk:
            return model.bekleyenIsSayisi > 0 ? Text("\(model.bekleyenIsSayisi)") : nil
        case .genelBakis:
            return model.durumOzeti.seviye >= .uyari ? Text("!") : nil
        default:
            return nil
        }
    }

    private var baslik: some View {
        let ozet = model.durumOzeti
        return HStack(spacing: 10) {
            YaziciResmi(boyut: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.katalog?.model.replacingOccurrences(of: "G3000", with: "G3010") ?? model.kuyrukAdi)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(Tema.renk(ozet.seviye)).frame(width: 7, height: 7)
                    Text(ozet.seviye == .hazir ? "Hazır" : ozet.baslik)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var sabitlemeAlani: some View {
        Button {
            model.secilenBolum = .baskiAyarlari
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.sabitleme.etkin ? "lock.fill" : "lock.open")
                    .foregroundStyle(model.sabitleme.etkin ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.sabitleme.etkin ? (model.sabitleme.kesinMod ? "Sabit · kesin mod" : "Sabit ayarlar") : "Sabitleme kapalı")
                        .font(.caption.weight(.semibold))
                    if model.sabitleme.etkin {
                        Text(model.sabitlemeOzeti).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(KartZemini(vurgu: model.sabitleme.etkin ? .accentColor : nil))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .padding(10)
    }
}
