import Foundation

// Giriş noktası: aynı program üç kipte çalışır.
//   YaziciPaneli              → arayüz
//   YaziciPaneli --gorevli    → kesin mod için arka plan görevlisi (launchd başlatır)
//   YaziciPaneli --tani       → terminalde teşhis çıktısı
//   YaziciPaneli chrome-extension://…  → Chrome eklentisi köprüsü (native messaging)
//   YaziciPaneli --chrome-kur → köprü manifest'ini ve eklenti dosyalarını kurar
let argumanlar = CommandLine.arguments
if argumanlar.contains(where: { $0.hasPrefix("chrome-extension://") }) {
    // Chrome eklentisi native messaging ile çağırdı: tek istek, tek yanıt.
    Gunluk.varsayilanKaynak = "chrome"
    ChromeKoprusu.calistir()
} else if argumanlar.contains("--chrome-kur") {
    print("Chrome köprüsü kuruldu: \(ChromeKoprusu.kur()) tarayıcı")
    exit(0)
} else if argumanlar.contains("--gorevli") {
    Gunluk.varsayilanKaynak = "görevli"
    Gorevli.calistir()
} else if argumanlar.contains("--tani") {
    Tani.calistir(argumanlar)
    exit(0)
} else {
    YaziciPaneliUygulamasi.main()
}
