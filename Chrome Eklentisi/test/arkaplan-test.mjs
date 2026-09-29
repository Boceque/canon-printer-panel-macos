// arkaplan.js testi: sahte `chrome` nesnesiyle vm içinde çalıştırılır.
// Çalıştırma: node test/arkaplan-test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const KAYNAK = readFileSync(new URL("../arkaplan.js", import.meta.url), "utf8");
const HOST = "com.caglar.yazicipaneli";
const EKLENTI_KIMLIGI = "abohnodngchkppmelngdcbidgpfocfho";
const ULASILAMADI = "Yazıcı Paneli uygulamasına ulaşılamadı. Uygulamayı bir kez açın (Chrome köprüsünü o kurar).";

// hostYaniti(istek) → Promise (sendNativeMessage'ın dönüşü) ya da fırlatır.
function ortamKur(hostYaniti) {
  const dinleyiciler = {};
  const gonderilenler = [];
  const uyarilar = [];
  const olay = (ad) => ({
    addListener(fn) {
      (dinleyiciler[ad] ??= []).push(fn);
    },
  });
  const chrome = {
    printerProvider: {
      onGetPrintersRequested: olay("yazicilar"),
      onGetCapabilityRequested: olay("yetenekler"),
      onPrintRequested: olay("yazdir"),
      onGetUsbPrinterInfoRequested: olay("usb"),
    },
    runtime: {
      id: EKLENTI_KIMLIGI,
      lastError: undefined,
      onMessage: olay("mesaj"),
      sendNativeMessage(host, istek) {
        gonderilenler.push({ host, istek });
        return hostYaniti(istek);
      },
    },
  };
  const baglam = vm.createContext({
    chrome,
    btoa,
    TextEncoder,
    setTimeout,
    clearTimeout,
    console: { warn: (...a) => uyarilar.push(a.join(" ")), log() {}, error() {} },
  });
  vm.runInContext(KAYNAK, baglam, { filename: "arkaplan.js" });
  return { baglam, dinleyiciler, gonderilenler, uyarilar };
}

const yanitla = (yanit) => () => Promise.resolve(yanit);
const hostYok = () => () => Promise.reject(new Error("Specified native messaging host not found."));

// Dinleyiciyi çağırır, geri çağrının tam bir kez geldiğini doğrular.
async function sonucAl(dinleyici, ...argumanlar) {
  const cagrilar = [];
  let coz;
  const ilk = new Promise((c) => (coz = c));
  dinleyici(...argumanlar, (sonuc) => {
    cagrilar.push(sonuc);
    coz();
  });
  let zamanlayici;
  const zaman = new Promise((_, r) => {
    zamanlayici = setTimeout(() => r(new Error("geri çağrı hiç çağrılmadı")), 5000);
  });
  await Promise.race([ilk, zaman]).finally(() => clearTimeout(zamanlayici));
  await new Promise((c) => setTimeout(c, 25));
  assert.equal(cagrilar.length, 1, "geri çağrı tam bir kez çağrılmalı");
  return cagrilar[0];
}

const duzJson = (x) => JSON.parse(JSON.stringify(x)); // vm'den gelen nesneleri karşılaştırmak için

function rastgeleBaytlar(uzunluk, tohum = 7) {
  const b = new Uint8Array(uzunluk);
  let x = tohum >>> 0 || 1;
  for (let i = 0; i < uzunluk; i++) {
    x ^= x << 13;
    x ^= x >>> 17;
    x ^= x << 5;
    b[i] = x & 0xff;
  }
  return b;
}

function sahtePdf(ekBayt = 0) {
  const bas = Buffer.from("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n1 0 obj << /Type /Catalog >> endobj\n", "latin1");
  const son = Buffer.from("\n%%EOF\n", "latin1");
  return new Uint8Array(Buffer.concat([bas, Buffer.from(rastgeleBaytlar(ekBayt)), son]));
}

const BILET = {
  version: "1.0",
  print: {
    color: { vendor_id: "", type: "STANDARD_MONOCHROME" },
    dpi: { horizontal_dpi: 300, vertical_dpi: 300 },
    copies: { copies: 2 },
    media_size: { width_microns: 210000, height_microns: 297000 },
  },
};

// ---------------------------------------------------------------------------

