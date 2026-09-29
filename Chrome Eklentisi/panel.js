// Yazıcı Paneli — araç çubuğu paneli.
// İstekler arka plan üzerinden uygulamaya gider (popup kapansa da iş yarım kalmaz).
// Host metinleri yalnız textContent ile basılır.

const BAGLANTI_KESILDI =
  "Eklentinin arka planına ulaşılamadı. Paneli kapatıp yeniden açın; düzelmezse chrome://extensions'ta eklentiyi yeniden yükleyin.";
const SEVIYELER = new Set(["hazir", "calisiyor", "bilinmiyor", "uyari", "hata"]);

// Başka bir panelden başlatılıp arka planda süren işlem (durum yanıtındaki `mesgul`).
const UZAK = "uzak";
const IZLEME_ARALIGI = 1000;
const UZAK_METINLERI = new Map([
  ["sabitle", "Ayar sabitleniyor…"],
  ["kaldir", "Sabitleme kaldırılıyor…"],
  ["kesinMod", "Kesin mod değiştiriliyor…"],
]);

const hal = {
  veri: null, // son `durum` yanıtı
  yukleniyor: true,
  baglantiHatasi: null, // { metin, ulasilamadi } — durum hiç okunamadıysa
  mesgul: null, // süren işlemin anahtarı; UZAK = başka panelden başlatılmış işlem sürüyor
  islemHatasi: null,
  kaldirOnayi: false,
  odakIstegi: null,
};

const ogeler = {
  yaziciAdi: document.getElementById("yazici-adi"),
  durumNoktasi: document.getElementById("durum-noktasi"),
  durumBasligi: document.getElementById("durum-basligi"),
  durumAyrintisi: document.getElementById("durum-ayrintisi"),
  baglantiHatasi: document.getElementById("baglanti-hatasi"),
  sabitBolumu: document.getElementById("sabit-bolumu"),
  kilitSimgesi: document.getElementById("kilit-simgesi"),
  sabitOzeti: document.getElementById("sabit-ozeti"),
  rozetler: document.getElementById("rozetler"),
  gorevliUyarisi: document.getElementById("gorevli-uyarisi"),
  uzakIslem: document.getElementById("uzak-islem"),
  hazirAyarlar: document.getElementById("hazir-ayarlar"),
  kesinMod: document.getElementById("kesin-mod"),
  kesinBekleme: document.getElementById("kesin-bekleme"),
  kesinIpucu: document.getElementById("kesin-ipucu"),
  kaldirAlani: document.getElementById("kaldir-alani"),
  chromeBolumu: document.getElementById("chrome-bolumu"),
  chromeNotu: document.getElementById("chrome-notu"),
  islemHatasi: document.getElementById("islem-hatasi"),
  alt: document.getElementById("alt"),
  paneliAc: document.getElementById("paneli-ac"),
  bekleyen: document.getElementById("bekleyen"),
};

// Yeniden çizimde odağı geri vermek için: anahtar → öğe.
const odaklanabilir = new Map();
let izlemeZamanlayicisi = null; // uzak işlem sürerken durumu yeniden okuma zamanlayıcısı

ogeler.kesinMod.dataset.anahtar = "kesin";
ogeler.paneliAc.dataset.anahtar = "paneli-ac";

ogeler.kesinMod.addEventListener("change", () => {
  islemYap("kesin", { tur: "kesinMod", acik: ogeler.kesinMod.checked }, true);
});
ogeler.paneliAc.addEventListener("click", () => {
  islemYap("paneli-ac", { tur: "paneliAc" }, false);
});

baslat();

async function baslat() {
  ciz();
  await durumuOku();
  ciz();
  uzakIsiIzle();
}

// ---------- istekler ----------

async function hostaSor(istek) {
  let yanit;
  try {
    yanit = await chrome.runtime.sendMessage({ yaziciPaneli: istek });
  } catch (hata) {
    throw hataYap(BAGLANTI_KESILDI, false);
  }
  if (!yanit || typeof yanit !== "object") throw hataYap(BAGLANTI_KESILDI, false);
  if (yanit.tamam !== true) {
    throw hataYap(metinMi(yanit.hata) ? yanit.hata : "İstek yerine getirilemedi.", yanit.ulasilamadi === true);
  }
  return yanit;
}

