#!/bin/bash
# Piples Sprite Tool - APK Build Script

echo "🎮 Piples Sprite Tool - APK Build"
echo "=================================="

# Flutter kontrol
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter bulunamadı!"
    echo "Kurulum: https://docs.flutter.dev/get-started/install"
    exit 1
fi

echo "✅ Flutter sürümü:"
flutter --version

# Temizle
echo ""
echo "🧹 Eski build'ları temizleme..."
flutter clean

# Bağımlılıklar
echo ""
echo "📦 Bağımlılıkları yükleme..."
flutter pub get

# Analiz
echo ""
echo "🔍 Kod analizi..."
flutter analyze || true

# APK Build
echo ""
echo "🔨 Release APK build ediliyor..."
flutter build apk --release

# Sonuç
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ BAŞARILI!"
    echo ""
    echo "📱 APK konumu:"
    echo "   build/app/outputs/flutter-apk/app-release.apk"
    echo ""
    echo "📲 Cihaza yükleme:"
    echo "   adb install build/app/outputs/flutter-apk/app-release.apk"
else
    echo ""
    echo "❌ Build başarısız!"
    exit 1
fi
