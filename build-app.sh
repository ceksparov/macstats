#!/bin/bash
# Derlenmiş programı çift tıklanabilir bir .app paketine koyar.
#
# Neden gerekli: menü bar uygulamasının Dock'ta görünmemesi, ileride
# "girişte başlat" gibi özelliklerin çalışması ve uygulamanın kendi ikonuna
# sahip olması sadece gerçek bir .app paketi içinde mümkün. "swift run" ile
# çalıştırdığında bunların hiçbiri geçerli olmaz.

set -euo pipefail

cd "$(dirname "$0")"

PAKET="macstats.app"
PROGRAM="macstats-app"

# Sürüm numarasının tek yazıldığı yer git etiketi. Kaynak koda sabit bir sürüm
# yazmak, yayınlanan paketin bir numara söyleyip içindeki uygulamanın başka bir
# numara söylemesiyle sonuçlanır — o yüzden buradan türetiyoruz.
SURUM="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo '0.0.0')"

echo "==> Sürüm ${SURUM} derleniyor (universal: arm64 + x86_64)"
# --arch iki kere verilince SwiftPM ikisini de derleyip tek bir "fat" ikili
# olarak birleştiriyor (lipo). Bu şart: sadece arm64 derlersek Intel Mac'ler
# uygulamayı hiç açamaz — Rosetta x86_64'ü arm64'e çevirir, tersini yapmaz.
# Bizim Intel yedek yolumuz (SicaklikSMC.swift) universal olmayan bir
# ikilikte hiç çalıştırılamayacak, ölü kod olarak kalırdı.
swift build -c release --arch arm64 --arch x86_64 --product "${PROGRAM}"

echo "==> ${PAKET} paketleniyor"
rm -rf "${PAKET}"
mkdir -p "${PAKET}/Contents/MacOS"
mkdir -p "${PAKET}/Contents/Resources"

cp ".build/apple/Products/Release/${PROGRAM}" "${PAKET}/Contents/MacOS/${PROGRAM}"

if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "${PAKET}/Contents/Resources/AppIcon.icns"
fi

cat > "${PAKET}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>macstats</string>
    <key>CFBundleDisplayName</key>       <string>macstats</string>
    <key>CFBundleIdentifier</key>        <string>com.github.ceksparov.macstats</string>
    <key>CFBundleExecutable</key>        <string>${PROGRAM}</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${SURUM}</string>
    <key>CFBundleVersion</key>           <string>${SURUM}</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>

    <!-- Dock'ta ikon gösterme, cmd-tab listesinde çıkma. Yeri sadece menü barı. -->
    <key>LSUIElement</key>               <true/>
</dict>
</plist>
PLIST

echo "==> Hazır: $(pwd)/${PAKET}"
echo "    Çalıştırmak için:  open ${PAKET}"
echo "    Mimariler:         $(lipo -info "${PAKET}/Contents/MacOS/${PROGRAM}" 2>/dev/null | sed 's/.*: //')"