test("dinleyiciler en üst düzeyde, senkron eklenir", () => {
  const { dinleyiciler } = ortamKur(yanitla({ tamam: true }));
  assert.equal(dinleyiciler.yazicilar?.length, 1);
  assert.equal(dinleyiciler.yetenekler?.length, 1);
  assert.equal(dinleyiciler.yazdir?.length, 1);
  assert.equal(dinleyiciler.mesaj?.length, 1);
  assert.equal(dinleyiciler.usb, undefined, "onGetUsbPrinterInfoRequested kullanılmamalı");
});

test("yazıcı listesi: host yanıtı PrinterInfo'ya çevrilir", async () => {
  const { dinleyiciler, gonderilenler } = ortamKur(
    yanitla({ tamam: true, id: "yazici-paneli-canon", ad: "Canon G3010 · Sabit ayarlar", aciklama: "Taslak · Siyah-beyaz" })
  );
  const sonuc = await sonucAl(dinleyiciler.yazicilar[0]);
  assert.deepEqual(duzJson(sonuc), [
    { id: "yazici-paneli-canon", name: "Canon G3010 · Sabit ayarlar", description: "Taslak · Siyah-beyaz" },
  ]);
  assert.equal(gonderilenler.length, 1);
  assert.equal(gonderilenler[0].host, HOST);
  assert.deepEqual(duzJson(gonderilenler[0].istek), { tur: "yazici" });
});

test("yazıcı listesi: host hatası → []", async (t) => {
  const durumlar = {
    "host yok (Promise reddi)": hostYok(),
    "sendNativeMessage fırlatır": () => () => {
      throw new Error("Error in invocation of runtime.sendNativeMessage");
    },
    "tamam: false": yanitla({ tamam: false, hata: "Yazıcı bulunamadı." }),
    "yanıt null": yanitla(null),
    "id yok": yanitla({ tamam: true, ad: "Canon" }),
  };
  for (const [ad, host] of Object.entries(durumlar)) {
    await t.test(ad, async () => {
      const { dinleyiciler } = ortamKur(host);
      const sonuc = await sonucAl(dinleyiciler.yazicilar[0]);
      assert.deepEqual(duzJson(sonuc), []);
    });
  }
});

test("yetenekler: CDD aynen verilir", async () => {
  const cdd = {
    version: "1.0",
    printer: {
      supported_content_type: [{ content_type: "application/pdf" }],
      color: { option: [{ type: "STANDARD_MONOCHROME", is_default: true }] },
    },
  };
  const { dinleyiciler, gonderilenler } = ortamKur(yanitla({ tamam: true, cdd }));
  const sonuc = await sonucAl(dinleyiciler.yetenekler[0], "yazici-paneli-canon");
  assert.equal(sonuc, cdd, "aynı nesne dönmeli");
  assert.deepEqual(duzJson(gonderilenler[0].istek), { tur: "yetenekler" });
});

test("yetenekler: hata → {}", async (t) => {
  const durumlar = {
    "host yok": hostYok(),
    "tamam: false": yanitla({ tamam: false, hata: "PPD okunamadı." }),
    "cdd eksik": yanitla({ tamam: true }),
    "cdd dizi": yanitla({ tamam: true, cdd: [] }),
  };
  for (const [ad, host] of Object.entries(durumlar)) {
    await t.test(ad, async () => {
      const { dinleyiciler } = ortamKur(host);
      const sonuc = await sonucAl(dinleyiciler.yetenekler[0], "yazici-paneli-canon");
      assert.deepEqual(duzJson(sonuc), {});
    });
  }
});

test("yazdırma: küçük PDF → base64 doğru, bilet aynen, OK", async () => {
  const pdf = sahtePdf(1000);
  const { dinleyiciler, gonderilenler } = ortamKur(yanitla({ tamam: true, isNo: 42, ozet: "Taslak · Siyah-beyaz" }));
  const isBilgisi = {
    printerId: "yazici-paneli-canon",
    title: "Deneme 1 — Türev",
    ticket: BILET,
    contentType: "application/pdf",
    document: new Blob([pdf], { type: "application/pdf" }),
  };
  const sonuc = await sonucAl(dinleyiciler.yazdir[0], isBilgisi);
  assert.equal(sonuc, "OK");
  assert.equal(gonderilenler.length, 1);
  const { host, istek } = gonderilenler[0];
  assert.equal(host, HOST);
  assert.equal(istek.tur, "yazdir");
  assert.equal(istek.baslik, "Deneme 1 — Türev");
  assert.equal(istek.bilet, BILET, "bilet aynı nesne olarak iletilmeli");
  assert.equal(istek.belge, Buffer.from(pdf).toString("base64"));
  assert.deepEqual(new Uint8Array(Buffer.from(istek.belge, "base64")), pdf);
  assert.deepEqual(Object.keys(istek).sort(), ["baslik", "belge", "bilet", "tur"]);
});

