#piples sprite tool
#for game labyrinthoteka

#made by dosulu claude and some love <3

#!/usr/bin/env python3
"""
Piples Sprite Extractor Tool
Karakalem fotoğrafından şeffaf PNG + wiggle GIF + spritesheet üretir.

Gereksinimler:
pip install customtkinter opencv-python-headless pillow numpy
"""

import customtkinter as ctk
from tkinter import filedialog, messagebox
import cv2
import numpy as np
from PIL import Image, ImageTk
import threading
import os

# ── Tema ──────────────────────────────────────────────────────────────
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")


# ── Görüntü İşleme Fonksiyonları ─────────────────────────────────────

def extract_sprite(img_path, threshold, min_area, dilate_iter):
    img = cv2.imread(img_path)
    if img is None:
        raise ValueError(f"Görüntü açılamadı: {img_path}")
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    bg = cv2.GaussianBlur(gray, (201, 201), 0)
    diff = np.clip(bg.astype(np.int16) - gray.astype(np.int16), 0, 255).astype(np.uint8)
    norm = cv2.normalize(diff, None, 0, 255, cv2.NORM_MINMAX)
    _, binary = cv2.threshold(norm, threshold, 255, cv2.THRESH_BINARY)
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(binary)
    clean = np.zeros_like(binary)
    for i in range(1, num_labels):
        if stats[i, cv2.CC_STAT_AREA] >= min_area:
            clean[labels == i] = 255
    k = np.ones((dilate_iter + 1, dilate_iter + 1), np.uint8)
    clean = cv2.dilate(clean, k, iterations=dilate_iter)
    h, w = clean.shape
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[clean > 0] = [25, 18, 12, 255]
    pil = Image.fromarray(rgba, 'RGBA')
    bbox = pil.getbbox()
    if bbox:
        pad = 25
        box = (max(0, bbox[0]-pad), max(0, bbox[1]-pad),
               min(pil.width, bbox[2]+pad), min(pil.height, bbox[3]+pad))
        pil = pil.crop(box)
    pil.thumbnail((512, 512), Image.LANCZOS)
    return pil


def make_noise_field(h, w, t, scale=1.0):
    y_c = np.linspace(0, 4*np.pi, h)
    x_c = np.linspace(0, 4*np.pi, w)
    Y, X = np.meshgrid(y_c, x_c, indexing='ij')
    noise = (
        np.sin(X*1.0+t*1.7)*0.40 + np.sin(Y*1.2+t*1.3)*0.40 +
        np.sin((X+Y)*0.8+t*2.1)*0.30 + np.sin(X*2.3-t*0.9)*0.20 +
        np.sin(Y*2.7+t*1.1)*0.20 + np.sin((X-Y)*1.5+t*1.8)*0.15
    )
    return noise * scale / 1.65


def wiggle_frame(arr, t, strength=3.2):
    h, w = arr.shape[:2]
    dx = make_noise_field(h, w, t, scale=strength)
    dy = make_noise_field(h, w, t+100, scale=strength*0.7)
    Y, X = np.meshgrid(np.arange(h), np.arange(w), indexing='ij')
    sx = np.clip(X-dx, 0, w-1)
    sy = np.clip(Y-dy, 0, h-1)
    x0 = sx.astype(np.int32); x1 = np.clip(x0+1, 0, w-1)
    y0 = sy.astype(np.int32); y1 = np.clip(y0+1, 0, h-1)
    fx = sx-x0; fy = sy-y0
    result = np.zeros_like(arr)
    for c in range(4):
        tl = arr[y0,x0,c].astype(np.float32); tr = arr[y0,x1,c].astype(np.float32)
        bl = arr[y1,x0,c].astype(np.float32); br = arr[y1,x1,c].astype(np.float32)
        result[:,:,c] = np.clip(
            tl*(1-fx)*(1-fy)+tr*fx*(1-fy)+bl*(1-fx)*fy+br*fx*fy, 0, 255
        ).astype(np.uint8)
    return result