async function durumuOku() {
  try {
    hal.veri = await hostaSor({ tur: "durum" });
    hal.baglantiHatasi = null;
  } catch (hata) {
    if (hal.veri) hal.islemHatasi = hal.islemHatasi || hata.message;
    else hal.baglantiHatasi = { metin: hata.message, ulasilamadi: hata.ulasilamadi === true };
  }
  hal.yukleniyor = false;
  uzakIsiGuncelle();
}

// Arka planda başka bir işlem sürüyorsa düğmeler kilitlenir; bitince açılır.
function uzakIsiGuncelle() {
  const suruyor = !!hal.veri && metinMi(hal.veri.mesgul);
  if (suruyor && hal.mesgul === null) hal.mesgul = UZAK;
  else if (!suruyor && hal.mesgul === UZAK) hal.mesgul = null;
}

// Uzak işlem sürdükçe durumu yaklaşık saniyede bir yeniden okur.
function uzakIsiIzle() {
  if (hal.mesgul !== UZAK || izlemeZamanlayicisi !== null) return;
  izlemeZamanlayicisi = setTimeout(async () => {
    izlemeZamanlayicisi = null;
    await durumuOku();
    ciz();
    uzakIsiIzle();
  }, IZLEME_ARALIGI);
}

// Düğmeleri kilitler, "…" gösterir, bitince durumu yeniden okur.
async function islemYap(anahtar, istek, sonraYenile) {
  if (hal.mesgul) {
    ciz();
    return;
  }
  const odak = odakAnahtari() || anahtar;
  hal.mesgul = anahtar;
  hal.islemHatasi = null;
  hal.kaldirOnayi = false;
  ciz();

  try {
    await hostaSor(istek);
  } catch (hata) {
    hal.islemHatasi = hata.message;
  }
  if (sonraYenile) await durumuOku();

  hal.mesgul = null;
  uzakIsiGuncelle();
  hal.odakIstegi = odak;
  ciz();
  uzakIsiIzle();
}

// ---------- çizim ----------

function ciz() {
  const odak = hal.odakIstegi || odakAnahtari();
  hal.odakIstegi = null;
  odaklanabilir.clear();
  odaklanabilir.set("kesin", ogeler.kesinMod);
  odaklanabilir.set("paneli-ac", ogeler.paneliAc);

  ustuCiz();
  sabitCiz();
  chromeCiz();
  altCiz();

  ogeler.islemHatasi.hidden = !hal.islemHatasi;
  ogeler.islemHatasi.textContent = hal.islemHatasi || "";

  const oge = odak ? odaklanabilir.get(odak) : null;
  if (oge && !oge.disabled && document.activeElement !== oge) oge.focus();
}

function ustuCiz() {
  const v = hal.veri;
  let seviye = "bilinmiyor";
  let baslik = "Durum okunuyor…";
  let ayrinti = null;
  let ipucu = "";

  if (v) {
    const d = v.durum && typeof v.durum === "object" ? v.durum : {};
    if (SEVIYELER.has(d.seviye)) seviye = d.seviye;
    baslik = metinMi(d.baslik) ? d.baslik : "Durum bilinmiyor";
    if (metinMi(d.ayrinti)) ayrinti = d.ayrinti;
    const y = v.yazici && typeof v.yazici === "object" ? v.yazici : null;
    if (y && metinMi(y.ad)) ipucu = metinMi(y.kuyruk) ? y.ad + " · " + y.kuyruk : y.ad;
  } else if (!hal.yukleniyor) {
    baslik = hal.baglantiHatasi && !hal.baglantiHatasi.ulasilamadi ? "Durum okunamadı" : "Bağlantı yok";
  }

  ogeler.durumNoktasi.dataset.seviye = seviye;
  ogeler.durumBasligi.textContent = baslik;
  ogeler.durumAyrintisi.hidden = !ayrinti;
  ogeler.durumAyrintisi.textContent = ayrinti || "";
  ogeler.yaziciAdi.title = ipucu;

  const hataVar = !v && !hal.yukleniyor && !!hal.baglantiHatasi;
  ogeler.baglantiHatasi.hidden = !hataVar;
  ogeler.baglantiHatasi.textContent = hataVar ? hal.baglantiHatasi.metin : "";
}

