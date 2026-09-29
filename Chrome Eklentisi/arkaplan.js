// Yazıcı Paneli — arka plan (service worker).
// Chrome'un yazdırma penceresine sabit ayarlı Canon hedefini ekler; belgeyi native messaging ile
// Mac uygulamasına yollar. Popup'ın istekleri de buradan geçer (popup kapansa bile iş yarım kalmasın).

const HOST_ADI = "com.caglar.yazicipaneli";
const ULASILAMADI_METNI =
  "Yazıcı Paneli uygulamasına ulaşılamadı. Uygulamayı bir kez açın (Chrome köprüsünü o kurar).";

const EN_BUYUK_BELGE = 60 * 1024 * 1024;
// Chrome eklenti iletisini (JSON) 64 MiB ile sınırlar; base64 PDF'i ~%33 büyütür.
const EN_BUYUK_ILETI = 64 * 1024 * 1024;
// 3'ün katı: her parça ayrı base64'lenip uç uca eklenebilsin diye (arada "=" dolgusu çıkmaz).
const PARCA_BOYU = 0x6000;

const KISA_SURE = 15000;
const AYAR_SURESI = 60000;
const YAZDIRMA_SURESI = 120000;

// Popup'ın gönderebileceği istekler → zaman aşımı.
const PANEL_ISTEKLERI = new Map([
  ["durum", KISA_SURE],
  ["sabitle", AYAR_SURESI],
  ["kaldir", AYAR_SURESI],
  ["kesinMod", AYAR_SURESI],
  ["paneliAc", KISA_SURE],
]);

// Durum değiştiren istekler sırayla çalışır: popup kapanıp yeniden açılınca ikinci bir işlem öncekiyle
// aynı anda başlamasın. Süren işin türü `durum` yanıtında `mesgul` olarak bildirilir (popup düğmeleri kilitler).
const DEGISTIREN = new Set(["sabitle", "kaldir", "kesinMod"]);
let sira = Promise.resolve();
let suren = null;

// MV3 kuralı: dinleyiciler en üst düzeyde ve senkron eklenir.
if (chrome.printerProvider) {
  chrome.printerProvider.onGetPrintersRequested.addListener(yazicilariVer);
  chrome.printerProvider.onGetCapabilityRequested.addListener(yetenekleriVer);
  chrome.printerProvider.onPrintRequested.addListener(isiYazdir);
}
chrome.runtime.onMessage.addListener(paneldenGelen);

// ---------- printerProvider ----------

function yazicilariVer(sonucuVer) {
  const bitir = birKez(sonucuVer);
  hostaSor({ tur: "yazici" }, KISA_SURE)
    .then((yanit) => {
      if (!metinMi(yanit.id)) {
        bitir([]);
        return;
      }
      const yazici = { id: yanit.id, name: metinMi(yanit.ad) ? yanit.ad : "Canon G3010" };
      if (metinMi(yanit.aciklama)) yazici.description = yanit.aciklama;
      bitir([yazici]);
    })
    .catch((hata) => {
      gunlukle("yazıcı listesi", hata);
      bitir([]);
    });
}

function yetenekleriVer(yaziciId, sonucuVer) {
  const bitir = birKez(sonucuVer);
  hostaSor({ tur: "yetenekler" }, KISA_SURE)
    .then((yanit) => {
      const cdd = yanit.cdd;
      bitir(cdd && typeof cdd === "object" && !Array.isArray(cdd) ? cdd : {});
    })
    .catch((hata) => {
      gunlukle("yetenekler", hata);
      bitir({});
    });
}

function isiYazdir(isBilgisi, sonucuVer) {
  const bitir = birKez(sonucuVer);
  yazdirmaSonucu(isBilgisi).then(bitir, (hata) => {
    gunlukle("yazdırma", hata);
    bitir("FAILED");
  });
}

async function yazdirmaSonucu(isBilgisi) {
  const belge = isBilgisi && isBilgisi.document;
  if (!belge || typeof belge.arrayBuffer !== "function") return "INVALID_DATA";
  // Uygulama yalnız PDF basar; CDD'de PDF yoksa Chrome PWG raster yollar.
  if (metinMi(isBilgisi.contentType) && isBilgisi.contentType !== "application/pdf") return "INVALID_DATA";
  if (typeof belge.size === "number" && belge.size > EN_BUYUK_BELGE) return "INVALID_DATA";

  const baytlar = new Uint8Array(await belge.arrayBuffer());
  if (baytlar.length === 0 || baytlar.length > EN_BUYUK_BELGE) return "INVALID_DATA";

  const istek = {
    tur: "yazdir",
    belge: "",
    baslik: typeof isBilgisi.title === "string" ? isBilgisi.title : "",
    bilet: isBilgisi.ticket,
  };
  const base64Uzunlugu = Math.ceil(baytlar.length / 3) * 4;
  if (base64Uzunlugu + new TextEncoder().encode(JSON.stringify(istek)).length > EN_BUYUK_ILETI) {
    gunlukle("yazdırma", "belge Chrome'un ileti sınırını aşıyor (" + baytlar.length + " bayt)");
    return "INVALID_DATA";
  }
  istek.belge = base64Yap(baytlar);
  try {
    await hostaSor(istek, YAZDIRMA_SURESI);
    return "OK";
  } catch (hata) {
    gunlukle("yazdırma", hata);
    return "FAILED";
  }
}