def create_wiggle(sprite_pil, n_frames=7, strength=3.2, total_ms=1040):
    pad = 6
    canvas = Image.new('RGBA', (sprite_pil.width+pad*2, sprite_pil.height+pad*2), (0,0,0,0))
    canvas.paste(sprite_pil, (pad, pad))
    arr = np.array(canvas)
    rng = np.random.default_rng(42)
    t_values = np.linspace(0, 2*np.pi, n_frames, endpoint=False) + rng.uniform(-0.8, 0.8, n_frames)
    durations = [total_ms // n_frames] * n_frames
    durations[-1] += total_ms - sum(durations)
    frames = [Image.fromarray(wiggle_frame(arr, t, strength=strength), 'RGBA') for t in t_values]
    return frames, durations


# ── Ana Uygulama ──────────────────────────────────────────────────────

class SpriteToolApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("🎮 Piple Sprite Extractor")
        self.geometry("900x700")
        self.resizable(True, True)

        self.img_path = None
        self.sprite_pil = None
        self.preview_photo = None

        self._build_ui()

    def _build_ui(self):
        # Sol panel - kontroller
        left = ctk.CTkFrame(self, width=280)
        left.pack(side="left", fill="y", padx=10, pady=10)
        left.pack_propagate(False)

        ctk.CTkLabel(left, text="🎮 Sprite Extractor", font=("Arial", 18, "bold")).pack(pady=(15,5))
        ctk.CTkLabel(left, text="Karakalem → PNG + GIF + Sheet", font=("Arial", 11), text_color="gray").pack(pady=(0,15))

        # Dosya seç
        ctk.CTkButton(left, text="📁 Fotoğraf Seç", command=self._pick_file, height=40).pack(fill="x", padx=15, pady=5)
        self.file_label = ctk.CTkLabel(left, text="Dosya seçilmedi", font=("Arial", 10), text_color="gray", wraplength=240)
        self.file_label.pack(pady=2)

        ctk.CTkLabel(left, text="Çıktı Klasörü").pack(pady=(10,2))
        ctk.CTkButton(left, text="📂 Klasör Seç", command=self._pick_outdir, height=35).pack(fill="x", padx=15)
        self.outdir_label = ctk.CTkLabel(left, text="Masaüstü", font=("Arial", 10), text_color="gray", wraplength=240)
        self.outdir_label.pack(pady=2)
        self.out_dir = os.path.expanduser("~/Desktop")

        # Ayırıcı
        ctk.CTkFrame(left, height=2, fg_color="gray30").pack(fill="x", padx=15, pady=12)

        # Sprite adı
        ctk.CTkLabel(left, text="Sprite Adı").pack()
        self.name_entry = ctk.CTkEntry(left, placeholder_text="örn: piple_back_side_right")
        self.name_entry.pack(fill="x", padx=15, pady=5)

        # Threshold
        ctk.CTkLabel(left, text="Threshold (düşük = daha fazla çizgi)").pack()
        self.thresh_var = ctk.IntVar(value=35)
        self.thresh_slider = ctk.CTkSlider(left, from_=10, to=80, variable=self.thresh_var, command=self._update_thresh_label)
        self.thresh_slider.pack(fill="x", padx=15)
        self.thresh_label = ctk.CTkLabel(left, text="35")
        self.thresh_label.pack()

        # Min Alan
        ctk.CTkLabel(left, text="Min Alan (gürültü filtresi)").pack()
        self.minarea_var = ctk.IntVar(value=50)
        self.minarea_slider = ctk.CTkSlider(left, from_=10, to=300, variable=self.minarea_var, command=self._update_minarea_label)
        self.minarea_slider.pack(fill="x", padx=15)
        self.minarea_label = ctk.CTkLabel(left, text="50")
        self.minarea_label.pack()

        # Dilate
        ctk.CTkLabel(left, text="Kalınlık (dilate)").pack()
        self.dilate_var = ctk.IntVar(value=1)
        self.dilate_slider = ctk.CTkSlider(left, from_=1, to=4, variable=self.dilate_var, number_of_steps=3, command=self._update_dilate_label)
        self.dilate_slider.pack(fill="x", padx=15)
        self.dilate_label = ctk.CTkLabel(left, text="1")
        self.dilate_label.pack()

        # Wiggle ayarları
        ctk.CTkFrame(left, height=2, fg_color="gray30").pack(fill="x", padx=15, pady=12)
        ctk.CTkLabel(left, text="Wiggle Kuvveti").pack()
        self.wiggle_var = ctk.DoubleVar(value=3.2)
        self.wiggle_slider = ctk.CTkSlider(left, from_=1.0, to=6.0, variable=self.wiggle_var, command=self._update_wiggle_label)
        self.wiggle_slider.pack(fill="x", padx=15)
        self.wiggle_label = ctk.CTkLabel(left, text="3.2")
        self.wiggle_label.pack()

        # Önizle butonu
        ctk.CTkButton(left, text="👁 Önizle", command=self._preview, height=38, fg_color="gray40").pack(fill="x", padx=15, pady=(12,5))

        # Çıktı seçenekleri
        ctk.CTkFrame(left, height=2, fg_color="gray30").pack(fill="x", padx=15, pady=5)
        self.save_png = ctk.BooleanVar(value=True)
        self.save_gif = ctk.BooleanVar(value=True)
        self.save_sheet = ctk.BooleanVar(value=True)
        ctk.CTkCheckBox(left, text="Statik PNG", variable=self.save_png).pack(anchor="w", padx=20)
        ctk.CTkCheckBox(left, text="Wiggle GIF", variable=self.save_gif).pack(anchor="w", padx=20)
        ctk.CTkCheckBox(left, text="Spritesheet PNG", variable=self.save_sheet).pack(anchor="w", padx=20)

        # Kaydet butonu
        ctk.CTkButton(left, text="💾 Kaydet", command=self._save, height=42,
                      fg_color="#1f6aa5", hover_color="#144e7a", font=("Arial", 14, "bold")).pack(fill="x", padx=15, pady=10)

        # Status
        self.status_label = ctk.CTkLabel(left, text="", font=("Arial", 11), text_color="#4CAF50", wraplength=240)
        self.status_label.pack(pady=5)

        # Sağ panel - önizleme
        right = ctk.CTkFrame(self)
        right.pack(side="right", fill="both", expand=True, padx=10, pady=10)

        ctk.CTkLabel(right, text="Önizleme", font=("Arial", 14, "bold")).pack(pady=10)
        self.preview_label = ctk.CTkLabel(right, text="Fotoğraf seçip 'Önizle'ye tıkla", text_color="gray")
        self.preview_label.pack(expand=True)

    # ── Slider label güncellemeleri ────────────────────────────────────
    def _update_thresh_label(self, v): self.thresh_label.configure(text=str(int(float(v))))
    def _update_minarea_label(self, v): self.minarea_label.configure(text=str(int(float(v))))
    def _update_dilate_label(self, v): self.dilate_label.configure(text=str(int(float(v))))
    def _update_wiggle_label(self, v): self.wiggle_label.configure(text=f"{float(v):.1f}")

    # ── Dosya seçimi ───────────────────────────────────────────────────
    def _pick_file(self):
        path = filedialog.askopenfilename(filetypes=[("Görüntü", "*.jpg *.jpeg *.png *.webp *.bmp")])
        if path:
            self.img_path = path
            self.file_label.configure(text=os.path.basename(path))
            # Dosya adını otomatik sprite adı olarak öner
            base = os.path.splitext(os.path.basename(path))[0]
            self.name_entry.delete(0, "end")
            self.name_entry.insert(0, base)

    def _pick_outdir(self):
        d = filedialog.askdirectory()
        if d:
            self.out_dir = d
            self.outdir_label.configure(text=d)

    # ── Önizle ────────────────────────────────────────────────────────
    def _preview(self):
        if not self.img_path:
            messagebox.showwarning("Uyarı", "Önce fotoğraf seç!")
            return
        self.status_label.configure(text="İşleniyor...", text_color="orange")
        self.update()
        try:
            self.sprite_pil = extract_sprite(
                self.img_path,
                int(self.thresh_var.get()),
                int(self.minarea_var.get()),
                int(self.dilate_var.get())
            )
            # Beyaz bg üzerinde göster
            prev = Image.new('RGB', self.sprite_pil.size, (248, 245, 240))
            prev.paste(self.sprite_pil, mask=self.sprite_pil.split()[3])

            # Önizleme boyutuna sığdır
            prev.thumbnail((500, 550), Image.LANCZOS)
            self.preview_photo = ImageTk.PhotoImage(prev)
            self.preview_label.configure(image=self.preview_photo, text="")
            self.status_label.configure(text=f"✓ {self.sprite_pil.size[0]}x{self.sprite_pil.size[1]}px", text_color="#4CAF50")
        except Exception as e:
            self.status_label.configure(text=f"Hata: {e}", text_color="red")

    # ── Kaydet ────────────────────────────────────────────────────────
    def _save(self):
        if not self.sprite_pil:
            messagebox.showwarning("Uyarı", "Önce 'Önizle'ye tıkla!")
            return
        name = self.name_entry.get().strip()
        if not name:
            messagebox.showwarning("Uyarı", "Sprite adı gir!")
            return

        self.status_label.configure(text="Kaydediliyor...", text_color="orange")
        self.update()

        def _worker():
            try:
                saved = []
                if self.save_png.get():
                    p = os.path.join(self.out_dir, f"{name}.png")
                    self.sprite_pil.save(p)
                    saved.append("PNG")

                if self.save_gif.get() or self.save_sheet.get():
                    frames, durations = create_wiggle(
                        self.sprite_pil,
                        n_frames=7,
                        strength=float(self.wiggle_var.get()),
                        total_ms=1040
                    )
                    if self.save_gif.get():
                        p = os.path.join(self.out_dir, f"{name}_wiggle.gif")
                        frames[0].save(p, save_all=True, append_images=frames[1:],
                                       duration=durations, loop=0, disposal=2)
                        saved.append("GIF")
                    if self.save_sheet.get():
                        sw, sh = frames[0].size
                        sheet = Image.new('RGBA', (sw*len(frames), sh), (0,0,0,0))
                        for i, f in enumerate(frames): sheet.paste(f, (i*sw, 0))
                        p = os.path.join(self.out_dir, f"{name}_sheet.png")
                        sheet.save(p)
                        saved.append("Sheet")

                self.after(0, lambda: self.status_label.configure(
                    text=f"✓ Kaydedildi: {', '.join(saved)}", text_color="#4CAF50"))
            except Exception as e:
                self.after(0, lambda: self.status_label.configure(text=f"Hata: {e}", text_color="red"))

        threading.Thread(target=_worker, daemon=True).start()


if __name__ == "__main__":
    app = SpriteToolApp()
    app.mainloop()


