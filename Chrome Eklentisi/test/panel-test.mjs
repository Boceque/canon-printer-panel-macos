// panel.js testi: panel.html'deki kimliklerden küçük bir sahte DOM kurulur, panel.js vm içinde çalışır.
// Çalıştırma: node test/panel-test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const PANEL_JS = readFileSync(new URL("../panel.js", import.meta.url), "utf8");
const PANEL_HTML = readFileSync(new URL("../panel.html", import.meta.url), "utf8");
const ULASILAMADI = "Yazıcı Paneli uygulamasına ulaşılamadı. Uygulamayı bir kez açın (Chrome köprüsünü o kurar).";

// ---------- sahte DOM ----------

class SahteOge {
  constructor(etiket, belge) {
    this.tagName = etiket.toUpperCase();
    this.belge = belge;
    this.cocuklar = [];
    this.oznitelikler = new Map();
    this.dataset = {};
    this.dinleyiciler = {};
    this.hidden = false;
    this.disabled = false;
    this.checked = false;
    this.title = "";
    this.type = "";
    this.className = "";
    this._metin = "";
    const oge = this;
    this.classList = {
      contains: (ad) => oge.className.split(/\s+/).includes(ad),
      toggle(ad, zorla) {
        const var_ = this.contains(ad);
        const olsun = zorla === undefined ? !var_ : !!zorla;
        const siniflar = oge.className.split(/\s+/).filter((s) => s && s !== ad);
        if (olsun) siniflar.push(ad);
        oge.className = siniflar.join(" ");
        return olsun;
      },
    };
  }
  get textContent() {
    return this._metin + this.cocuklar.map((c) => (typeof c === "string" ? c : c.textContent)).join("");
  }
  set textContent(deger) {
    this._metin = String(deger);
    this.cocuklar = [];
  }
  set innerHTML(_) {
    throw new Error("innerHTML kullanılmamalı");
  }
  get innerHTML() {
    throw new Error("innerHTML kullanılmamalı");
  }
  insertAdjacentHTML() {
    throw new Error("insertAdjacentHTML kullanılmamalı");
  }
  append(...ogeler) {
    for (const o of ogeler) {
      if (typeof o !== "string") o.ebeveyn = this;
      this.cocuklar.push(o);
    }
  }
  replaceChildren(...ogeler) {
    this._metin = "";
    this.cocuklar = [];
    this.append(...ogeler);
  }
  get childElementCount() {
    return this.cocuklar.filter((c) => typeof c !== "string").length;
  }
  setAttribute(ad, deger) {
    this.oznitelikler.set(ad, String(deger));
  }
  getAttribute(ad) {
    return this.oznitelikler.has(ad) ? this.oznitelikler.get(ad) : null;
  }
  removeAttribute(ad) {
    this.oznitelikler.delete(ad);
  }
  addEventListener(tur, fn) {
    (this.dinleyiciler[tur] ??= []).push(fn);
  }
  focus() {
    this.belge.activeElement = this;
  }
  tetikle(tur) {
    for (const fn of this.dinleyiciler[tur] || []) fn({ type: tur, target: this });
  }
  click() {
    if (!this.disabled) this.tetikle("click");
  }
  // Ağaçta arama (test kolaylığı)
  *tumu() {
    for (const c of this.cocuklar) {
      if (typeof c === "string") continue;
      yield c;
      yield* c.tumu();
    }
  }
}

function belgeKur() {
  const belge = { kimlikler: new Map() };
  belge.body = new SahteOge("body", belge);
  belge.activeElement = belge.body;
  belge.createElement = (etiket) => new SahteOge(etiket, belge);
  belge.getElementById = (id) => belge.kimlikler.get(id) || null;
  // panel.html'deki her id için bir öğe; hidden özniteliği ve düz metin korunur.
  const desen = /<([a-z0-9]+)\b([^>]*?)\bid="([^"]+)"([^>]*)>([^<]*)/gi;
  for (const [, etiket, once, id, sonra, metin] of PANEL_HTML.matchAll(desen)) {
    const oge = new SahteOge(etiket, belge);
    oge.hidden = /\shidden(\s|$|>)/.test(" " + once + " " + sonra + " ");
    if (metin.trim()) oge._metin = metin.trim();
    belge.kimlikler.set(id, oge);
  }
  return belge;
}

// ---------- ortam ----------

