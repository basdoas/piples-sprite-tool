import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Piples Sprite Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1f6aa5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(cameras: cameras),
    );
  }
}

// ============================================================================
// GÖRÜNTÜ İŞLEME FONKSİYONLARI
// ============================================================================

class ImageProcessor {
  /// Gaussian blur (basit implementasyon)
  static List<List<double>> _gaussianBlur(List<List<double>> input, int radius) {
    final h = input.length;
    final w = input[0].length;
    final result = List.generate(h, (_) => List<double>.filled(w, 0));
    
    // Yatay blur
    final temp = List.generate(h, (_) => List<double>.filled(w, 0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double sum = 0;
        int count = 0;
        for (int k = -radius; k <= radius; k++) {
          final nx = x + k;
          if (nx >= 0 && nx < w) {
            sum += input[y][nx];
            count++;
          }
        }
        temp[y][x] = sum / count;
      }
    }
    
    // Dikey blur
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double sum = 0;
        int count = 0;
        for (int k = -radius; k <= radius; k++) {
          final ny = y + k;
          if (ny >= 0 && ny < h) {
            sum += temp[ny][x];
            count++;
          }
        }
        result[y][x] = sum / count;
      }
    }
    
    return result;
  }

  /// Gauss bulanıklığı (büyük kernel için integral image kullanarak)
  static List<List<double>> _fastGaussianBlur(List<List<double>> input, int radius) {
    final h = input.length;
    final w = input[0].length;
    final result = List.generate(h, (_) => List<double>.filled(w, 0));
    
    // Integral image oluştur
    final integral = List.generate(h + 1, (_) => List<double>.filled(w + 1, 0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        integral[y + 1][x + 1] = input[y][x] + 
            integral[y][x + 1] + integral[y + 1][x] - integral[y][x];
      }
    }
    
    // Box blur uygula
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x1 = math.max(0, x - radius);
        final y1 = math.max(0, y - radius);
        final x2 = math.min(w - 1, x + radius);
        final y2 = math.min(h - 1, y + radius);
        
        final count = (x2 - x1 + 1) * (y2 - y1 + 1);
        final sum = integral[y2 + 1][x2 + 1] - integral[y1][x2 + 1] - 
                   integral[y2 + 1][x1] + integral[y1][x1];
        result[y][x] = sum / count;
      }
    }
    
    return result;
  }

  /// Bağlı bileşenleri bul (flood fill algoritması)
  static List<List<int>> _connectedComponents(List<List<int>> binary) {
    final h = binary.length;
    final w = binary[0].length;
    final labels = List.generate(h, (_) => List<int>.filled(w, 0));
    int currentLabel = 0;
    
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (binary[y][x] == 255 && labels[y][x] == 0) {
          currentLabel++;
          _floodFill(binary, labels, x, y, w, h, currentLabel);
        }
      }
    }
    
    return labels;
  }
  
  static void _floodFill(List<List<int>> binary, List<List<int>> labels, 
                        int startX, int startY, int w, int h, int label) {
    final stack = [(startX, startY)];
    
    while (stack.isNotEmpty) {
      final (x, y) = stack.removeLast();
      
      if (x < 0 || x >= w || y < 0 || y >= h) continue;
      if (binary[y][x] != 255 || labels[y][x] != 0) continue;
      
      labels[y][x] = label;
      
      stack.add((x + 1, y));
      stack.add((x - 1, y));
      stack.add((x, y + 1));
      stack.add((x, y - 1));
    }
  }

  /// Genişletme (dilate) işlemi
  static List<List<int>> _dilate(List<List<int>> input, int iterations) {
    int h = input.length;
    int w = input[0].length;
    var result = List.generate(h, (y) => List<int>.from(input[y]));
    
    for (int iter = 0; iter < iterations; iter++) {
      final temp = List.generate(h, (y) => List<int>.from(result[y]));
      
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          // 3x3 komşuluk kontrolü
          bool hasNeighbor = false;
          for (int dy = -1; dy <= 1 && !hasNeighbor; dy++) {
            for (int dx = -1; dx <= 1 && !hasNeighbor; dx++) {
              if (temp[y + dy][x + dx] == 255) {
                hasNeighbor = true;
              }
            }
          }
          if (hasNeighbor) {
            result[y][x] = 255;
          }
        }
      }
    }
    
    return result;
  }

  /// Ana sprite çıkarma fonksiyonu
  static img.Image extractSprite(
    img.Image source, {
    int threshold = 35,
    int minArea = 50,
    int dilateIter = 1,
  }) {
    final w = source.width;
    final h = source.height;
    
    // Grayscale'e çevir
    final gray = List.generate(h, (_) => List<double>.filled(w, 0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = source.getPixel(x, y);
        gray[y][x] = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      }
    }
    
    // Gauss bulanıklığı (arka plan tahmini için)
    final bg = _fastGaussianBlur(gray, 50);
    
    // Fark hesapla (bg - gray, sadece pozitif)
    final diff = List.generate(h, (_) => List<double>.filled(w, 0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        diff[y][x] = math.max(0, bg[y][x] - gray[y][x]);
      }
    }
    
    // Normalize (0-255 arasına)
    double minVal = diff[0][0], maxVal = diff[0][0];
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (diff[y][x] < minVal) minVal = diff[y][x];
        if (diff[y][x] > maxVal) maxVal = diff[y][x];
      }
    }
    
    final normalized = List.generate(h, (_) => List<double>.filled(w, 0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (maxVal > minVal) {
          normalized[y][x] = 255 * (diff[y][x] - minVal) / (maxVal - minVal);
        }
      }
    }
    
    // Threshold uygula
    final binary = List.generate(h, (_) => List<int>.filled(w, 0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        binary[y][x] = normalized[y][x] > threshold ? 255 : 0;
      }
    }
    
    // Bağlı bileşenleri bul ve filtrele
    final labels = _connectedComponents(binary);
    
    // Her etiketin alanını hesapla
    final areas = <int, int>{};
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final label = labels[y][x];
        if (label > 0) {
          areas[label] = (areas[label] ?? 0) + 1;
        }
      }
    }
    
    // Min alan filtresi uygula
    final clean = List.generate(h, (_) => List<int>.filled(w, 0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final label = labels[y][x];
        if (label > 0 && (areas[label] ?? 0) >= minArea) {
          clean[y][x] = 255;
        }
      }
    }
    
    // Genişletme (dilate) uygula
    final dilated = _dilate(clean, dilateIter);
    
    // RGBA görüntü oluştur (koyu kahve renk: [25, 18, 12])
    final rgba = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (dilated[y][x] > 0) {
          rgba.setPixelRgba(x, y, 25, 18, 12, 255);
        } else {
          rgba.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
    
    // Bounding box bul ve kırp
    int minX = w, minY = h, maxX = 0, maxY = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (dilated[y][x] > 0) {
          minX = math.min(minX, x);
          minY = math.min(minY, y);
          maxX = math.max(maxX, x);
          maxY = math.max(maxY, y);
        }
      }
    }
    
    if (minX < maxX && minY < maxY) {
      const pad = 25;
      final cropX = math.max(0, minX - pad);
      final cropY = math.max(0, minY - pad);
      final cropW = math.min(w - cropX, maxX - minX + 1 + pad * 2);
      final cropH = math.min(h - cropY, maxY - minY + 1 + pad * 2);
      
      final cropped = img.copyCrop(rgba, x: cropX, y: cropY, width: cropW, height: cropH);
      
      // 512x512'ye sığdır
      if (cropped.width > 512 || cropped.height > 512) {
        return img.copyResize(cropped, width: 512, height: 512, interpolation: img.Interpolation.cubic);
      }
      return cropped;
    }
    
    return rgba;
  }

  // ==========================================================================
  // WIGGLE ANİMASYONU
  // ==========================================================================

  /// Gürültü alanı oluştur (Perlin-like noise)
  static List<List<double>> _makeNoiseField(int h, int w, double t, double scale) {
    final noise = List.generate(h, (_) => List<double>.filled(w, 0));
    
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final X = x * 4 * math.pi / w;
        final Y = y * 4 * math.pi / h;
        
        double value = 
            math.sin(X * 1.0 + t * 1.7) * 0.40 +
            math.sin(Y * 1.2 + t * 1.3) * 0.40 +
            math.sin((X + Y) * 0.8 + t * 2.1) * 0.30 +
            math.sin(X * 2.3 - t * 0.9) * 0.20 +
            math.sin(Y * 2.7 + t * 1.1) * 0.20 +
            math.sin((X - Y) * 1.5 + t * 1.8) * 0.15;
        
        noise[y][x] = value * scale / 1.65;
      }
    }
    
    return noise;
  }

  /// Görüntüyü bük (wiggle frame)
  static img.Image _wiggleFrame(img.Image source, double t, double strength) {
    final w = source.width;
    final h = source.height;
    final dx = _makeNoiseField(h, w, t, strength);
    final dy = _makeNoiseField(h, w, t + 100, strength * 0.7);
    
    final result = img.Image(width: w, height: h);
    
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // Kaynak koordinatları hesapla
        double sx = (x - dx[y][x]).clamp(0, w - 1);
        double sy = (y - dy[y][x]).clamp(0, h - 1);
        
        // Bilineer interpolasyon
        int x0 = sx.floor();
        int y0 = sy.floor();
        int x1 = (x0 + 1).clamp(0, w - 1);
        int y1 = (y0 + 1).clamp(0, h - 1);
        
        double fx = sx - x0;
        double fy = sy - y0;
        
        final p00 = source.getPixel(x0, y0);
        final p10 = source.getPixel(x1, y0);
        final p01 = source.getPixel(x0, y1);
        final p11 = source.getPixel(x1, y1);
        
        final r = _bilinear(p00.r, p10.r, p01.r, p11.r, fx, fy);
        final g = _bilinear(p00.g, p10.g, p01.g, p11.g, fx, fy);
        final b = _bilinear(p00.b, p10.b, p01.b, p11.b, fx, fy);
        final a = _bilinear(p00.a, p10.a, p01.a, p11.a, fx, fy);
        
        result.setPixelRgba(x, y, r.toInt(), g.toInt(), b.toInt(), a.toInt());
      }
    }
    
    return result;
  }
  
  static double _bilinear(num tl, num tr, num bl, num br, double fx, double fy) {
    return tl * (1 - fx) * (1 - fy) + 
           tr * fx * (1 - fy) + 
           bl * (1 - fx) * fy + 
           br * fx * fy;
  }

  /// Wiggle animasyonu oluştur
  static List<img.Image> createWiggle(
    img.Image sprite, {
    int nFrames = 7,
    double strength = 3.2,
    int totalMs = 1040,
  }) {
    const pad = 6;
    
    // Padding ekle
    final canvas = img.Image(width: sprite.width + pad * 2, height: sprite.height + pad * 2);
    img.compositeImage(canvas, sprite, dstX: pad, dstY: pad);
    
    final random = math.Random(42);
    final frames = <img.Image>[];
    
    // Zaman değerlerini hesapla
    for (int i = 0; i < nFrames; i++) {
      final baseT = 2 * math.pi * i / nFrames;
      final t = baseT + random.nextDouble() * 1.6 - 0.8; // +/- 0.8 rastgelelik
      frames.add(_wiggleFrame(canvas, t, strength));
    }
    
    return frames;
  }

  /// GIF dosyası oluştur (basit GIF89a formatı)
  static Uint8List createGif(List<img.Image> frames, {int delayMs = 148}) {
    // GIF oluşturmak için image paketinin encoder'ını kullan
    final animation = img.Animation();
    
    for (final frame in frames) {
      animation.addFrame(frame);
    }
    
    // GIF encode et
    return Uint8List.fromList(img.encodeGifAnimation(animation) ?? []);
  }

  /// Spritesheet oluştur
  static img.Image createSpritesheet(List<img.Image> frames) {
    if (frames.isEmpty) return img.Image(width: 1, height: 1);
    
    final fw = frames[0].width;
    final fh = frames[0].height;
    final sheet = img.Image(width: fw * frames.length, height: fh);
    
    for (int i = 0; i < frames.length; i++) {
      img.compositeImage(sheet, frames[i], dstX: i * fw, dstY: 0);
    }
    
    return sheet;
  }
}

