import AppKit
import SwiftUI

struct YaziciPaneliUygulamasi: App {
    @NSApplicationDelegateAdaptor(UygulamaTemsilcisi.self) private var temsilci
    @State private var model = UygulamaModeli()

    var body: some Scene {
        Window("Yazıcı Paneli", id: "ana") {
            AnaPencere()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    temsilci.model = model
                    model.baslat()
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .printItem) {}
            CommandMenu("Yazıcı") {
                Button("Yenile") { Task { await model.yenile(cihazDahil: true) } }
                    .keyboardShortcut("r")
                Button("Kuyruğu Sürdür") { Task { await model.kuyruguSurdur() } }
                Divider()
                ForEach(Bolum.allCases.prefix(7)) { b in
                    Button(b.ad) { model.secilenBolum = b }
                        .keyboardShortcut(KeyEquivalent(Character("\((Bolum.allCases.firstIndex(of: b) ?? 0) + 1)")), modifiers: .command)
                }
            }
        }

        MenuBarExtra(isInserted: Binding(get: { model.menuCubugunda }, set: { model.menuCubugunda = $0 })) {
            MenuCubugu()
                .environment(model)
                .onAppear { model.baslat() }
        } label: {
            MenuCubuguEtiketi(seviye: model.durumOzeti.seviye, sabit: model.sabitleme.etkin)
        }
        .menuBarExtraStyle(.window)

        Settings {
            TercihlerGorunumu()
                .environment(model)
                .frame(width: 560, height: 520)
        }
    }
}

/// Menü çubuğundaki simge: yazıcı + durum işareti.
struct MenuCubuguEtiketi: View {
    let seviye: DurumSeviyesi
    let sabit: Bool

    // Menü çubuğu etiketi şablon görsel olarak çizilir; üst üste bindirme görünmez.
    // Bu yüzden her durum ayrı simgeyle gösterilir.
    var body: some View {
        switch seviye {
        case .hata, .uyari: Image(systemName: "exclamationmark.triangle.fill")
        case .calisiyor: Image(systemName: "printer.fill.and.paper.fill")
        default: Image(systemName: sabit ? "printer.fill" : "printer")
        }
    }
}

final class UygulamaTemsilcisi: NSObject, NSApplicationDelegate {
    weak var model: UygulamaModeli?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated {
            guard let model else { return true }
            return !(model.menuCubugunda && model.arkaPlandaCalis)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for w in sender.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil); return false }
        }
        return true
    }
}