function ortamKur() {
  const belge = belgeKur();
  const istekler = []; // { istek, coz, reddet }
  const chrome = {
    runtime: {
      sendMessage(mesaj) {
        // Chrome mesajı JSON'a çevirerek taşır; vm dışına düz nesne olarak al.
        const istek = JSON.parse(JSON.stringify(mesaj)).yaziciPaneli;
        return new Promise((coz, reddet) => istekler.push({ istek, coz, reddet }));
      },
    },
  };
  const hatalar = [];
  // Sahte zamanlayıcı: test elle çalıştırır (panel.js'in yeniden okuma döngüsü için).
  const zamanlayicilar = [];
  const baglam = vm.createContext({
    document: belge,
    chrome,
    console: { warn() {}, log() {}, error: (...a) => hatalar.push(a) },
    setTimeout: (fn, ms) => zamanlayicilar.push({ fn, ms }),
    clearTimeout() {},
  });
  vm.runInContext(PANEL_JS, baglam, { filename: "panel.js" });
  const $ = (id) => {
    const oge = belge.getElementById(id);
    assert.ok(oge, `#${id} panel.html'de yok`);
    return oge;
  };
  return { belge, istekler, $, hatalar, zamanlayicilar };
}

const bekle = () => new Promise((c) => setTimeout(c, 0));

function ornekDurum(degisiklik = {}) {
  return {
    tamam: true,
    yazici: { ad: "Canon G3010 series", kuyruk: "Canon_G3010_series" },
    durum: { seviye: "hazir", baslik: "Hazır", ayrinti: "Mürekkep düzeyi iyi" },
    bekleyenIs: 2,
    sabitleme: {
      etkin: true,
      ozet: "Taslak · Siyah-beyaz · A4",
      kesinMod: true,
      pencereKatmani: false,
      hazirAyarId: "test",
      gorevliCanli: true,
    },
    hazirAyarlar: [
      { id: "test", ad: "Test çıktısı", aciklama: "Deneme sınavları için", ozet: "Taslak · Siyah-beyaz", yerlesik: true },
      { id: "foto", ad: "Fotoğraf", aciklama: "Parlak kağıt", ozet: "Yüksek · Renkli", yerlesik: true },
    ],
    chromeNotu: "Chrome kaliteyi göndermez; renk ve DPI'yi gönderir.",
    surum: "1.2",
    ...degisiklik,
  };
}

async function yukle(durum = ornekDurum()) {
  const ortam = ortamKur();
  await bekle();
  assert.equal(ortam.istekler.length, 1);
  assert.deepEqual(ortam.istekler[0].istek, { tur: "durum" });
  ortam.istekler.shift().coz(durum);
  await bekle();
  return ortam;
}

function satirlar($) {
  return [...$("hazir-ayarlar").tumu()].filter((o) => o.tagName === "BUTTON");
}

function dugmeBul($, kap, metin) {
  return [...$(kap).tumu()].find((o) => o.tagName === "BUTTON" && o.textContent.startsWith(metin));
}

// ---------------------------------------------------------------------------

test("yükleniyor durumu", async () => {
  const { $, istekler } = ortamKur();
  assert.equal($("durum-basligi").textContent, "Durum okunuyor…");
  assert.equal($("sabit-bolumu").hidden, true);
  assert.equal($("alt").hidden, true);
  assert.equal($("baglanti-hatasi").hidden, true);
  await bekle();
  assert.equal(istekler.length, 1);
});

test("normal durum çizilir", async () => {
  const { $ } = await yukle();
  assert.equal($("yazici-adi").textContent, "Canon G3010");
  assert.equal($("durum-noktasi").dataset.seviye, "hazir");
  assert.equal($("durum-basligi").textContent, "Hazır");
  assert.equal($("durum-ayrintisi").hidden, false);
  assert.equal($("durum-ayrintisi").textContent, "Mürekkep düzeyi iyi");
  assert.equal($("sabit-bolumu").hidden, false);
  assert.equal($("kilit-simgesi").hidden, false);
  assert.equal($("sabit-ozeti").textContent, "Taslak · Siyah-beyaz · A4");
  assert.equal($("rozetler").hidden, false);
  assert.equal($("rozetler").textContent, "Kesin mod");
  assert.equal($("gorevli-uyarisi").hidden, true);

  const s = satirlar($);
  assert.equal(s.length, 2);
  assert.equal(s[0].getAttribute("aria-current"), "true");
  assert.match(s[0].textContent, /Test çıktısı.*Taslak · Siyah-beyaz.*✓/);
  assert.equal(s[0].title, "Deneme sınavları için");
  assert.equal(s[1].getAttribute("aria-current"), null);
  assert.doesNotMatch(s[1].textContent, /✓/);

  assert.equal($("kesin-mod").checked, true);
  assert.equal($("kesin-mod").disabled, false);
  assert.equal($("kesin-ipucu").textContent, "Her iş sabit ayarlarla basılır");
  assert.ok(dugmeBul($, "kaldir-alani", "Sabitlemeyi kaldır"));
  assert.equal($("chrome-bolumu").hidden, false);
  assert.equal($("chrome-notu").textContent, "Chrome kaliteyi göndermez; renk ve DPI'yi gönderir.");
  assert.equal($("alt").hidden, false);
  assert.equal($("bekleyen").textContent, "2 iş bekliyor");
  assert.equal($("islem-hatasi").hidden, true);
});

