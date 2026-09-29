import AppKit
import SwiftUI

// MARK: - Tema

enum Tema {
    static let kose: CGFloat = 12
    static let bosluk: CGFloat = 16
    static let sayfaGenisligi: CGFloat = 1000

    static func renk(_ s: DurumSeviyesi) -> Color {
        switch s {
        case .hazir: return .green
        case .calisiyor: return .blue
        case .bilinmiyor: return .secondary
        case .uyari: return .orange
        case .hata: return .red
        }
    }

    static func simge(_ s: DurumSeviyesi) -> String {
        switch s {
        case .hazir: return "checkmark.circle.fill"
        case .calisiyor: return "printer.dotmatrix.fill"
        case .bilinmiyor: return "questionmark.circle.fill"
        case .uyari: return "exclamationmark.triangle.fill"
        case .hata: return "xmark.octagon.fill"
        }
    }

    static func renk(_ o: Onem) -> Color {
        switch o {
        case .bilgi: return .secondary
        case .uyari: return .orange
        case .hata: return .red
        }
    }

    static func renk(_ d: IsDurumu) -> Color {
        switch d {
        case .yazdiriliyor: return .blue
        case .sirada: return .secondary
        case .beklemede: return .orange
        case .durdu, .hataIleBitti: return .red
        case .iptalEdildi: return .gray
        case .tamamlandi: return .green
        case .bilinmiyor: return .secondary
        }
    }

    static func simge(_ d: IsDurumu) -> String {
        switch d {
        case .yazdiriliyor: return "printer.dotmatrix.fill"
        case .sirada: return "clock"
        case .beklemede: return "pause.circle.fill"
        case .durdu: return "exclamationmark.circle.fill"
        case .hataIleBitti: return "xmark.circle.fill"
        case .iptalEdildi: return "minus.circle.fill"
        case .tamamlandi: return "checkmark.circle.fill"
        case .bilinmiyor: return "questionmark.circle"
        }
    }

    static func renk(_ m: MurekkepKullanimi) -> Color {
        switch m {
        case .yok: return .secondary
        case .az: return .green
        case .orta: return .yellow
        case .cok: return .orange
        case .cokFazla: return .red
        }
    }
}

// MARK: - Sayfa iskeleti

/// Her bölümün kaydırılabilir gövdesi: başlık + içerik, okunur genişlikte.
struct Sayfa<Icerik: View>: View {
    let baslik: String
    var altBaslik: String? = nil
    var simge: String? = nil
    @ViewBuilder var icerik: () -> Icerik

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tema.bosluk) {
                SayfaBasligi(baslik: baslik, altBaslik: altBaslik, simge: simge)
                icerik()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: Tema.sayfaGenisligi, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}