// ============================================================================
// UI EKRANLARI
// ============================================================================

class HomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const HomeScreen({super.key, required this.cameras});

  Future<void> _checkPermissions() async {
    await Permission.camera.request();
    await Permission.storage.request();
    await Permission.photos.request();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.videogame_asset,
                  size: 80,
                  color: Color(0xFF4CAF50),
                ),
                const SizedBox(height: 24),
                const Text(
                  '🎮 Piples Sprite Tool',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Karakalem → PNG + GIF + Sheet',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 48),
                _buildButton(
                  context: context,
                  icon: Icons.camera_alt,
                  label: '📷 Fotoğraf Çek',
                  onPressed: () async {
                    await _checkPermissions();
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CameraScreen(cameras: cameras),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildButton(
                  context: context,
                  icon: Icons.photo_library,
                  label: '🖼 Galeriden Seç',
                  onPressed: () async {
                    await _checkPermissions();
                    final picker = ImagePicker();
                    final image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null && context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PreviewScreen(
                            imagePath: image.path,
                            fromCamera: false,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1f6aa5),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller.initialize();
    setState(() => _isReady = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (!_controller.value.isInitialized) return;
    
    try {
      final image = await _controller.takePicture();
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PreviewScreen(
              imagePath: image.path,
              fromCamera: true,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Fotoğraf çekme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isReady
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller),
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FloatingActionButton.large(
                      onPressed: _takePhoto,
                      backgroundColor: Colors.white,
                      child: const Icon(
                        Icons.camera,
                        color: Colors.black,
                        size: 40,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 48,
                  left: 16,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 32),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

class PreviewScreen extends StatefulWidget {
  final String imagePath;
  final bool fromCamera;
  
  const PreviewScreen({
    super.key,
    required this.imagePath,
    required this.fromCamera,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final TextEditingController _nameController = TextEditingController();
  
  // Parametreler
  double _threshold = 35;
  double _minArea = 50;
  double _dilate = 1;
  double _wiggleStrength = 3.2;
  
  // Checkbox'lar
  bool _savePng = true;
  bool _saveGif = true;
  bool _saveSheet = true;
  
  // Durum
  bool _isProcessing = false;
  img.Image? _originalImage;
  img.Image? _processedSprite;
  List<img.Image>? _wiggleFrames;
  int _currentPreviewFrame = 0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final file = File(widget.imagePath);
    final bytes = await file.readAsBytes();
    _originalImage = img.decodeImage(bytes);
    
    // Dosya adından isim öner
    final fileName = path.basenameWithoutExtension(widget.imagePath);
    _nameController.text = fileName;
    
    setState(() {});
  }

  Future<void> _processImage() async {
    if (_originalImage == null) return;
    
    setState(() => _isProcessing = true);
    
    await Future.delayed(const Duration(milliseconds: 100)); // UI güncellensin
    
    try {
      // Sprite çıkar
      _processedSprite = ImageProcessor.extractSprite(
        _originalImage!,
        threshold: _threshold.round(),
        minArea: _minArea.round(),
        dilateIter: _dilate.round(),
      );
      
      // Wiggle animasyonu oluştur
      if (_saveGif || _saveSheet) {
        _wiggleFrames = ImageProcessor.createWiggle(
          _processedSprite!,
          nFrames: 7,
          strength: _wiggleStrength,
        );
        
        // Animasyon önizlemesi için timer başlat
        _startAnimation();
      }
      
      setState(() => _isProcessing = false);
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  void _startAnimation() {
    Future.doWhile(() async {
      if (!mounted || _wiggleFrames == null) return false;
      await Future.delayed(const Duration(milliseconds: 148));
      if (mounted && _wiggleFrames != null) {
        setState(() {
          _currentPreviewFrame = (_currentPreviewFrame + 1) % _wiggleFrames!.length;
        });
      }
      return mounted && _wiggleFrames != null;
    });
  }

  Future<void> _saveFiles() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir isim girin!')),
      );
      return;
    }

    if (_processedSprite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce "İşle" butonuna tıklayın!')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final dir = await getExternalStorageDirectory();
      final saveDir = Directory('${dir?.path}/PiplesSprites');
      await saveDir.create(recursive: true);
      
      final savedFiles = <String>[];

      // PNG kaydet
      if (_savePng) {
        final pngPath = path.join(saveDir.path, '$name.png');
        final pngBytes = img.encodePng(_processedSprite!);
        await File(pngPath).writeAsBytes(pngBytes);
        savedFiles.add('PNG');
      }

      // GIF ve/veya Spritesheet için frame'ler lazım
      if ((_saveGif || _saveSheet) && _wiggleFrames != null) {
        // GIF kaydet
        if (_saveGif) {
          final gifPath = path.join(saveDir.path, '${name}_wiggle.gif');
          final animation = img.Animation();
          for (final frame in _wiggleFrames!) {
            animation.addFrame(frame);
          }
          final gifBytes = img.encodeGifAnimation(animation);
          if (gifBytes != null) {
            await File(gifPath).writeAsBytes(gifBytes);
            savedFiles.add('GIF');
          }
        }

        // Spritesheet kaydet
        if (_saveSheet) {
          final sheet = ImageProcessor.createSpritesheet(_wiggleFrames!);
          final sheetPath = path.join(saveDir.path, '${name}_sheet.png');
          final sheetBytes = img.encodePng(sheet);
          await File(sheetPath).writeAsBytes(sheetBytes);
          savedFiles.add('Sheet');
        }
      }

      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ Kaydedildi: ${savedFiles.join(", ")}')),
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213e),
        title: const Text('Sprite İşleyici'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: _originalImage == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Önizleme
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey),
                        color: const Color(0xFFF8F5F0),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildPreview(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // İsim girişi
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Sprite Adı',
                      hintText: 'örn: piple_back_side_right',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF16213e),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 24),

                  // Threshold
                  _buildSlider(
                    label: 'Threshold (düşük = daha fazla çizgi)',
                    value: _threshold,
                    min: 10,
                    max: 80,
                    onChanged: (v) => setState(() => _threshold = v),
                  ),

                  // Min Alan
                  _buildSlider(
                    label: 'Min Alan (gürültü filtresi)',
                    value: _minArea,
                    min: 10,
                    max: 300,
                    onChanged: (v) => setState(() => _minArea = v),
                  ),

                  // Dilate
                  _buildSlider(
                    label: 'Kalınlık (dilate)',
                    value: _dilate,
                    min: 1,
                    max: 4,
                    divisions: 3,
                    onChanged: (v) => setState(() => _dilate = v),
                  ),

                  const Divider(height: 32, color: Colors.grey),

                  // Wiggle Kuvveti
                  _buildSlider(
                    label: 'Wiggle Kuvveti',
                    value: _wiggleStrength,
                    min: 1.0,
                    max: 6.0,
                    onChanged: (v) => setState(() => _wiggleStrength = v),
                  ),

                  const SizedBox(height: 16),

                  // Kaydetme seçenekleri
                  const Text(
                    'Kaydetme Seçenekleri:',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('Statik PNG'),
                    value: _savePng,
                    onChanged: (v) => setState(() => _savePng = v ?? true),
                    activeColor: const Color(0xFF1f6aa5),
                  ),
                  CheckboxListTile(
                    title: const Text('Wiggle GIF'),
                    value: _saveGif,
                    onChanged: (v) => setState(() => _saveGif = v ?? true),
                    activeColor: const Color(0xFF1f6aa5),
                  ),
                  CheckboxListTile(
                    title: const Text('Spritesheet PNG'),
                    value: _saveSheet,
                    onChanged: (v) => setState(() => _saveSheet = v ?? true),
                    activeColor: const Color(0xFF1f6aa5),
                  ),

                  const SizedBox(height: 24),

                  // Butonlar
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _processImage,
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.auto_fix_high),
                          label: const Text('👁 Önizle', style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _saveFiles,
                          icon: const Icon(Icons.save),
                          label: const Text('💾 Kaydet', style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1f6aa5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPreview() {
    if (_wiggleFrames != null && _wiggleFrames!.isNotEmpty) {
      // Animasyonlu wiggle göster
      final frame = _wiggleFrames![_currentPreviewFrame % _wiggleFrames!.length];
      final bytes = img.encodePng(frame);
      return Image.memory(
        Uint8List.fromList(bytes),
        fit: BoxFit.contain,
      );
    } else if (_processedSprite != null) {
      // İşlenmiş sprite göster
      final bytes = img.encodePng(_processedSprite!);
      return Image.memory(
        Uint8List.fromList(bytes),
        fit: BoxFit.contain,
      );
    } else {
      // Orijinal göster
      return Image.file(
        File(widget.imagePath),
        fit: BoxFit.contain,
      );
    }
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions ?? (max - min).round(),
          label: value.toStringAsFixed(divisions == null ? 0 : 1),
          onChanged: onChanged,
          activeColor: const Color(0xFF1f6aa5),
        ),
        Text(
          value.toStringAsFixed(divisions == null ? 0 : 1),
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