test("host metinleri HTML olarak yorumlanmaz", async () => {
  const kotu = "<img src=x onerror=alert(1)>";
  const { $ } = await yukle(
    ornekDurum({
      durum: { seviye: "uyari", baslik: kotu, ayrinti: kotu },
      chromeNotu: kotu,
      hazirAyarlar: [{ id: kotu, ad: kotu, ozet: kotu, aciklama: kotu, yerlesik: false }],
    })
  );
  assert.equal($("durum-basligi").textContent, kotu);
  assert.equal($("chrome-notu").textContent, kotu);
  assert.match(satirlar($)[0].textContent, /<img src=x onerror=alert\(1\)>/);
});

test("kesin mod açık ama görevli çalışmıyor → uyarı", async () => {
  const d = ornekDurum();
  d.sabitleme.gorevliCanli = false;
  d.sabitleme.pencereKatmani = true;
  const { $ } = await yukle(d);
  assert.equal($("gorevli-uyarisi").hidden, false);
  assert.equal($("rozetler").childElementCount, 2);
});

test("sabitleme kapalı", async () => {
  const d = ornekDurum({
    sabitleme: { etkin: false, ozet: "", kesinMod: false, pencereKatmani: false, hazirAyarId: null, gorevliCanli: false },
    bekleyenIs: 0,
  });
  const { $ } = await yukle(d);
  assert.equal($("sabit-ozeti").textContent, "Sabitleme kapalı");
  assert.equal($("kilit-simgesi").hidden, true);
  assert.equal($("rozetler").hidden, true);
  assert.equal($("kesin-mod").disabled, true);
  assert.equal($("kesin-ipucu").textContent, "Önce bir ayar sabitleyin");
  assert.equal($("kaldir-alani").childElementCount, 0);
  assert.ok(satirlar($).every((s) => !/✓/.test(s.textContent)));
  assert.equal($("bekleyen").textContent, "Bekleyen iş yok");
});

test("hazır ayar tıklanınca sabitle; süreç boyunca kilit ve …; sonra durum yenilenir", async () => {
  const { $, istekler } = await yukle();
  satirlar($)[1].click();
  await bekle();
  assert.equal(istekler.length, 1);
  assert.deepEqual(istekler[0].istek, { tur: "sabitle", hazirAyarId: "foto" });

  // Süreç sürüyor
  assert.ok(satirlar($).every((s) => s.disabled));
  assert.match(satirlar($)[1].textContent, /…/);
  assert.equal($("kesin-mod").disabled, true);
  assert.equal($("paneli-ac").disabled, true);
  satirlar($)[0].click(); // kilitliyken etkisiz
  await bekle();
  assert.equal(istekler.length, 1);

  istekler.shift().coz({ tamam: true, ozet: "Yüksek · Renkli" });
  await bekle();
  assert.equal(istekler.length, 1);
  assert.deepEqual(istekler[0].istek, { tur: "durum" });
  const yeni = ornekDurum();
  yeni.sabitleme.hazirAyarId = "foto";
  istekler.shift().coz(yeni);
  await bekle();

  assert.ok(satirlar($).every((s) => !s.disabled));
  assert.match(satirlar($)[1].textContent, /✓/);
  assert.doesNotMatch(satirlar($)[0].textContent, /✓/);
  assert.equal($("paneli-ac").disabled, false);
});

test("etkin hazır ayara tıklamak istek göndermez", async () => {
  const { $, istekler } = await yukle();
  satirlar($)[0].click();
  await bekle();
  assert.equal(istekler.length, 0);
});