test("yazdırma: host hatası → FAILED", async (t) => {
  const durumlar = {
    "tamam: false": yanitla({ tamam: false, hata: "Yazıcı kapalı." }),
    "host yok": hostYok(),
    "yanıt null": yanitla(null),
    "tamam alanı yok": yanitla({ isNo: 1 }),
  };
  for (const [ad, host] of Object.entries(durumlar)) {
    await t.test(ad, async () => {
      const { dinleyiciler } = ortamKur(host);
      const sonuc = await sonucAl(dinleyiciler.yazdir[0], {
        title: "x",
        ticket: BILET,
        contentType: "application/pdf",
        document: new Blob([sahtePdf(10)]),
      });
      assert.equal(sonuc, "FAILED");
    });
  }
});

test("yazdırma: geçersiz belge → INVALID_DATA, host çağrılmaz", async (t) => {
  const durumlar = {
    "60 MB'tan büyük": {
      title: "büyük",
      ticket: BILET,
      contentType: "application/pdf",
      document: {
        size: 60 * 1024 * 1024 + 1,
        arrayBuffer() {
          throw new Error("okunmamalıydı");
        },
      },
    },
    "PDF değil (PWG raster)": {
      title: "pwg",
      ticket: BILET,
      contentType: "image/pwg-raster",
      document: new Blob([new Uint8Array([1, 2, 3])]),
    },
    "base64 hâli 64 MiB ileti sınırını aşıyor (50 MB)": {
      title: "50 MB",
      ticket: BILET,
      contentType: "application/pdf",
      document: { size: 50 * 1024 * 1024, arrayBuffer: async () => new ArrayBuffer(50 * 1024 * 1024) },
    },
    "belge yok": { title: "yok", ticket: BILET, contentType: "application/pdf" },
    "boş belge": { title: "boş", ticket: BILET, contentType: "application/pdf", document: new Blob([]) },
  };
  for (const [ad, isBilgisi] of Object.entries(durumlar)) {
    await t.test(ad, async () => {
      const { dinleyiciler, gonderilenler } = ortamKur(yanitla({ tamam: true }));
      const sonuc = await sonucAl(dinleyiciler.yazdir[0], isBilgisi);
      assert.equal(sonuc, "INVALID_DATA");
      assert.equal(gonderilenler.length, 0);
    });
  }
});

test("yazdırma: printJob null → geri çağrı yine bir kez", async () => {
  const { dinleyiciler } = ortamKur(yanitla({ tamam: true }));
  const sonuc = await sonucAl(dinleyiciler.yazdir[0], null);
  assert.equal(sonuc, "INVALID_DATA");
});

test("yazdırma: arrayBuffer reddederse → FAILED", async () => {
  const { dinleyiciler, gonderilenler } = ortamKur(yanitla({ tamam: true }));
  const sonuc = await sonucAl(dinleyiciler.yazdir[0], {
    title: "bozuk",
    ticket: BILET,
    contentType: "application/pdf",
    document: { size: 10, arrayBuffer: () => Promise.reject(new Error("okunamadı")) },
  });
  assert.equal(sonuc, "FAILED");
  assert.equal(gonderilenler.length, 0);
});

test("base64Yap: kenar uzunluklarında Buffer ile aynı", () => {
  const { baglam } = ortamKur(yanitla({ tamam: true }));
  const P = 0x6000;
  for (const n of [0, 1, 2, 3, 4, 5, P - 1, P, P + 1, P + 2, 2 * P + 2, 0x8000, 0x8000 + 1, 100003]) {
    const b = rastgeleBaytlar(n, n + 3);
    assert.equal(baglam.base64Yap(b), Buffer.from(b).toString("base64"), `uzunluk ${n}`);
  }
});

