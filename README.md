# DeskWidgets

Widget desktop native untuk macOS dengan **ukuran bebas**, dari sekecil jam sampai satu layar penuh. Ditulis dengan Swift, SwiftUI, dan AppKit, tanpa Electron, tanpa akun, dan tanpa Apple Developer Program.

Widget berupa jendela transparan di level desktop (di atas wallpaper, di bawah jendela aplikasi lain). Berbeda dengan widget WidgetKit bawaan, widget di sini bisa diperbarui tiap detik dan ukurannya kontinu, bukan preset.

> Spesifikasi dan keputusan desain awal ada di [`PRD.md`](PRD.md).

## Daftar isi

- [Fitur](#fitur)
- [Persyaratan](#persyaratan)
- [Clone dan jalankan](#clone-dan-jalankan)
- [Instalasi untuk pengguna lain](#instalasi-untuk-pengguna-lain)
- [Cara pakai](#cara-pakai)
- [Widget](#widget)
- [Tampilan: tema, warna, font, Liquid Glass](#tampilan-tema-warna-font-liquid-glass)
- [Data dan privasi](#data-dan-privasi)
- [Batasan yang diketahui](#batasan-yang-diketahui)
- [Pengembangan](#pengembangan)
- [Rilis dan uninstall](#rilis-dan-uninstall)

## Fitur

- Enam widget: Jam, Tanggal & Kalender, Timer, Monitor Sistem, Penggunaan Aplikasi, dan Penggunaan Token AI.
- Ukuran bebas dengan tarik tepi atau sudut, preset Kecil / Sedang / Besar, dan **Layar Penuh**. Isi widget menyesuaikan tata letak, bukan sekadar diperbesar.
- Mode edit untuk menggeser dan mengubah ukuran, lalu dikunci agar klik menembus ke desktop.
- Banyak instance per jenis widget dengan konfigurasi berbeda (misalnya dua jam dengan zona waktu berbeda).
- Tema, warna, font, dan tema **Liquid Glass** pada huruf.
- Tooltip statistik saat hover pada widget Penggunaan Aplikasi dan Token AI.
- Berjalan di latar: menutup dari Dock tidak mematikan widget. Opsi buka otomatis saat login.
- Multi-display, snap ke tepi layar, dan layout tersimpan otomatis.
- Semua data lokal. Tidak ada telemetri dan tidak ada koneksi jaringan.

## Persyaratan

| Kebutuhan | Keterangan |
|---|---|
| macOS | 13 (Ventura) atau lebih baru |
| Liquid Glass asli | macOS 26 atau lebih baru. Di versi lebih lama tema Glass tampil sebagai teks biasa |
| Toolchain | Swift 5.9+ (Xcode atau Command Line Tools: `xcode-select --install`) |
| Arsitektur | Apple Silicon dan Intel (binary universal saat dibuild tanpa `ARCHS`) |

## Clone dan jalankan

```bash
git clone https://github.com/KeiRey/mac-widget.git
cd mac-widget

# Build, bungkus menjadi .app, ad-hoc sign, lalu buka
scripts/build-app.sh && open dist/DeskWidgets.app
```

Build universal (arm64 + x86_64) butuh waktu lebih lama. Untuk development di Apple Silicon saja:

```bash
ARCHS=arm64 scripts/build-app.sh && open dist/DeskWidgets.app
```

Opsi lain:

- **Pasang ke `~/Applications`**: salin hasil build, `cp -R dist/DeskWidgets.app ~/Applications/`.
- **`swift run`**: berjalan tanpa bundle `.app`, jadi notifikasi Timer dan "buka otomatis saat login" tidak berfungsi. Cukup untuk percobaan cepat.
- **Versi di file `.zip`**: `scripts/build-app.sh 1.0.0` juga menghasilkan `dist/DeskWidgets-v1.0.0-macos-universal.zip` beserta `.sha256`.

Aplikasi ini ditandatangani **ad-hoc** (tanpa notarization). Jika macOS menolak membuka berkas hasil unduhan lewat browser, jalankan `xattr -dr com.apple.quarantine dist/DeskWidgets.app`. Build lokal biasanya tidak terkena karantina.

## Instalasi untuk pengguna lain

Skrip `install.sh` mengunduh rilis dari GitHub, memverifikasi checksum SHA-256, memasang ke `~/Applications` (tanpa `sudo`), lalu membuka aplikasi:

```bash
curl -fsSL https://raw.githubusercontent.com/KeiRey/mac-widget/main/install.sh \
  | DESKWIDGETS_REPO=KeiRey/mac-widget bash
```

Opsi:

```bash
... | DESKWIDGETS_REPO=KeiRey/mac-widget bash -s -- --version 1.0.0   # versi tertentu
... | DESKWIDGETS_REPO=KeiRey/mac-widget bash -s -- --no-launch       # jangan buka setelah pasang
... | DESKWIDGETS_REPO=KeiRey/mac-widget bash -s -- --uninstall       # hapus aplikasi
```

Skrip ini idempoten (dijalankan ulang berarti memperbarui) dan hanya berfungsi setelah ada rilis di GitHub: push tag `vX.Y.Z` dan workflow `.github/workflows/release.yml` membuat zip serta checksum-nya. Tanpa `DESKWIDGETS_REPO`, skrip berhenti dengan pesan yang jelas.

## Cara pakai

1. **Pertama kali dibuka**: satu widget Jam muncul di tengah layar dalam mode edit, dan Widget Manager terbuka.
2. **Mengatur widget** (mode edit): seret badan widget untuk memindah, tarik tepi atau sudut untuk mengubah ukuran. Klik kanan untuk preset ukuran, pengaturan, atau hapus. Widget menempel ke tepi dan tengah layar saat digeser.
3. **Selesai mengatur**: klik tombol **Selesai mengedit** di atas widget, atau matikan toggle Mode edit di Widget Manager atau menu bar. Widget terkunci dan klik menembus ke desktop.
4. **Layar Penuh**: pilih dari menu klik kanan atau Widget Manager. Pilih lagi untuk kembali ke ukuran sebelumnya.
5. **Menambah widget**: Widget Manager, tombol **Tambah widget**. Widget baru muncul di tengah layar dalam mode edit.

### Widget Manager

Daftar widget (tampil/sembunyi), ukuran dan posisi, pilihan layar, opasitas, level di atas ikon desktop, pengaturan khusus tiap widget, dan hapus. Footer berisi:

- **Buka otomatis saat login**
- **Ikon menu bar**
- **Lacak pemakaian app** (untuk widget Penggunaan Aplikasi)

### Berjalan di latar

**Quit** dari Dock atau ⌘Q tidak mematikan aplikasi. Ikon Dock dan jendela manager disembunyikan, sementara widget, ikon menu bar, dan pelacak pemakaian tetap berjalan. Buka lagi lewat ikon menu bar atau Launchpad. Untuk keluar sepenuhnya: ikon menu bar → **Keluar sepenuhnya**, atau ⌥⌘Q. Shutdown, restart, dan logout tetap menutup aplikasi seperti biasa. Saat berjalan di latar, ikon menu bar selalu ditampilkan walau opsinya dimatikan, agar aplikasi tetap bisa dibuka.

## Widget

### Jam

Digital atau analog, format 12/24 jam, detik, tanggal, dan zona waktu pilihan. Pembaruan mengikuti kebutuhan: tanpa detik hanya sekali per menit.

### Tanggal & Kalender

Hari, tanggal besar, dan kalender bulanan. Tata letak otomatis (kiri-kanan atau atas-bawah) menurut ukuran. Awal minggu Senin atau Minggu.

### Timer

Hitung mundur, stopwatch, dan Pomodoro (fokus/istirahat berpindah otomatis) dengan notifikasi saat selesai. Lihat [batasan](#batasan-yang-diketahui) soal klik tombol.

### Monitor Sistem

CPU, RAM, baterai, dan penyimpanan sebagai gauge melingkar. Interval pembaruan 1 sampai 30 detik. Sampling berhenti saat widget tidak terlihat.

### Penggunaan Aplikasi

Heatmap ala kontribusi GitHub: makin lama sebuah app dipakai, makin terang selnya.

- **Metrik**: *Aktif di depan* (app yang sedang dipakai; berhenti dihitung setelah 3 menit tanpa input, saat layar tidur, atau sesi terkunci) atau *Aplikasi berjalan* (terbuka walau di latar).
- **Rentang**: hari ini per jam, atau 4 sampai 52 minggu. "Isi lebar widget" menyesuaikan jumlah minggu dengan lebar.
- **App**: pilih dari app yang sedang terbuka, yang pernah terdeteksi, atau dari Finder. Tiap app punya nama, warna, target harian (kecerahan penuh), serta rentang dan metrik sendiri.
- **Tampilan**: bentuk sel (kotak, membulat, lingkaran), jarak sel, kecerahan bertingkat atau halus, ikon, nama, total hari ini, label bulan, label hari, legend Kurang → Banyak.
- **Hover**: waktu aktif, waktu berjalan, jam tersibuk, dan persen dari target.

Pelacak hanya memakai `NSWorkspace`, tanpa izin Accessibility atau Screen Recording. Ia mencatat semua app biasa selama DeskWidgets berjalan, bukan hanya yang ada di widget.

### Penggunaan Token AI

Total token harian dan biaya untuk agent coding, dalam dua bentuk: **heatmap** atau **line chart**.

| Agent | Sumber data | Akurasi |
|---|---|---|
| Claude Code | `~/.claude/projects/**/*.jsonl` | Akurat (dihitung per pesan, tanpa hitung ganda) |
| Codex | `~/.codex/sessions/**/*.jsonl` | Akurat |
| OpenCode | `~/.local/share/opencode/opencode.db` | Akurat |
| Antigravity CLI | `~/.gemini/antigravity-cli/conversations/*.db` | **Perkiraan**: format internal tidak terdokumentasi |

- **Hitung token**: semua token (termasuk cache), input + output, output saja, atau **biaya (USD)**.
- **Heatmap**: opsi tampilan sama dengan Penggunaan Aplikasi. Target token harian bisa diatur per agent.
- **Line chart**: rentang hari ini per jam atau 7 sampai 90 hari, kurva halus, area berwarna, titik data, grid, label sumbu, dan skala terpisah per agent (0–100%) agar agent kecil tetap terlihat di samping yang besar.
- **Hover**: input, output, cache read/write, total token, biaya, dan rincian per model. Pada line chart muncul garis panduan dan tooltip per hari, dengan total gabungan bila lebih dari satu agent aktif.
- **Biaya**: dihitung dari token per model dengan tabel harga yang bisa diedit (Widget Manager → pengaturan widget → *Harga per 1 juta token*). Angkanya adalah **perkiraan setara harga API**, bukan tagihan langganan atau router. Model tanpa aturan harga (misalnya alias router seperti `Combo1`) dihitung $0 dan ditandai "harga belum diatur".
  - Harga bawaan Claude mengikuti tabel harga resmi Anthropic. Harga GPT-5 dan Gemini Flash adalah perkiraan dari daftar harga publik; periksa dan sesuaikan.
- **Pemindaian**: pertama kali sekitar 4 detik untuk ±300 MB log, lalu inkremental. Pemindaian hanya berjalan saat widget terlihat.

## Tampilan: tema, warna, font, Liquid Glass

Berlaku untuk semua widget:

- **Tema**: Minimal (tanpa latar), Liquid Glass, Gelap, Terang, Neon, atau Ikuti sistem.
- **Warna** teks, aksen, dan latar (dengan opasitas latar), masing-masing bisa direset ke tema.
- **Font**: font sistem (gaya Bulat / Standar / Serif / Monospace) atau font apa pun yang terpasang.
- **Opasitas** per widget.

**Liquid Glass** memakai `glassEffect` asli macOS 26 pada kontur huruf, sehingga huruf membiaskan wallpaper dan jendela di belakangnya. Slider **Transparansi** mengatur kaca bertint (kiri) hingga bening (kanan), dan **Ketebalan lensa** menebalkan kontur agar area pembiasan lebih besar. Sistem tidak menyediakan parameter kekuatan pembiasan.

## Data dan privasi

Semua data tersimpan di `~/Library/Application Support/DeskWidgets/`:

| Berkas | Isi |
|---|---|
| `layout.json` | Posisi, ukuran, dan konfigurasi widget |
| `usage.json` | Riwayat waktu pemakaian app, per jam |
| `tokens-v2.json`, `tokens-seen-v2.bin` | Cache hasil pemindaian token agent (jumlah token per jam per model dan posisi baca) |
| `pricing.json` | Tabel harga yang sudah diedit |

- Tidak ada telemetri dan tidak ada koneksi jaringan.
- Pemindai token membaca log lokal agent. Yang diambil hanya angka token, nama model, dan waktu; **isi percakapan tidak diurai dan tidak disimpan**.
- Untuk menjalankan instance terpisah (misalnya saat menguji) tanpa menyentuh data asli, set `DESKWIDGETS_DATA_DIR=/path/folder` sebelum menjalankan binary. Memulai dari awal berarti menghapus folder di atas saat aplikasi tidak berjalan.

## Batasan yang diketahui

- **Tombol Timer tidak bisa diklik saat widget terkunci.** Jendela Finder di level desktop mengambil klik. Timer tetap berfungsi, tetapi tombolnya baru bisa dipakai lewat mode edit atau setelah penumpukan jendela diubah.
- **Hover hanya berfungsi bila widget tidak tertutup jendela lain.** Widget yang punya tooltip berada di atas ikon desktop dan menyerap klik pada areanya.
- Pemantauan hover membaca posisi kursor secara berkala (jarang saat kursor di luar widget, lebih rapat saat di atasnya), karena jendela level desktop tidak menerima event hover.
- Waktu pemakaian app hanya tercatat selama DeskWidgets berjalan. Aktifkan **Buka otomatis saat login** agar tidak ada hari yang bolong. Saat sebuah app ditutup, waktu terakhirnya bisa meleset sampai 30 detik.
- Angka Antigravity CLI adalah perkiraan, dan biaya selalu perkiraan setara harga API.
- Memori dengan widget token AI aktif sekitar 100–150 MB (lebih tinggi sebentar saat pemindaian pertama), di atas target awal di PRD. CPU saat idle rendah (±0,1–0,3% pada pengukuran di satu mesin).
- Perilaku jendela level desktop dengan Stage Manager dan "klik wallpaper untuk menampilkan desktop" belum diuji menyeluruh di semua versi macOS.

## Pengembangan

```
Sources/
├── App/          # entry point, AppDelegate, pengaturan aplikasi
├── Core/         # WidgetHost, WidgetPanel, LayoutStore, DisplayManager,
│                 # UsageStore, TokenStore, Pricing, Hover, HeatmapChart, LineChart, Theme
├── UI/           # Widget Manager
└── Widgets/      # Clock, DateCalendar, Timer, SystemMonitor, AppUsage, AITokens
scripts/          # build-app.sh, release.sh
install.sh        # pemasang untuk pengguna lain
uninstall.sh
```

Build dan jalankan cepat tanpa membungkus `.app`:

```bash
swift build          # debug
swift run
```

### Menambah widget baru

Engine tidak perlu diubah. Buat tipe yang memenuhi `WidgetDefinition` lalu daftarkan di `Sources/Core/WidgetRegistry.swift`:

```swift
enum HelloWidget: WidgetDefinition {
    struct Config: Codable, Hashable { var text = "Halo" }

    static let id = "hello"
    static let displayName = "Halo"
    static let symbol = "hand.wave"
    static let minimumSize = CGSize(width: 80, height: 40)
    static let defaultConfig = Config()
    // opsional: defaultSize, isInteractive, isHoverable

    static func makeContent(config: Config, size: CGSize) -> some View {
        Text(config.text).font(.system(size: size.height * 0.5))
    }

    static func makeSettings(config: Binding<Config>) -> some View {
        TextField("Teks", text: config.text)
    }
}
```

```swift
// WidgetRegistry.swift
static let all: [AnyWidgetDefinition] = [
    // ...
    AnyWidgetDefinition(HelloWidget.self),
]
```

`makeContent` menerima `size` sehingga tata letak bisa beradaptasi. Pakai `TickView` untuk konten yang berubah menurut waktu (berhenti otomatis saat widget tidak terlihat) dan `LText` bila ingin mendukung tema Liquid Glass.

## Rilis dan uninstall

```bash
scripts/release.sh 1.0.0              # build universal + zip + sha256 di dist/
scripts/release.sh 1.0.0 --publish    # juga membuat GitHub Release (butuh gh CLI)
```

Push tag `v*` juga memicu workflow GitHub Actions yang membangun dan mengunggah rilis.

Menghapus aplikasi:

```bash
./uninstall.sh
# atau tanpa clone:
curl -fsSL https://raw.githubusercontent.com/KeiRey/mac-widget/main/install.sh \
  | DESKWIDGETS_REPO=KeiRey/mac-widget bash -s -- --uninstall
```

Skrip menghentikan aplikasi, mencabut item login, menghapus `.app`, dan menanyakan apakah data di Application Support ikut dihapus.
