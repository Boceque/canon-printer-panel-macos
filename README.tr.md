# Canon Yazıcı Paneli — Mac için (Canon PIXMA G3010)

🇬🇧 [English](README.md)

**Canon G3010 için macOS kontrol paneli.** Yazıcının gerçek durumunu gösterir, baskı ayarlarını tüm uygulamalar için sabitler (ör. "her zaman taslak"), bakım işlemlerini (temizlik, püskürtme denetimi, kafa hizalama…) Mac'ten çalıştırır.

Canon'un Mac'teki araçları G3010'da bakım komutlarını gönderir ama yazıcı bunları yok sayar. Bu uygulama yazıcıyla kendi dilinde (IVEC/CHMP) konuşur, bu yüzden bakım gerçekten çalışır.

![Genel Bakış](Belgeler/ekran-genel-bakis.png)

> Canon ile bir ilişkisi yoktur; resmî bir Canon ürünü değildir. Yalnızca **Canon G3010** ile denendi.

## Neler yapar

- **Genel Bakış:** Yazıcının kendi durumunu ve Mac'teki kuyruğu yan yana gösterir. Canon'un Türkçe hata metinlerini (ör. "Kağıt yok… SÜRDÜR düğmesine basın") kullanır. Kuyruk takılırsa tek tıkla, parola sormadan sürdürür.
- **Baskı ayarlarını sabitleme:** Kalite, siyah-beyaz, kağıt türü, kağıt boyutu, parlaklık ve yarı ton ayrı ayrı kilitlenir. Sabitleme üç katmanda çalışır:
  1. Yazıcının varsayılan ayarları (Chrome, `lp` ve "Saptanmış Ayarlar" için)
  2. macOS yazdırma penceresinin "Son Kullanılan Ayarlar"ı
  3. **Kesin mod:** her iş bir an bekletilir, sabit ayarlar yazılır, sonra bırakılır. Hiçbir uygulama ayarı ezemez.

  Sabitleme kaldırılınca her şey eski hâline döner.