test("5 MB belge: yığın taşmaz, base64 doğru, OK", async () => {
  const pdf = sahtePdf(5 * 1024 * 1024);
  const { baglam, dinleyiciler, gonderilenler } = ortamKur(yanitla({ tamam: true, isNo: 7, ozet: "" }));
  const beklenen = Buffer.from(pdf).toString("base64");

  assert.equal(baglam.base64Yap(pdf), beklenen);

  const sonuc = await sonucAl(dinleyiciler.yazdir[0], {
    title: "5 MB",
    ticket: BILET,
    contentType: "application/pdf",
    document: new Blob([pdf], { type: "application/pdf" }),
  });
  assert.equal(sonuc, "OK");
  assert.equal(gonderilenler[0].istek.belge.length, beklenen.length);
  assert.equal(gonderilenler[0].istek.belge, beklenen);
});

test("hostaSor: zaman aşımı reddeder, geç gelen yanıt yok sayılır", async () => {
  let gecCoz;
  const { baglam } = ortamKur(() => new Promise((c) => (gecCoz = c)));
  await assert.rejects(baglam.hostaSor({ tur: "durum" }, 30), (hata) => {
    assert.match(hata.message, /zamanında yanıt vermedi/);
    assert.equal(hata.ulasilamadi, false);
    return true;
  });
  gecCoz({ tamam: true }); // etkisiz kalmalı
  await new Promise((c) => setTimeout(c, 10));
});

test("hostaSor: host yok → Türkçe yardım metni, ulasilamadi", async () => {
  const { baglam } = ortamKur(hostYok());
  await assert.rejects(baglam.hostaSor({ tur: "durum" }, 1000), (hata) => {
    assert.equal(hata.message, ULASILAMADI);
    assert.equal(hata.ulasilamadi, true);
    return true;
  });
});

test("hostaSor: tamam false → host'un hata metni", async () => {
  const { baglam } = ortamKur(yanitla({ tamam: false, hata: "Yazıcı ayarı yazılamadı." }));
  await assert.rejects(baglam.hostaSor({ tur: "kaldir" }, 1000), (hata) => {
    assert.equal(hata.message, "Yazıcı ayarı yazılamadı.");
    assert.equal(hata.ulasilamadi, false);
    return true;
  });
});

test("birKez: ikinci çağrı ve fırlatan geri çağrı zararsız", () => {
  const { baglam } = ortamKur(yanitla({ tamam: true }));
  let sayac = 0;
  const f = baglam.birKez(() => {
    sayac++;
    throw new Error("Chrome geri çağrısı fırlattı");
  });
  f("OK");
  f("FAILED");
  assert.equal(sayac, 1);
});

// ---------- popup aktarımı ----------

function mesajGonder(dinleyici, mesaj, gonderen = { id: EKLENTI_KIMLIGI }) {
  return new Promise((coz, reddet) => {
    let sayac = 0;
    let deger;
    const donus = dinleyici(mesaj, gonderen, (y) => {
      sayac++;
      deger = y;
    });
    setTimeout(() => {
      if (sayac > 1) reddet(new Error("yanıt birden çok kez verildi"));
      else coz({ donus, sayac, yanit: deger === undefined ? undefined : duzJson(deger) });
    }, 30);
  });
}

test("popup aktarımı: durum host'a gider, yanıt aynen döner", async () => {
  const durum = {
    tamam: true,
    yazici: { ad: "Canon G3010 series", kuyruk: "Canon_G3010_series" },
    durum: { seviye: "hazir", baslik: "Hazır", ayrinti: null },
    bekleyenIs: 0,
    sabitleme: { etkin: true, ozet: "Taslak · Siyah-beyaz", kesinMod: false, pencereKatmani: true, hazirAyarId: "test", gorevliCanli: true },
    hazirAyarlar: [],
    chromeNotu: "Not",
    surum: "1.0",
  };
  const { dinleyiciler, gonderilenler } = ortamKur(yanitla(durum));
  const s = await mesajGonder(dinleyiciler.mesaj[0], { yaziciPaneli: { tur: "durum" } });
  assert.equal(s.donus, true, "eşzamansız yanıt için true dönmeli");
  assert.equal(s.sayac, 1);
  assert.deepEqual(s.yanit, durum);
  assert.equal(gonderilenler[0].host, HOST);
  assert.deepEqual(duzJson(gonderilenler[0].istek), { tur: "durum" });
});