test("sabitlemeyi kaldır: iki adımlı onay", async () => {
  const { $, istekler, belge } = await yukle();
  dugmeBul($, "kaldir-alani", "Sabitlemeyi kaldır").click();
  assert.match($("kaldir-alani").textContent, /Emin misiniz\?/);
  const vazgec = dugmeBul($, "kaldir-alani", "Vazgeç");
  assert.ok(vazgec);
  assert.equal(belge.activeElement, vazgec, "odak Vazgeç'e geçmeli");
  vazgec.click();
  assert.ok(dugmeBul($, "kaldir-alani", "Sabitlemeyi kaldır"));
  await bekle();
  assert.equal(istekler.length, 0);

  dugmeBul($, "kaldir-alani", "Sabitlemeyi kaldır").click();
  dugmeBul($, "kaldir-alani", "Kaldır").click();
  await bekle();
  assert.deepEqual(istekler[0].istek, { tur: "kaldir" });
  const bekleyen = dugmeBul($, "kaldir-alani", "Sabitlemeyi kaldır");
  assert.ok(bekleyen.disabled);
  assert.match(bekleyen.textContent, /…/);

  istekler.shift().coz({ tamam: true });
  await bekle();
  istekler.shift().coz(
    ornekDurum({ sabitleme: { etkin: false, ozet: "", kesinMod: false, pencereKatmani: false, hazirAyarId: null, gorevliCanli: false } })
  );
  await bekle();
  assert.equal($("sabit-ozeti").textContent, "Sabitleme kapalı");
  assert.equal($("kaldir-alani").childElementCount, 0);
});

test("kesin mod anahtarı", async () => {
  const { $, istekler } = await yukle();
  const anahtar = $("kesin-mod");
  anahtar.checked = false;
  anahtar.tetikle("change");
  await bekle();
  assert.deepEqual(istekler[0].istek, { tur: "kesinMod", acik: false });
  assert.equal($("kesin-bekleme").hidden, false);
  assert.equal(anahtar.checked, false, "süreç boyunca kullanıcının seçtiği konumda kalmalı");
  assert.equal(anahtar.disabled, true);

  istekler.shift().coz({ tamam: true });
  await bekle();
  const yeni = ornekDurum();
  yeni.sabitleme.kesinMod = false;
  istekler.shift().coz(yeni);
  await bekle();
  assert.equal($("kesin-bekleme").hidden, true);
  assert.equal(anahtar.checked, false);
  assert.equal(anahtar.disabled, false);
  assert.equal($("rozetler").hidden, true);
});

test("işlem hatası gösterilir, arayüz açılır", async () => {
  const { $, istekler } = await yukle();
  satirlar($)[1].click();
  await bekle();
  istekler.shift().coz({ tamam: false, hata: "Yazıcı ayarı yazılamadı." });
  await bekle();
  istekler.shift().coz(ornekDurum());
  await bekle();
  assert.equal($("islem-hatasi").hidden, false);
  assert.equal($("islem-hatasi").textContent, "Yazıcı ayarı yazılamadı.");
  assert.ok(satirlar($).every((s) => !s.disabled));
});