- **Hazır ayarlar:** Taslak · Siyah-beyaz, Taslak · Renkli, Ekstra taslak, Standart, Fotoğraf kağıdı; kendi ayarlarınızı da kaydedebilirsiniz.
- **Hızlı Yazdır:** Sürükle-bırak; kopya, sayfa aralığı, yön, sayfaya sığdır, yaprak başına sayfa seçenekleri. Elle çift taraf sihirbazı da var (G3010'da otomatik çift taraf yok).
- **Kuyruk:** İşleri iptal etme, bekletme, sürdürme, yeniden basma.
- **Bakım:**
  - Püskürtme ucu denetimi
  - Temizlik (tümü / siyah / renkli), yoğun temizlik, sistem temizliği
  - Silindir ve alt plaka temizliği
  - Kafa hizalama, hizalama değerlerini yazdırma
  - Mürekkep sayacını sıfırlama

  İşlem sürerken yazıcının canlı durumu görünür ve **Durdur** ile iptal edilebilir.

  ![Bakım](Belgeler/ekran-bakim.png)
- **Cihaz ayarları:** Otomatik açılma (yalnız USB bağlantıda), otomatik kapanma süresi, sessiz mod (zamanlı), kalan mürekkep bildirimi.
- **Menü çubuğu:** Yazıcı durumunu gösterir. Buradan hazır ayar sabitlenebilir, sabitleme kaldırılabilir, takılan kuyruk sürdürülebilir, süren iş iptal edilebilir.
- **Chrome eklentisi:** Chrome kendi yazdırma penceresinde renk ve çözünürlüğü kendisi gönderip sabit ayarları ezer. Eklenti, yazdırma penceresine **"Canon G3010 · Sabit ayarlar"** hedefini ekler; bu hedeften basılan iş her zaman sabit ayarlarla çıkar.

## Gereksinimler

- macOS 26 (Tahoe) veya üstü. Hazır sürüm Apple Silicon (arm64) içindir.
- Canon'un macOS yazıcı sürücüsü kurulu olmalı, yazıcı **Sistem Ayarları › Yazıcılar ve Tarayıcılar**'a eklenmiş olmalı.
- Bakım ve yazıcı durumu için yazıcı ile Mac aynı ağda olmalı.

## Kurulum

### A) Hazır sürüm (önerilen)

1. [Releases](../../releases) sayfasından `Yazici-Paneli-….zip` dosyasını indirin, çift tıklayıp açın.
2. **Yazıcı Paneli.app**'i **Uygulamalar** klasörüne sürükleyin.
3. Uygulama Apple tarafından noter onaylı olmadığı için ilk açılışta macOS "açılamıyor" der:
   - **Sistem Ayarları › Gizlilik ve Güvenlik**'e girin, aşağıdaki "Yazıcı Paneli engellendi" satırında **Yine de Aç**'a tıklayın.
   - Ya da Terminal'de şunu çalıştırın:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/Yazıcı Paneli.app"
     ```
4. macOS yerel ağdaki aygıtlara bağlanma izni sorarsa **İzin Ver** deyin. Yazıcının durumu ve bakım için gerekir.

### B) Kaynaktan derleme

Xcode gerekmez, Komut Satırı Araçları yeter:

```bash
xcode-select --install
git clone https://github.com/Boceque/canon-printer-panel-macos.git
cd canon-printer-panel-macos
./derle.sh
```

`derle.sh` sırasıyla şunları yapar:
1. Derler.
2. `.app` paketini oluşturur ve yerel olarak imzalar.
3. `/Applications`'a kurar.
4. Chrome köprüsünü kurar.

Yalnızca proje klasöründe denemek için `./derle.sh --kurma` kullanın.

### Chrome eklentisi (isteğe bağlı)

Uygulama ilk açılışta Chrome köprüsünü kendisi kurar ve eklenti dosyalarını `~/Library/Application Support/Yazıcı Paneli/Chrome Eklentisi` klasörüne kopyalar. Sonrası:

1. Chrome'da adres çubuğuna `chrome://extensions` yazın.
2. Sağ üstten **Geliştirici modu**'nu açın.
3. **Paketlenmemiş öğe yükle**'ye tıklayın. Açılan pencerede ⇧⌘G'ye basın, şu yolu yapıştırın, Return'e basın ve **Seç**'e tıklayın:
   ```
   ~/Library/Application Support/Yazıcı Paneli/Chrome Eklentisi
   ```
4. Yapboz simgesinden eklentiyi araç çubuğuna iğneleyin.
5. Yazdırırken hedef olarak **Canon G3010 · Sabit ayarlar**'ı seçin. Chrome bu seçimi hatırlar.

Uygulama güncellenince `chrome://extensions`'ta eklentinin ↻ (yeniden yükle) düğmesine basın.

Chrome dışında Chrome Beta/Canary, Chromium, Brave ve Edge de desteklenir.

## Nasıl çalışır (teknik not)

- **Kuyruk ve ayarlar:** `libcups` (IPP) ve `lpadmin` kullanılır. Yazıcı varsayılanını değiştirmek ve kuyruğu sürdürmek, macOS'ta yönetici (admin) hesaplarında parola istemez.
- **Kalite:** Canon'un "Taslak" ayarı sürücüde `CNIJPrintQuality=15` ve 300 dpi demektir. Fotoğraf kağıdında taslak kalite yazıcıda hata verdiği için, o kağıtlarda kaliteye dokunulmaz.
- **Bakım:** Canon'un Linux sürücüsündeki biçimle yazıcıya doğrudan komut gönderilir:
  - Bakım işleri: 9100 portuna IVEC XML işi (`StartJob › SetJobConfiguration › Cleaning/TestPrint/RollerCleaning › EndJob`).
  - Durum, iptal (`CancelJob`) ve mürekkep sayacı (`VendorCmd ResetCounter`): 80 portundaki CHMP kanalı.
- **Teşhis:** Arayüz açmadan durumu yazdırır:
  ```bash
  "/Applications/Yazıcı Paneli.app/Contents/MacOS/YaziciPaneli" --tani            # kuyruk, işler, PPD, sabitleme
  "/Applications/Yazıcı Paneli.app/Contents/MacOS/YaziciPaneli" --tani --cihaz    # yazıcının kendi durumu ve ayarları
  "/Applications/Yazıcı Paneli.app/Contents/MacOS/YaziciPaneli" --tani --gunluk   # son günlük satırları
  ```

## Kaldırma

1. Uygulamada sabitleme açıksa **Kaldır**'a basın. Yazıcı ve pencere ayarları eski hâline döner; kesin mod açıksa arka plan görevlisi de kapanır.
2. **Yazıcı Paneli.app**'i Çöp Sepeti'ne taşıyın.
3. İsterseniz şunları da silin:
   - `~/Library/Application Support/Yazıcı Paneli` (ayarlar ve günlük)
   - Chrome'daki eklenti
   - `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.caglar.yazicipaneli.json`

## Bilinen sınırlar

- G3010 mürekkep seviyesini ölçmez; tankları gözle kontrol edin.
- Otomatik açılma yalnızca USB kabloyla çalışır, Wi‑Fi'da çalışmaz.
- Yoğun temizlik ve sistem temizliği için yazıcının komutu kabul ettiği doğrulandı. Mürekkep harcamamak için sonuna kadar çalıştırılmadı.
- Temizlik iptal edilse bile yazıcı durana kadar (birkaç saniye) biraz mürekkep harcanabilir.
- Uygulama Apple'a kayıtlı bir geliştirici imzası taşımaz (bkz. Kurulum › 3. adım).

## Lisans

[MIT](LICENSE) — serbestçe kullanılabilir, değiştirilebilir, paylaşılabilir. Olduğu gibi, garantisiz verilir: bakım işlemleri mürekkep harcar, kullanım sorumluluğu size aittir.