test("popup aktarımı: yalnız bilinen alanlar geçer", async () => {
  const { dinleyiciler, gonderilenler } = ortamKur(yanitla({ tamam: true, ozet: "x" }));
  await mesajGonder(dinleyiciler.mesaj[0], { yaziciPaneli: { tur: "sabitle", hazirAyarId: "taslak-sb", fazla: 1 } });
  await mesajGonder(dinleyiciler.mesaj[0], { yaziciPaneli: { tur: "kesinMod", acik: true, belge: "…" } });
  await mesajGonder(dinleyiciler.mesaj[0], { yaziciPaneli: { tur: "kaldir", x: 1 } });
  await mesajGonder(dinleyiciler.mesaj[0], { yaziciPaneli: { tur: "paneliAc" } });
  assert.deepEqual(
    gonderilenler.map((g) => duzJson(g.istek)),
    [
      { tur: "sabitle", hazirAyarId: "taslak-sb" },
      { tur: "kesinMod", acik: true },
      { tur: "kaldir" },
      { tur: "paneliAc" },
    ]
  );
});

test("popup aktarımı: geçersiz istekler host'a gitmez", async () => {
  const { dinleyiciler, gonderilenler } = ortamKur(yanitla({ tamam: true }));
  for (const istek of [
    { tur: "yazdir", belge: "AAAA" },
    { tur: "constructor" },
    { tur: "sabitle" },
    { tur: "kesinMod", acik: "evet" },
    null,
  ]) {
    const s = await mesajGonder(dinleyiciler.mesaj[0], { yaziciPaneli: istek });
    assert.equal(s.sayac, 1);
    assert.equal(s.yanit.tamam, false);
  }
  // Başka eklentiden / ilgisiz mesaj: dokunulmaz.
  const yabanci = await mesajGonder(dinleyiciler.mesaj[0], { yaziciPaneli: { tur: "durum" } }, { id: "baska" });
  assert.equal(yabanci.donus, false);
  assert.equal(yabanci.sayac, 0);
  const ilgisiz = await mesajGonder(dinleyiciler.mesaj[0], { baska: 1 });
  assert.equal(ilgisiz.donus, false);
  assert.equal(ilgisiz.sayac, 0);
  assert.equal(gonderilenler.length, 0);
});

test("popup aktarımı: host yok → ulasilamadi + yardım metni", async () => {
  const { dinleyiciler } = ortamKur(hostYok());
  const s = await mesajGonder(dinleyiciler.mesaj[0], { yaziciPaneli: { tur: "durum" } });
  assert.deepEqual(s.yanit, { tamam: false, hata: ULASILAMADI, ulasilamadi: true });
});

test("popup aktarımı: host hatası metni iletilir", async () => {
  const { dinleyiciler } = ortamKur(yanitla({ tamam: false, hata: "Hazır ayar bulunamadı." }));
  const s = await mesajGonder(dinleyiciler.mesaj[0], { yaziciPaneli: { tur: "sabitle", hazirAyarId: "yok" } });
  assert.deepEqual(s.yanit, { tamam: false, hata: "Hazır ayar bulunamadı.", ulasilamadi: false });
});

// ---------- durum değiştiren isteklerin sırası ----------

// Yanıtı testin elinde olan host: her çağrı `bekleyenler`e düşer, test çözer.
function elleHost() {
  const bekleyenler = [];
  const host = (istek) => new Promise((coz, reddet) => bekleyenler.push({ istek: duzJson(istek), coz, reddet }));
  return { host, bekleyenler };
}

// Popup'tan mesaj gönderir; yanıt geldiğinde çözülen bir söz döndürür.
function mesajBaslat(dinleyici, istek) {
  let coz;
  const yanit = new Promise((c) => (coz = c));
  const donus = dinleyici({ yaziciPaneli: istek }, { id: EKLENTI_KIMLIGI }, (y) => coz(duzJson(y)));
  return { donus, yanit };
}

const tik = () => new Promise((c) => setTimeout(c, 0));