function sabitCiz() {
  const v = hal.veri;
  ogeler.sabitBolumu.hidden = !v;
  if (!v) return;

  const s = v.sabitleme && typeof v.sabitleme === "object" ? v.sabitleme : {};
  const etkin = s.etkin === true;
  const mesgul = hal.mesgul !== null;

  ogeler.kilitSimgesi.hidden = !etkin;
  ogeler.sabitOzeti.textContent = etkin ? (metinMi(s.ozet) ? s.ozet : "Sabit ayar etkin") : "Sabitleme kapalı";
  ogeler.sabitOzeti.classList.toggle("ikincil", !etkin);

  ogeler.rozetler.replaceChildren();
  if (etkin && s.pencereKatmani === true) ogeler.rozetler.append(ogeYap("span", "rozet", "Yazdırma penceresi"));
  if (etkin && s.kesinMod === true) ogeler.rozetler.append(ogeYap("span", "rozet", "Kesin mod"));
  ogeler.rozetler.hidden = ogeler.rozetler.childElementCount === 0;
  ogeler.gorevliUyarisi.hidden = !(etkin && s.kesinMod === true && s.gorevliCanli === false);
  ogeler.uzakIslem.hidden = hal.mesgul !== UZAK;
  ogeler.uzakIslem.textContent =
    hal.mesgul === UZAK ? UZAK_METINLERI.get(v.mesgul) || "Önceki işlem sürüyor…" : "";

  hazirAyarlariCiz(v, s, etkin, mesgul);

  // Kesin mod anahtarı; işlem sürerken kullanıcının seçtiği konumda kalır.
  if (hal.mesgul !== "kesin") ogeler.kesinMod.checked = s.kesinMod === true;
  ogeler.kesinMod.disabled = !etkin || mesgul;
  ogeler.kesinBekleme.hidden = hal.mesgul !== "kesin";
  ogeler.kesinIpucu.textContent = etkin ? "Her iş sabit ayarlarla basılır" : "Önce bir ayar sabitleyin";

  kaldirCiz(etkin, mesgul);
}

function hazirAyarlariCiz(v, s, etkin, mesgul) {
  const liste = Array.isArray(v.hazirAyarlar) ? v.hazirAyarlar : [];
  const etkinId = etkin && s.hazirAyarId != null ? String(s.hazirAyarId) : null;
  ogeler.hazirAyarlar.replaceChildren();

  for (const h of liste) {
    if (!h || typeof h !== "object" || !(metinMi(h.id) || Number.isFinite(h.id))) continue;
    const anahtar = "hazir:" + h.id;
    const secili = etkinId !== null && String(h.id) === etkinId;

    const dugme = ogeYap("button", "satir");
    dugme.type = "button";
    dugme.dataset.anahtar = anahtar;
    dugme.disabled = mesgul;
    if (secili) dugme.setAttribute("aria-current", "true");
    if (metinMi(h.aciklama)) dugme.title = h.aciklama;

    const metin = ogeYap("span", "satir-metin");
    metin.append(ogeYap("span", "satir-ad", metinMi(h.ad) ? h.ad : "Adsız ayar"));
    if (metinMi(h.ozet)) metin.append(ogeYap("span", "satir-ozet kucuk ikincil", h.ozet));

    const isaret = ogeYap("span", "satir-isaret");
    if (hal.mesgul === anahtar) isaret.append(beklemeYap());
    else if (secili) isaret.textContent = "✓";

    dugme.append(metin, isaret);
    dugme.addEventListener("click", () => {
      if (!secili) islemYap(anahtar, { tur: "sabitle", hazirAyarId: h.id }, true);
    });

    const satir = document.createElement("li");
    satir.append(dugme);
    ogeler.hazirAyarlar.append(satir);
    odaklanabilir.set(anahtar, dugme);
  }

  if (ogeler.hazirAyarlar.childElementCount === 0) {
    ogeler.hazirAyarlar.append(ogeYap("li", "bos-liste kucuk ikincil", "Hazır ayar yok."));
  }
}

