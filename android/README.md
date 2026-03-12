# Piples Sprite Tool - Mobile

Android için Flutter ile geliştirilmiş mobil versiyon.

## 🎮 Özellikler

### Girdi
- 📷 Uygulama içinden fotoğraf çekme
- 🖼 Galeriden fotoğraf seçme

### İşleme (Masaüstü ile Aynı)
- ✏️ Sprite Adı belirleme
- 🔧 **Threshold** (10-80): Düşük = daha fazla çizgi
- 📊 **Min Alan** (10-300): Gürültü filtresi
- ➕ **Kalınlık/Dilate** (1-4): Çizgi kalınlaştırma
- 🌊 **Wiggle Kuvveti** (1.0-6.0): Animasyon şiddeti

### Çıktılar
- 💾 **Statik PNG** - Şeffaf arka planlı sprite
- 🎬 **Wiggle GIF** - 7 karelik animasyon (1040ms)
- 📑 **Spritesheet PNG** - Tüm kareler yan yana

## 📋 Gereksinimler

- Flutter SDK 3.0+
- Android Studio / VS Code
- Android SDK 21+
- Android cihaz/emülatör (kamera için)

## 📱 APK İndirme (En Kolay Yöntem)

GitHub Actions otomatik build alır, Flutter kurmanıza gerek yok!

### 1. Projeyi GitHub'a Yükle

```bash
# GitHub hesabınızda yeni repo oluşturun (örn: piples-sprite-tool-mobile)

# Bu komutları terminalde çalıştırın:
cd piples-sprite-tool-mobile
git init
git add .
git commit -m "İlk yükleme"
git branch -M main
# KENDİ_REPO_URL_NİZ ile değiştirin:
git remote add origin https://github.com/KULLANICI_ADINIZ/piples-sprite-tool-mobile.git
git push -u origin main
```

### 2. APK'yı İndir

GitHub'a push yaptıktan 3-5 dakika sonra:

**Seçenek A - GitHub Actions'dan:**
1. GitHub repo sayfasına git
2. **Actions** sekmesine tıkla
3. En üstteki yeşil tikli workflow'a tıkla
4. En alttaki **Artifacts** bölümünden `piples-sprite-tool-apk` indir

**Seçenek B - Release'den (Tag oluşturursan):**
```bash
git tag v1.0.0
git push origin v1.0.0
```
Tag push edince otomatik Release oluşur ve APK orada olur.

## 🛠 Geliştirme (Flutter Kurulumu)

Kendiniz build almak isterseniz:

```bash
# 1. Flutter'ı kur: https://docs.flutter.dev/get-started/install

# 2. Projeye git
cd piples-sprite-tool-mobile

# 3. Bağımlılıkları yükle
flutter pub get

# 4. Çalıştır (debug)
flutter run

# 5. Veya APK build al
flutter build apk --release
# APK: build/app/outputs/flutter-apk/app-release.apk
```

## 🔐 İzinler

AndroidManifest.xml'de tanımlı izinler:
- `CAMERA` - Fotoğraf çekmek için
- `READ_EXTERNAL_STORAGE` - Galeriye erişmek için
- `WRITE_EXTERNAL_STORAGE` - Dosyaları kaydetmek için

## 📁 Kayıt Konumu

Tüm çıktılar: `/sdcard/Android/data/com.example.piples_sprite_tool_mobile/files/PiplesSprites/`

## 🔄 Masaüstü vs Mobil Karşılaştırma

| Özellik | Python Masaüstü | Flutter Mobil |
|---------|-----------------|---------------|
| Kamera | ❌ | ✅ |
| Galeri | ✅ | ✅ |
| Gaussian Blur | ✅ (OpenCV) | ✅ (Custom) |
| Bağlı Bileşenler | ✅ (OpenCV) | ✅ (Flood Fill) |
| Dilate | ✅ (OpenCV) | ✅ (Custom) |
| Wiggle Animasyonu | ✅ (NumPy) | ✅ (Pure Dart) |
| GIF Export | ✅ (PIL) | ✅ (image package) |
| Spritesheet | ✅ (PIL) | ✅ (image package) |

## 📝 Notlar

- Tüm görüntü işleme algoritmaları Dart ile sıfırdan yazıldı
- OpenCV/NumPy bağımlılığı yok
- Wiggle animasyonu gerçek zamanlı önizleme destekler
- Maksimum çıktı boyutu: 512x512

## 🐛 Bilinen Sorunlar

- Büyük görüntülerde işlem biraz yavaş olabilir
- GIF kaydetme bazen uzun sürebilir (7 kare render ediliyor)