test("sıra: durum değiştiren istekler üst üste binmez; durum ve paneliAc beklemez", async () => {
  const { host, bekleyenler } = elleHost();
  const { dinleyiciler } = ortamKur(host);
  const gonder = (istek) => mesajBaslat(dinleyiciler.mesaj[0], istek);

  const kaldir = gonder({ tur: "kaldir" });
  await tik();
  assert.equal(kaldir.donus, true);
  assert.deepEqual(bekleyenler.map((b) => b.istek), [{ tur: "kaldir" }]);

  // Popup kapanıp açıldı, kullanıcı hazır ayara tıkladı: kaldir bitmeden host'a gitmemeli.
  const sabitle = gonder({ tur: "sabitle", hazirAyarId: "taslak" });
  const kesin = gonder({ tur: "kesinMod", acik: true });
  await tik();
  assert.equal(bekleyenler.length, 1, "ikinci işlem sırada beklemeli");

  // Durum okuması beklemez ve süren işi bildirir.
  const durum1 = gonder({ tur: "durum" });
  const ac = gonder({ tur: "paneliAc" });
  await tik();
  assert.deepEqual(bekleyenler.map((b) => b.istek.tur), ["kaldir", "durum", "paneliAc"]);
  bekleyenler[1].coz({ tamam: true, sabitleme: { etkin: true } });
  bekleyenler[2].coz({ tamam: true });
  assert.deepEqual(await durum1.yanit, { tamam: true, sabitleme: { etkin: true }, mesgul: "kaldir" });
  assert.deepEqual(await ac.yanit, { tamam: true });

  // kaldir biter → sıradaki sabitle host'a gider.
  bekleyenler[0].coz({ tamam: true });
  assert.deepEqual(await kaldir.yanit, { tamam: true });
  await tik();
  assert.equal(bekleyenler.length, 4);
  assert.deepEqual(bekleyenler[3].istek, { tur: "sabitle", hazirAyarId: "taslak" });

  const durum2 = gonder({ tur: "durum" });
  await tik();
  bekleyenler[4].coz({ tamam: true });
  assert.deepEqual(await durum2.yanit, { tamam: true, mesgul: "sabitle" });

  // sabitle hata verir → hata popup'a iletilir, sıra kilitlenmez: kesinMod çalışır.
  bekleyenler[3].coz({ tamam: false, hata: "Yazıcı ayarı yazılamadı." });
  assert.deepEqual(await sabitle.yanit, { tamam: false, hata: "Yazıcı ayarı yazılamadı.", ulasilamadi: false });
  await tik();
  assert.equal(bekleyenler.length, 6);
  assert.deepEqual(bekleyenler[5].istek, { tur: "kesinMod", acik: true });
  bekleyenler[5].coz({ tamam: true });
  assert.deepEqual(await kesin.yanit, { tamam: true });

  // Hepsi bitti: durum yanıtında `mesgul` yok.
  const durum3 = gonder({ tur: "durum" });
  await tik();
  bekleyenler[6].coz({ tamam: true, bekleyenIs: 0 });
  assert.deepEqual(await durum3.yanit, { tamam: true, bekleyenIs: 0 });
});

test("sıra: host'a ulaşılamayan işlem sırayı kilitlemez", async () => {
  let sayac = 0;
  const { dinleyiciler, gonderilenler } = ortamKur(() =>
    ++sayac === 1 ? Promise.reject(new Error("Native host has exited.")) : Promise.resolve({ tamam: true })
  );
  const gonder = (istek) => mesajBaslat(dinleyiciler.mesaj[0], istek);
  const ilk = gonder({ tur: "kaldir" });
  const ikinci = gonder({ tur: "kesinMod", acik: false });
  assert.deepEqual(await ilk.yanit, { tamam: false, hata: ULASILAMADI, ulasilamadi: true });
  assert.deepEqual(await ikinci.yanit, { tamam: true });
  assert.deepEqual(
    gonderilenler.map((g) => duzJson(g.istek)),
    [{ tur: "kaldir" }, { tur: "kesinMod", acik: false }]
  );
});

test("sıra: zaman aşımına uğrayan işlemden sonra sıradaki çalışır", async () => {
  const { host, bekleyenler } = elleHost();
  const { baglam, dinleyiciler } = ortamKur(host);
  // 60 sn beklememek için zaman aşımını Map'te kısalt.
  vm.runInContext('PANEL_ISTEKLERI.set("kaldir", 20); PANEL_ISTEKLERI.set("sabitle", 1000);', baglam);
  const gonder = (istek) => mesajBaslat(dinleyiciler.mesaj[0], istek);
  const kaldir = gonder({ tur: "kaldir" });
  const sabitle = gonder({ tur: "sabitle", hazirAyarId: "x" });
  const y = await kaldir.yanit;
  assert.equal(y.tamam, false);
  assert.match(y.hata, /zamanında yanıt vermedi/);
  await tik();
  assert.deepEqual(bekleyenler.map((b) => b.istek.tur), ["kaldir", "sabitle"]);
  bekleyenler[1].coz({ tamam: true });
  assert.deepEqual(await sabitle.yanit, { tamam: true });
});
