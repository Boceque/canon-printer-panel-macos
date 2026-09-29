#!/bin/zsh
# Yazıcı Paneli.app paketini derler, imzalar ve /Applications'a kurar.
#   ./derle.sh           derle + /Applications/Yazıcı Paneli.app olarak kur
#   ./derle.sh --kurma   yalnız proje klasörüne paketle (kurmadan dene)
# Kesin moddaki arka plan görevlisi /Applications'taki kopyayı çalıştırır:
# launchd, Masaüstü'ndeki programları çalıştıramayabiliyor.
set -e
cd "$(dirname "$0")"

swift build -c release

# İkon bir kez üretilir
if [[ ! -f Destek/AppIcon.icns ]]; then
    gecici=$(mktemp -d)
    swift Destek/ikon-uret.swift "$gecici/ikon.png"
    mkdir -p "$gecici/AppIcon.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$gecici/ikon.png" --out "$gecici/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$gecici/ikon.png" --out "$gecici/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$gecici/AppIcon.iconset" -o Destek/AppIcon.icns
fi

# Paket önce ayrı yerde kurulup imzalanır; rsync dosyaları yeni kopya + yeniden adlandırmayla
# değiştirir, böylece uygulama açıkken derlense de çalışan kopyanın dosyası altından değişmez.
PAKET=".build/paket/Yazıcı Paneli.app"
mkdir -p "$PAKET/Contents/MacOS" "$PAKET/Contents/Resources"
cp -f .build/release/YaziciPaneli "$PAKET/Contents/MacOS/YaziciPaneli"
cp -f Destek/Info.plist "$PAKET/Contents/Info.plist"
cp -f Destek/AppIcon.icns "$PAKET/Contents/Resources/AppIcon.icns"
# Chrome eklentisi paketle birlikte taşınır; uygulama onu Application Support'a kopyalar.
rsync -a --delete --exclude test "Chrome Eklentisi/" "$PAKET/Contents/Resources/Chrome Eklentisi/"
codesign --force --sign - "$PAKET" >/dev/null 2>&1

if [[ "$1" == "--kurma" ]]; then
    APP="Yazıcı Paneli.app"
    mkdir -p "$APP"
    rsync -a "$PAKET/" "$APP/"
    touch "$APP"
    echo "Hazır: $(pwd)/$APP"
    if [[ -d "/Applications/Yazıcı Paneli.app" ]]; then
        echo "Not: Chrome köprüsü ve eklentisi /Applications'taki kopyadan gelir; bu kopyadaki Chrome değişikliklerini denemek için ./derle.sh ile kurun."
    else
        echo "Chrome eklentisi değiştiyse: uygulamayı açın, sonra chrome://extensions › Yazıcı Paneli › ↻ (Yeniden yükle)."
    fi
    exit 0
fi

HEDEF="/Applications/Yazıcı Paneli.app"
mkdir -p "$HEDEF"
rsync -a "$PAKET/" "$HEDEF/"
touch "$HEDEF"

# Kesin mod görevlisi çalışıyorsa yeni sürüme geçsin
GOREVLI="gui/$(id -u)/com.caglar.yazicipaneli.gorevli"
if launchctl print "$GOREVLI" >/dev/null 2>&1; then
    launchctl kickstart -k "$GOREVLI" >/dev/null 2>&1 || true
fi

# Chrome köprüsü (native messaging manifest'i) ve eklenti dosyaları. Eklenti dosyası değişince
# uygulama bu işaret dosyasını yeniler; Chrome ise arka planı kendiliğinden yenilemez.
ISARET="$HOME/Library/Application Support/Yazıcı Paneli/chrome-eklenti-guncelleme.json"
onceki_isaret=$(cat "$ISARET" 2>/dev/null || true)
"$HEDEF/Contents/MacOS/YaziciPaneli" --chrome-kur || true

echo "Kuruldu: $HEDEF"
if [[ "$(cat "$ISARET" 2>/dev/null || true)" != "$onceki_isaret" ]]; then
    echo "Chrome eklentisi güncellendi: chrome://extensions › Yazıcı Paneli › ↻ (Yeniden yükle) düğmesine basın."
fi