struct SayfaBasligi: View {
    let baslik: String
    var altBaslik: String? = nil
    var simge: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let simge {
                Image(systemName: simge)
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(baslik).font(.largeTitle.weight(.semibold))
                if let altBaslik {
                    Text(altBaslik).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Kart

struct Kart<Aksesuar: View, Icerik: View>: View {
    var baslik: String? = nil
    var simge: String? = nil
    var vurgu: Color? = nil
    @ViewBuilder var aksesuar: () -> Aksesuar
    @ViewBuilder var icerik: () -> Icerik

    init(baslik: String? = nil, simge: String? = nil, vurgu: Color? = nil,
         @ViewBuilder aksesuar: @escaping () -> Aksesuar = { EmptyView() },
         @ViewBuilder icerik: @escaping () -> Icerik) {
        self.baslik = baslik
        self.simge = simge
        self.vurgu = vurgu
        self.aksesuar = aksesuar
        self.icerik = icerik
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if baslik != nil || simge != nil {
                HStack(spacing: 8) {
                    if let simge {
                        Image(systemName: simge)
                            .foregroundStyle(vurgu ?? .accentColor)
                            .frame(width: 18)
                    }
                    if let baslik {
                        Text(baslik).font(.headline)
                    }
                    Spacer(minLength: 8)
                    aksesuar()
                }
            }
            icerik()
        }
        .padding(Tema.bosluk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KartZemini(vurgu: vurgu))
    }
}

struct KartZemini: View {
    var vurgu: Color? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: Tema.kose, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: Tema.kose, style: .continuous)
                    .strokeBorder((vurgu ?? Color.primary).opacity(vurgu == nil ? 0.08 : 0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

// MARK: - Küçük parçalar

struct DurumRozeti: View {
    let metin: String
    var renk: Color = .secondary
    var simge: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let simge { Image(systemName: simge).imageScale(.small) }
            Text(metin).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(renk)
        .background(renk.opacity(0.12), in: Capsule())
    }
}

struct DurumSimgesi: View {
    let seviye: DurumSeviyesi
    var boyut: CGFloat = 16

    var body: some View {
        Image(systemName: Tema.simge(seviye))
            .font(.system(size: boyut, weight: .semibold))
            .foregroundStyle(Tema.renk(seviye))
            .symbolEffect(.pulse, isActive: seviye == .calisiyor)
    }
}

struct IpucuKutusu: View {
    var baslik: String? = nil
    let metin: String
    var simge: String = "info.circle.fill"
    var renk: Color = .blue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: simge).foregroundStyle(renk).font(.body)
            VStack(alignment: .leading, spacing: 3) {
                if let baslik { Text(baslik).font(.callout.weight(.semibold)) }
                Text(metin).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(renk.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct BilgiSatiri: View {
    let etiket: String
    let deger: String
    var kopyalanabilir = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(etiket).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(deger.isEmpty ? "—" : deger)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
            if kopyalanabilir && !deger.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(deger, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Kopyala")
            }
        }
        .font(.callout)
    }
}

/// Göreli mürekkep kullanımı: 5 dilimlik çubuk.
struct MurekkepCubugu: View {
    let oran: Double
    var renk: Color = .accentColor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Double(i) < oran * 5 - 0.01 ? renk : Color.secondary.opacity(0.2))
                    .frame(width: 10, height: 5)
            }
        }
        .accessibilityLabel("Mürekkep kullanımı yüzde \(Int(oran * 100))")
    }
}

/// Ayarın yanında kilit (sabitle) düğmesi.
struct KilitDugmesi: View {
    @Binding var kilitli: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { kilitli.toggle() }
        } label: {
            Image(systemName: kilitli ? "lock.fill" : "lock.open")
                .foregroundStyle(kilitli ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .help(kilitli ? "Bu ayar sabitlenecek" : "Bu ayara dokunulmayacak (sabitlemek için tıklayın)")
    }
}

/// Yazıcının kendi simgesi (Canon sürücüsünden), yoksa SF Symbol.
struct YaziciResmi: View {
    @Environment(UygulamaModeli.self) private var model
    var boyut: CGFloat = 64

    var body: some View {
        Group {
            if let resim = model.yaziciSimgesi {
                Image(nsImage: resim).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "printer.fill").resizable().scaledToFit().foregroundStyle(.secondary).padding(boyut * 0.12)
            }
        }
        .frame(width: boyut, height: boyut)
    }
}

/// Alttan kayan geçici bildirim.
struct BildirimBalonu: View {
    let bildirim: Bildirim

    private var renk: Color {
        switch bildirim.tur {
        case .basari: return .green
        case .hata: return .red
        case .bilgi: return .blue
        }
    }

    private var simge: String {
        switch bildirim.tur {
        case .basari: return "checkmark.circle.fill"
        case .hata: return "exclamationmark.octagon.fill"
        case .bilgi: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: simge).foregroundStyle(renk)
            Text(bildirim.metin).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(renk.opacity(0.35)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

// MARK: - Biçimlendirme

enum Bicim {
    static let goreceli: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .full
        return f
    }()

    static let saat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    static func goreceli(_ d: Date?) -> String {
        guard let d else { return "—" }
        if abs(d.timeIntervalSinceNow) < 5 { return "şimdi" }
        return goreceli.localizedString(for: d, relativeTo: Date())
    }

    static func tarih(_ d: Date?) -> String { d.map { saat.string(from: $0) } ?? "—" }

    static func boyut(kb: Int?) -> String {
        guard let kb else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .file)
    }

    static func sure(_ saniye: TimeInterval?) -> String {
        guard let saniye, saniye > 0 else { return "—" }
        let f = DateComponentsFormatter()
        f.allowedUnits = saniye > 86400 ? [.day, .hour] : [.hour, .minute]
        f.unitsStyle = .full
        f.calendar?.locale = Locale(identifier: "tr_TR")
        var takvim = Calendar.current
        takvim.locale = Locale(identifier: "tr_TR")
        f.calendar = takvim
        return f.string(from: saniye) ?? "—"
    }
}