// ---------- popup aktarımı ----------

function paneldenGelen(mesaj, gonderen, yanitla) {
  if (!mesaj || typeof mesaj !== "object" || !("yaziciPaneli" in mesaj)) return false;
  if (!gonderen || gonderen.id !== chrome.runtime.id) return false;

  const bitir = birKez(yanitla);
  const istek = panelIstegiKur(mesaj.yaziciPaneli);
  if (!istek) {
    bitir({ tamam: false, hata: "Bilinmeyen istek." });
    return false;
  }
  const sure = PANEL_ISTEKLERI.get(istek.tur);
  let is;
  if (DEGISTIREN.has(istek.tur)) {
    is = sira
      .then(() => {
        suren = istek.tur;
        return hostaSor(istek, sure);
      })
      .finally(() => {
        suren = null;
      });
    sira = is.catch(() => {}); // başarısız işlem sırayı kilitlemesin
  } else {
    is = hostaSor(istek, sure);
  }
  is.then(
    (yanit) => bitir(istek.tur === "durum" && suren !== null ? { ...yanit, mesgul: suren } : yanit),
    (hata) => bitir({ tamam: false, hata: hata.message, ulasilamadi: hata.ulasilamadi === true })
  );
  return true; // yanıt eşzamansız gelecek
}

// Yalnız bilinen alanları geçir.
function panelIstegiKur(ham) {
  if (!ham || typeof ham !== "object" || !PANEL_ISTEKLERI.has(ham.tur)) return null;
  if (ham.tur === "sabitle") {
    const id = ham.hazirAyarId;
    return metinMi(id) || Number.isFinite(id) ? { tur: "sabitle", hazirAyarId: id } : null;
  }
  if (ham.tur === "kesinMod") {
    return typeof ham.acik === "boolean" ? { tur: "kesinMod", acik: ham.acik } : null;
  }
  return { tur: ham.tur };
}

// ---------- native messaging ----------

// Tek atımlık istek. Yanıt `tamam: true` ise döner; değilse Türkçe iletili Error ile reddeder.
// Host yok / çöktü → hata.ulasilamadi = true.
function hostaSor(istek, sureMs) {
  return new Promise((coz, reddet) => {
    let bitti = false;
    const zamanlayici = setTimeout(
      () => sonlandir(null, hataYap("Yazıcı Paneli zamanında yanıt vermedi.", false)),
      sureMs || KISA_SURE
    );

    function sonlandir(yanit, hata) {
      if (bitti) return;
      bitti = true;
      clearTimeout(zamanlayici);
      if (hata) reddet(hata);
      else coz(yanit);
    }

    let vaat;
    try {
      vaat = chrome.runtime.sendNativeMessage(HOST_ADI, istek);
    } catch (hata) {
      gunlukle("native host", hata);
      sonlandir(null, hataYap(ULASILAMADI_METNI, true));
      return;
    }
    Promise.resolve(vaat).then(
      (yanit) => {
        if (!yanit || typeof yanit !== "object") {
          sonlandir(null, hataYap("Yazıcı Paneli anlaşılmayan bir yanıt verdi.", false));
        } else if (yanit.tamam !== true) {
          const metin = metinMi(yanit.hata) ? yanit.hata : "Yazıcı Paneli isteği yerine getiremedi.";
          sonlandir(null, hataYap(metin, false));
        } else {
          sonlandir(yanit, null);
        }
      },
      (hata) => {
        gunlukle("native host", hata);
        sonlandir(null, hataYap(ULASILAMADI_METNI, true));
      }
    );
  });
}

// ---------- yardımcılar ----------

// Büyük dizide fromCharCode(...dizi) yığın taşırır; parça parça çevir.
function base64Yap(baytlar) {
  const parcalar = [];
  for (let i = 0; i < baytlar.length; i += PARCA_BOYU) {
    const parca = baytlar.subarray(i, i + PARCA_BOYU);
    parcalar.push(btoa(String.fromCharCode.apply(null, parca)));
  }
  return parcalar.join("");
}

// Chrome geri çağrısı her yolda tam bir kez çağrılsın.
function birKez(geriCagri) {
  let cagrildi = false;
  return (deger) => {
    if (cagrildi) return;
    cagrildi = true;
    try {
      geriCagri(deger);
    } catch (hata) {
      gunlukle("geri çağrı", hata);
    }
  };
}

function hataYap(metin, ulasilamadi) {
  const hata = new Error(metin);
  hata.ulasilamadi = ulasilamadi;
  return hata;
}

function metinMi(deger) {
  return typeof deger === "string" && deger.length > 0;
}

function gunlukle(yer, hata) {
  console.warn("[Yazıcı Paneli] " + yer + ":", hata && hata.message ? hata.message : hata);
}
