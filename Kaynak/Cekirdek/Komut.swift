import Foundation

/// Dış komut çalıştırma (lpadmin, launchctl). Engelleyicidir; arka planda çağrılmalı.
enum Komut {
    struct Sonuc: Sendable {
        let kod: Int32
        let cikti: String
        let hata: String
        var basarili: Bool { kod == 0 }
    }

    struct Hata: LocalizedError {
        let aciklama: String
        var errorDescription: String? { aciklama }
    }

    @discardableResult
    static func calistir(_ yol: String, _ argumanlar: [String], zamanAsimi: TimeInterval = 30) -> Sonuc {
        let islem = Process()
        islem.executableURL = URL(fileURLWithPath: yol)
        islem.arguments = argumanlar
        var ortam = ProcessInfo.processInfo.environment
        ortam["PATH"] = "/usr/sbin:/usr/bin:/bin:/sbin"
        islem.environment = ortam
        let cikti = Pipe(), hata = Pipe()
        islem.standardOutput = cikti
        islem.standardError = hata
        islem.standardInput = FileHandle.nullDevice
        do { try islem.run() } catch {
            return Sonuc(kod: -1, cikti: "", hata: error.localizedDescription)
        }
        // Çıktıyı beklerken okumak, dolu boru yüzünden kilitlenmeyi önler.
        let grup = DispatchGroup()
        var ciktiVerisi = Data(), hataVerisi = Data()
        grup.enter()
        DispatchQueue.global().async { ciktiVerisi = cikti.fileHandleForReading.readDataToEndOfFile(); grup.leave() }
        grup.enter()
        DispatchQueue.global().async { hataVerisi = hata.fileHandleForReading.readDataToEndOfFile(); grup.leave() }
        let bitis = Date().addingTimeInterval(zamanAsimi)
        while islem.isRunning && Date() < bitis { usleep(20_000) }
        if islem.isRunning { islem.terminate() }
        islem.waitUntilExit()
        grup.wait()
        return Sonuc(kod: islem.terminationStatus,
                     cikti: String(decoding: ciktiVerisi, as: UTF8.self),
                     hata: String(decoding: hataVerisi, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - lpadmin (bu kullanıcı için parolasız)

    /// `lpadmin -p kuyruk -o ad=deger …`. PPD seçeneklerinde PPD'deki *Default satırını,
    /// `-default` ile biten adlarda sunucu varsayılanını değiştirir.
    static func lpadmin(_ kuyruk: String, _ secenekler: [(String, String)]) throws {
        guard !secenekler.isEmpty else { return }
        var arg = ["-p", kuyruk]
        for (ad, deger) in secenekler { arg += ["-o", "\(ad)=\(deger)"] }
        let s = calistir("/usr/sbin/lpadmin", arg)
        if !s.basarili {
            throw Hata(aciklama: "Yazıcı ayarı değiştirilemedi (lpadmin): \(s.hata.isEmpty ? "kod \(s.kod)" : s.hata)")
        }
    }

    /// Kuyruğu sürdürür ve iş kabulünü açar. Printer uygulamasının "Sürdür" düğmesinin
    /// aksine parola istemez (`lpadmin -E`, CUPS-Add-Modify-Printer ile yapılır).
    static func kuyruguSurdur(_ kuyruk: String) throws {
        let s = calistir("/usr/sbin/lpadmin", ["-p", kuyruk, "-E"])
        if !s.basarili {
            throw Hata(aciklama: "Kuyruk sürdürülemedi: \(s.hata.isEmpty ? "kod \(s.kod)" : s.hata)")
        }
    }

    // MARK: - launchctl

    static var kullaniciAlani: String { "gui/\(getuid())" }

    @discardableResult
    static func launchctl(_ argumanlar: [String]) -> Sonuc {
        calistir("/bin/launchctl", argumanlar, zamanAsimi: 15)
    }
}