test("paneli aç: istek gider, durum yeniden istenmez", async () => {
  const { $, istekler } = await yukle();
  $("paneli-ac").click();
  await bekle();
  assert.deepEqual(istekler[0].istek, { tur: "paneliAc" });
  assert.equal($("paneli-ac").disabled, true);
  assert.match($("paneli-ac").textContent, /Yazıcı Paneli'ni aç …/);
  istekler.shift().coz({ tamam: true });
  await bekle();
  assert.equal(istekler.length, 0);
  assert.equal($("paneli-ac").disabled, false);
  assert.equal($("paneli-ac").textContent, "Yazıcı Paneli'ni aç");
});

test("uygulamaya ulaşılamıyor → Türkçe yardım", async () => {
  const { $ } = await yukle({ tamam: false, hata: ULASILAMADI, ulasilamadi: true });
  assert.equal($("durum-basligi").textContent, "Bağlantı yok");
  assert.equal($("baglanti-hatasi").hidden, false);
  assert.equal($("baglanti-hatasi").textContent, ULASILAMADI);
  assert.equal($("sabit-bolumu").hidden, true);
  assert.equal($("chrome-bolumu").hidden, true);
  assert.equal($("alt").hidden, true);
});

test("host hata döndürürse metni gösterilir", async () => {
  const { $ } = await yukle({ tamam: false, hata: "CUPS yanıt vermiyor." });
  assert.equal($("durum-basligi").textContent, "Durum okunamadı");
  assert.equal($("baglanti-hatasi").textContent, "CUPS yanıt vermiyor.");
});

test("arka plana ulaşılamazsa sakin hata", async () => {
  const ortam = ortamKur();
  await bekle();
  ortam.istekler.shift().reddet(new Error("Could not establish connection. Receiving end does not exist."));
  await bekle();
  assert.equal(ortam.$("baglanti-hatasi").hidden, false);
  assert.match(ortam.$("baglanti-hatasi").textContent, /arka planına ulaşılamadı/);
});

test("eksik alanlı yanıtta çökmez", async () => {
  const { $, hatalar } = await yukle({ tamam: true });
  assert.equal($("durum-basligi").textContent, "Durum bilinmiyor");
  assert.equal($("durum-noktasi").dataset.seviye, "bilinmiyor");
  assert.equal($("sabit-ozeti").textContent, "Sabitleme kapalı");
  assert.match($("hazir-ayarlar").textContent, /Hazır ayar yok/);
  assert.equal($("chrome-bolumu").hidden, true);
  assert.equal($("bekleyen").textContent, "");
  assert.equal(hatalar.length, 0);
});

// ---------- başka panelden süren işlem ----------

function hepsiKilitli($) {
  return (
    satirlar($).every((s) => s.disabled) &&
    $("kesin-mod").disabled &&
    $("paneli-ac").disabled &&
    dugmeBul($, "kaldir-alani", "Sabitlemeyi kaldır").disabled
  );
}

test("arka planda işlem sürüyorsa düğmeler kilitli gelir, bitene dek durum yeniden okunur", async () => {
  const { $, istekler, zamanlayicilar } = await yukle(ornekDurum({ mesgul: "kaldir" }));
  assert.ok(hepsiKilitli($));
  assert.equal($("uzak-islem").hidden, false);
  assert.equal($("uzak-islem").textContent, "Sabitleme kaldırılıyor…");

  // Kilitliyken tıklamak istek göndermez.
  satirlar($)[1].click();
  $("paneli-ac").click();
  await bekle();
  assert.equal(istekler.length, 0);

  // Yaklaşık saniyede bir durum yeniden okunur.
  assert.equal(zamanlayicilar.length, 1);
  assert.equal(zamanlayicilar[0].ms, 1000);
  zamanlayicilar.shift().fn();
  await bekle();
  assert.deepEqual(istekler[0].istek, { tur: "durum" });
  istekler.shift().coz(ornekDurum({ mesgul: "sabitle" }));
  await bekle();
  assert.ok(hepsiKilitli($));
  assert.equal($("uzak-islem").textContent, "Ayar sabitleniyor…");
  assert.equal(zamanlayicilar.length, 1);

  // İşlem bitti: kilit açılır, döngü durur.
  zamanlayicilar.shift().fn();
  await bekle();
  istekler.shift().coz(ornekDurum());
  await bekle();
  assert.equal($("uzak-islem").hidden, true);
  assert.ok(satirlar($).every((s) => !s.disabled));
  assert.equal($("kesin-mod").disabled, false);
  assert.equal($("paneli-ac").disabled, false);
  assert.equal(zamanlayicilar.length, 0);

  satirlar($)[1].click();
  await bekle();
  assert.deepEqual(istekler[0].istek, { tur: "sabitle", hazirAyarId: "foto" });
});

test("kendi işlemi bitince arka planda başka işlem sürüyorsa kilit kalır", async () => {
  const { $, istekler, zamanlayicilar } = await yukle();
  satirlar($)[1].click();
  await bekle();
  istekler.shift().coz({ tamam: true });
  await bekle();
  istekler.shift().coz(ornekDurum({ mesgul: "kesinMod" }));
  await bekle();
  assert.ok(hepsiKilitli($));
  assert.equal($("uzak-islem").textContent, "Kesin mod değiştiriliyor…");
  assert.equal(zamanlayicilar.length, 1);
});

test("durum okunamazsa kilit sürer, yeniden denenir", async () => {
  const { $, istekler, zamanlayicilar } = await yukle(ornekDurum({ mesgul: "kaldir" }));
  zamanlayicilar.shift().fn();
  await bekle();
  istekler.shift().coz({ tamam: false, hata: "Yazıcı Paneli zamanında yanıt vermedi." });
  await bekle();
  assert.ok(hepsiKilitli($));
  assert.equal(zamanlayicilar.length, 1, "yeniden denemeli");
});

test("bilinmeyen mesgul değeri genel metinle gösterilir", async () => {
  const { $ } = await yukle(ornekDurum({ mesgul: "constructor" }));
  assert.equal($("uzak-islem").textContent, "Önceki işlem sürüyor…");
});

test("kopan bağlantı metni yeniden yüklemeyi de söyler", async () => {
  const ortam = ortamKur();
  await bekle();
  ortam.istekler.shift().reddet(new Error("Could not establish connection. Receiving end does not exist."));
  await bekle();
  assert.match(ortam.$("baglanti-hatasi").textContent, /chrome:\/\/extensions/);
});