function kaldirCiz(etkin, mesgul) {
  ogeler.kaldirAlani.replaceChildren();
  if (!etkin) {
    hal.kaldirOnayi = false;
    return;
  }

  if (hal.kaldirOnayi) {
    const kutu = ogeYap("div", "kaldir-onayi");
    const vazgec = dugmeYap("Vazgeç", "dugme", "kaldir-vazgec", mesgul);
    vazgec.addEventListener("click", () => {
      hal.kaldirOnayi = false;
      hal.odakIstegi = "kaldir";
      ciz();
    });
    const kaldir = dugmeYap("Kaldır", "dugme dugme-tehlike", "kaldir-onay", mesgul);
    kaldir.addEventListener("click", () => {
      islemYap("kaldir", { tur: "kaldir" }, true);
    });
    kutu.append(ogeYap("span", "kucuk", "Emin misiniz?"), vazgec, kaldir);
    ogeler.kaldirAlani.append(kutu);
    return;
  }

  const dugme = dugmeYap("Sabitlemeyi kaldır", "metin-dugmesi", "kaldir", mesgul);
  if (hal.mesgul === "kaldir") dugme.append(" ", beklemeYap());
  dugme.addEventListener("click", () => {
    hal.kaldirOnayi = true;
    hal.odakIstegi = "kaldir-vazgec";
    ciz();
  });
  ogeler.kaldirAlani.append(dugme);
}

function chromeCiz() {
  const not = hal.veri && metinMi(hal.veri.chromeNotu) ? hal.veri.chromeNotu : "";
  ogeler.chromeBolumu.hidden = !not;
  ogeler.chromeNotu.textContent = not;
}

function altCiz() {
  const v = hal.veri;
  ogeler.alt.hidden = !v;
  if (!v) return;

  ogeler.paneliAc.disabled = hal.mesgul !== null;
  ogeler.paneliAc.replaceChildren("Yazıcı Paneli'ni aç");
  if (hal.mesgul === "paneli-ac") ogeler.paneliAc.append(" ", beklemeYap());

  const n = Number.isFinite(v.bekleyenIs) ? v.bekleyenIs : null;
  ogeler.bekleyen.textContent = n === null ? "" : n === 0 ? "Bekleyen iş yok" : n + " iş bekliyor";
  ogeler.alt.title = metinMi(v.surum) ? "Yazıcı Paneli " + v.surum : "";
}

// ---------- yardımcılar ----------

function ogeYap(etiket, sinif, metin) {
  const oge = document.createElement(etiket);
  if (sinif) oge.className = sinif;
  if (metin !== undefined) oge.textContent = metin;
  return oge;
}

function dugmeYap(metin, sinif, anahtar, kilitli) {
  const dugme = ogeYap("button", sinif, metin);
  dugme.type = "button";
  dugme.dataset.anahtar = anahtar;
  dugme.disabled = kilitli;
  odaklanabilir.set(anahtar, dugme);
  return dugme;
}

function beklemeYap() {
  return ogeYap("span", "bekleme", "…");
}

function odakAnahtari() {
  const oge = document.activeElement;
  return oge && oge.dataset && oge.dataset.anahtar ? oge.dataset.anahtar : null;
}

function hataYap(metin, ulasilamadi) {
  const hata = new Error(metin);
  hata.ulasilamadi = ulasilamadi;
  return hata;
}

function metinMi(deger) {
  return typeof deger === "string" && deger.length > 0;
}
