# PRD: DeskWidgets (nama kerja)

> **Status:** Draft v0.1
> **Platform:** macOS (Swift native)
> **Nama produk:** "DeskWidgets" hanyalah nama sementara. Ganti sesuai keputusan branding.

---

## 1. Ringkasan

DeskWidgets adalah aplikasi macOS native yang menyediakan **kumpulan widget desktop**: jam, tanggal, timer, monitor sistem, dan seterusnya. Setiap widget tampil langsung di desktop, ukurannya bisa diatur **bebas dari sangat kecil hingga memenuhi satu layar penuh**, dan tampilannya ikut menyesuaikan ukuran.

Aplikasi ini didistribusikan lewat **skrip instalasi `.sh`** sehingga pengguna lain bisa memasangnya dengan satu perintah di terminal, **tanpa memerlukan Apple Developer Program**.

## 2. Latar Belakang & Masalah

- Widget resmi macOS (WidgetKit) berbasis timeline dengan jatah refresh yang diatur sistem. Widget tidak bisa memperbarui tampilan tiap detik, tidak bisa animasi mulus, dan ukurannya hanya terbatas pada beberapa preset (kecil, sedang, besar, ekstra besar).
- Pengguna yang ingin jam besar di desktop (misalnya jam satu layar penuh untuk stream, setup meja, atau display kedua) tidak punya solusi native yang fleksibel.
- Aplikasi sejenis yang ada umumnya berbayar, berbasis Electron (berat), atau tidak mudah dibagikan.

## 3. Tujuan

| # | Tujuan |
|---|---|
| G1 | Menyediakan widget desktop yang **ukurannya bebas** (kecil sampai satu layar). |
| G2 | Satu aplikasi berisi **banyak jenis widget**, dengan arsitektur yang mudah ditambah widget baru. |
| G3 | **Ringan**: pemakaian CPU dan RAM sangat rendah, aman dibiarkan menyala seharian. |
| G4 | **Mudah dipasang orang lain** lewat satu perintah `.sh`, tanpa akun Apple Developer. |
| G5 | Terasa native: Swift/SwiftUI, mendukung dark mode, multi-display, dan Spaces. |

## 4. Non-Goals (v1)

- Bukan widget WidgetKit resmi (tidak muncul di Widget Gallery / Notification Center).
- Tidak ada distribusi lewat Mac App Store.
- Tidak ada marketplace atau plugin pihak ketiga (arsitektur disiapkan, tapi belum dibuka).
- Tidak mendukung Windows dan Linux.
- Tidak ada sinkronisasi cloud antar perangkat.
- Tidak ada widget yang membutuhkan akun login layanan pihak ketiga.

## 5. Target Pengguna

- **Pengguna utama:** pengguna Mac yang ingin desktop yang rapi dan informatif (pekerja remote, pelajar, kreator).
- **Pengguna sekunder:** streamer dan kreator yang membutuhkan jam atau timer besar di layar.
- **Penerima distribusi awal:** teman, komunitas, dan sesama developer yang terbiasa memakai terminal.

## 6. Konsep Produk

### 6.1 Cara kerja widget

Setiap widget adalah **jendela tanpa border dan transparan** yang diletakkan pada level desktop. Jadi widget:

- tampil di atas wallpaper, di bawah jendela aplikasi lain;
- muncul di semua Space;
- tidak ikut muncul di Cmd+Tab maupun Mission Control sebagai jendela biasa;
- bisa dipindah dan diubah ukurannya saat **mode edit** aktif, lalu dikunci agar tidak tergeser tidak sengaja.

### 6.2 Dua mode interaksi

| Mode | Perilaku |
|---|---|
| **Terkunci** (default) | Widget diam di tempatnya. Klik menembus ke desktop (*click-through*), kecuali widget yang memang interaktif (misalnya tombol timer). |
| **Mode edit** | Widget bisa digeser, ditarik untuk mengubah ukuran, dan diklik kanan untuk membuka pengaturannya. |

### 6.3 Ukuran

- Ukuran **kontinu** (bukan preset), dengan batas minimum per widget dan batas maksimum = ukuran layar.
- Tersedia **preset cepat**: Kecil, Sedang, Besar, dan **Layar Penuh**.
- Konten widget dirancang **responsif**: tata letak dan ukuran font menyesuaikan ukuran jendela, bukan sekadar di-scale.
- **Layar Penuh:** widget menutupi seluruh layar yang dipilih, tetap berada di level desktop, sehingga jendela aplikasi lain tetap tampil di atasnya.

## 7. Requirement Fungsional

Prioritas: **P0** = wajib untuk MVP, **P1** = penting, **P2** = nanti.

### 7.1 Engine widget

| ID | Requirement | Prioritas |
|---|---|---|
| F-01 | Membuat, menampilkan, dan menghapus instance widget. | P0 |
| F-02 | Satu jenis widget boleh punya banyak instance dengan konfigurasi berbeda (misalnya dua jam dengan zona waktu berbeda). | P0 |
| F-03 | Mengubah ukuran secara bebas lewat drag di tepi atau sudut (mode edit). | P0 |
| F-04 | Memindah posisi widget lewat drag (mode edit). | P0 |
| F-05 | Preset ukuran cepat, termasuk Layar Penuh. | P0 |
| F-06 | Posisi, ukuran, dan konfigurasi tersimpan lalu dipulihkan saat aplikasi dibuka lagi. | P0 |
| F-07 | Dukungan multi-display: pilih layar tempat widget tampil. | P1 |
| F-08 | Snap ke tepi layar dan grid saat menggeser. | P1 |
| F-09 | Atur level: di atas atau di bawah ikon desktop. | P1 |
| F-10 | Atur opasitas per widget. | P1 |
| F-11 | Ekspor dan impor layout (file JSON). | P2 |

### 7.2 Aplikasi & pengaturan

| ID | Requirement | Prioritas |
|---|---|---|
| F-20 | Jendela pengelola (*Widget Manager*): daftar widget yang tersedia, tambah, hapus, tampil/sembunyikan. | P0 |
| F-21 | Toggle global mode edit dan kunci. | P0 |
| F-22 | Opsi **buka otomatis saat login**. | P1 |
| F-23 | Ikon kontrol kecil di menu bar (bisa disembunyikan) sebagai jalan pintas ke Widget Manager dan mode edit. Ini hanya pintu kontrol, bukan tempat widget. | P1 |
| F-24 | Pengecekan versi baru dan petunjuk memperbarui. | P2 |

## 8. Katalog Widget

| Widget | Deskripsi | Rilis |
|---|---|---|
| **Jam** | Digital dan analog; 12/24 jam; opsi detik; zona waktu dipilih; beberapa gaya tema; skala dari kecil sampai layar penuh. | **MVP** |
| **Tanggal & Kalender** | Hari, tanggal, dan kalender bulanan ringkas. | v1.0 |
| **Timer / Stopwatch / Pomodoro** | Hitung mundur dan hitung maju, notifikasi saat selesai. Interaktif. | v1.0 |
| **Monitor Sistem** | CPU, RAM, baterai, dan penyimpanan dalam bentuk angka atau grafik mini. | v1.0 |
| **Jam Dunia** | Beberapa kota dalam satu widget. | v1.1 |
| **Catatan Cepat** | Teks pendek yang tersimpan lokal. | v1.1 |
| **Cuaca** | Membutuhkan koneksi internet dan sumber data. Perlu keputusan penyedia API dan izin lokasi. | v1.2 (dievaluasi) |

Widget baru harus bisa ditambahkan **tanpa mengubah engine** (lihat bagian 10.2).

## 9. Requirement Non-Fungsional

### 9.1 Performa

| Metrik | Target |
|---|---|
| CPU saat idle dengan widget jam (tanpa detik) | < 1% |
| CPU dengan jam berdetik (digital) | < 2% |
| RAM dasar aplikasi tanpa widget | < 50 MB |
| Waktu startup sampai widget tampil | < 1 detik |

> Target di atas adalah sasaran desain. Angka final harus **diukur** di mesin nyata (Apple Silicon dan Intel) saat prototipe.

Teknik yang diwajibkan:
- Pembaruan berbasis jadwal sesuai kebutuhan (jam tanpa detik hanya memperbarui tiap menit).
- **Berhenti merender** saat layar mati, terkunci, atau widget tidak terlihat (memantau `occlusionState` dan notifikasi tidur layar).
- Tidak ada polling terus-menerus; widget monitor memakai interval yang bisa diatur.
- Hindari efek berat seperti blur besar pada area luas.

### 9.2 Kompatibilitas

- **macOS minimum:** 13 (Ventura), sebagai usulan. Keputusan akhir ada di bagian 15.
- Binary **universal** (Apple Silicon + Intel).
- Mendukung dark mode dan light mode.

### 9.3 Privasi & keamanan

- Tidak ada telemetri dan tidak ada koneksi jaringan di v1, kecuali widget yang memang membutuhkannya dan dengan izin yang jelas.
- Semua data (layout, konfigurasi) tersimpan lokal di `~/Library/Application Support/<NamaApp>/`.
- Skrip instalasi tidak meminta `sudo`.

### 9.4 Aksesibilitas

- Dukungan VoiceOver untuk kontrol di Widget Manager.
- Kontras warna yang memadai pada tema bawaan.

## 10. Arsitektur Teknis

### 10.1 Stack

| Lapisan | Pilihan |
|---|---|
| Bahasa | Swift 5.9+ |
| UI konten widget | SwiftUI |
| Manajemen jendela | AppKit (`NSWindow` / `NSPanel`) |
| Penyimpanan | JSON (`Codable`) di Application Support |
| Build | Swift Package Manager + skrip pembungkus `.app` |
| CI/CD | GitHub Actions (runner macOS), menghasilkan rilis universal |

### 10.2 Struktur modul (usulan)

```
DeskWidgets/
├── Package.swift
├── Sources/
│   ├── App/                  # entry point, AppDelegate, pengaturan
│   ├── Core/
│   │   ├── WidgetHost.swift       # mengelola jendela per instance
│   │   ├── WidgetRegistry.swift   # daftar jenis widget yang tersedia
│   │   ├── LayoutStore.swift      # simpan/pulihkan posisi, ukuran, konfigurasi
│   │   └── DisplayManager.swift   # multi-display, perubahan layar
│   ├── Widgets/
│   │   ├── Clock/
│   │   ├── DateCalendar/
│   │   ├── Timer/
│   │   └── SystemMonitor/
│   └── UI/                   # Widget Manager, mode edit, kontrol resize
├── scripts/
│   ├── build-app.sh          # bungkus binary menjadi .app, ad-hoc sign
│   └── release.sh
├── install.sh                # skrip instalasi untuk pengguna
└── uninstall.sh
```

### 10.3 Kontrak widget

Setiap jenis widget mendaftarkan diri lewat definisi seragam, sehingga menambah widget baru tidak menyentuh engine:

```swift
protocol WidgetDefinition {
    associatedtype Config: Codable & Hashable
    associatedtype Content: View
    associatedtype SettingsView: View

    static var id: String { get }
    static var displayName: String { get }
    static var minimumSize: CGSize { get }
    static var defaultConfig: Config { get }

    @ViewBuilder static func makeContent(config: Config, size: CGSize) -> Content
    @ViewBuilder static func makeSettings(config: Binding<Config>) -> SettingsView
}
```

Konten menerima `size` sehingga tata letak bisa beradaptasi, bukan sekadar membesar.

### 10.4 Pengaturan jendela

- Gaya tanpa border, latar transparan, tanpa bayangan jendela.
- Level jendela di atas wallpaper dan opsional di atas atau di bawah ikon desktop.
- `collectionBehavior` mencakup tampil di semua Space, stasioner, dan tidak masuk siklus jendela.
- Mode terkunci: `ignoresMouseEvents = true`, kecuali area interaktif.
- Mode Layar Penuh: frame jendela = frame layar yang dipilih.

> Perilaku detail (khususnya interaksi dengan Stage Manager dan fitur "klik wallpaper untuk menampilkan desktop" pada macOS Sonoma ke atas) harus **diuji lebih dulu pada prototipe** sebelum arsitektur dikunci.

### 10.5 Persistensi

```json
{
  "version": 1,
  "widgets": [
    {
      "id": "uuid",
      "type": "clock",
      "display": "main",
      "frame": { "x": 120, "y": 80, "w": 320, "h": 320 },
      "opacity": 1.0,
      "config": { "style": "analog", "timezone": "Asia/Jakarta", "showSeconds": true }
    }
  ]
}
```

File memiliki field `version` untuk migrasi di masa depan.

## 11. Distribusi & Instalasi

### 11.1 Prinsip

- **Tanpa Apple Developer Program** pada v1.
- Pengguna cukup menjalankan satu perintah di terminal:

```bash
curl -fsSL https://<host-anda>/install.sh | bash
```

- Aplikasi dirilis sebagai **binary jadi (universal)** lewat GitHub Releases, bukan di-build di mesin pengguna, supaya pengguna tidak perlu Xcode.

### 11.2 Alur `install.sh`

1. Cek versi macOS dan arsitektur (arm64 atau x86_64). Berhenti dengan pesan jelas bila tidak didukung.
2. Ambil info rilis terbaru (atau versi tertentu lewat `--version`).
3. Unduh arsip `.zip` dan file `.sha256` lewat HTTPS.
4. **Verifikasi checksum SHA-256.** Gagal berarti berhenti.
5. Hentikan instance yang sedang berjalan (bila ada).
6. Pasang ke `~/Applications/` (tanpa `sudo`).
7. Pastikan tanda tangan ad-hoc valid (`codesign --verify`; tanda tangani ulang bila perlu). Binary tanpa tanda tangan apa pun tidak akan jalan di Apple Silicon.
8. Hapus atribut karantina sebagai pengaman tambahan (`xattr -dr com.apple.quarantine`). Berkas yang diunduh lewat `curl` umumnya tidak memilikinya.
9. Jalankan aplikasi, kecuali ada flag `--no-launch`.

### 11.3 Sifat skrip

- **Idempoten:** dijalankan ulang berarti memperbarui, bukan merusak.
- Pendek, mudah dibaca, dan tidak melakukan hal di luar yang dijelaskan.
- Menampilkan langkah yang sedang berjalan dan pesan error yang bisa ditindaklanjuti.
- Flag: `--version <x>`, `--no-launch`, `--uninstall`.

### 11.4 `uninstall.sh`

- Menghentikan aplikasi, menghapus `.app`, menghapus item login (bila ada), dan **menanyakan** apakah data pengguna di Application Support ikut dihapus.

### 11.5 Build & rilis

- `swift build -c release --arch arm64 --arch x86_64` menghasilkan binary universal.
- Skrip membungkus binary menjadi `.app` (Info.plist, ikon, resource), lalu **ad-hoc sign** (`codesign --force --deep -s -`).
- Artefak rilis: `DeskWidgets-vX.Y.Z-macos-universal.zip` + `.sha256`.

### 11.6 Konsekuensi tanpa notarization

- Pengguna yang mengunduh `.dmg` atau `.zip` lewat browser akan melihat peringatan Gatekeeper. Jalur resmi yang didukung v1 adalah **skrip `.sh`**.
- Pengguna harus mempercayai skrip dan sumber rilis. Karena itu kode dan skrip dibuat transparan (open source atau minimal dapat dibaca).
- **Jalur lanjutan (opsional):** bila nanti ingin dibuka untuk pengguna awam, daftar Apple Developer Program, gunakan Developer ID + notarization, lalu sediakan `.dmg`.

## 12. UX Singkat

1. **Pertama kali dibuka:** Widget Manager tampil dengan satu widget Jam sudah muncul di desktop dan mode edit aktif, agar pengguna langsung paham cara menggeser dan mengubah ukuran.
2. **Menambah widget:** pilih jenis di Widget Manager, lalu widget muncul di tengah layar dalam mode edit.
3. **Mengubah ukuran:** tarik sudut atau tepi; pegangan tampil hanya saat hover di mode edit. Preset ukuran ada di menu klik kanan.
4. **Selesai mengatur:** matikan mode edit (tombol di Widget Manager atau menu bar) dan widget terkunci.
5. **Layar Penuh:** satu klik di preset; kembali ke ukuran sebelumnya dengan satu klik.

## 13. Metrik Keberhasilan

| Metrik | Target awal |
|---|---|
| Keberhasilan instalasi via `.sh` pada macOS yang didukung | ≥ 95% |
| CPU idle widget jam | < 1% (terukur) |
| Crash-free sessions | ≥ 99% |
| Widget bisa menampilkan ukuran dari kecil sampai layar penuh tanpa tata letak rusak | 100% pada widget MVP |
| Waktu dari menjalankan perintah install sampai widget tampil | < 1 menit |

## 14. Milestone

| Fase | Isi | Hasil |
|---|---|---|
| **M0: Prototipe** | Satu jendela desktop transparan dengan jam; uji level jendela, Spaces, click-through, Layar Penuh, dan ukur CPU/RAM. | Keputusan teknis dikunci |
| **M1: Engine + Jam (MVP)** | WidgetHost, LayoutStore, mode edit, resize bebas, preset, widget Jam. | Bisa dipakai sendiri |
| **M2: Distribusi** | build universal, ad-hoc sign, `install.sh`, `uninstall.sh`, rilis GitHub. | Bisa dibagikan ke orang lain |
| **M3: Katalog v1.0** | Tanggal/Kalender, Timer, Monitor Sistem; multi-display; login otomatis. | Rilis v1.0 |
| **M4: v1.1+** | Jam Dunia, Catatan, evaluasi Cuaca, ekspor/impor layout. | Iterasi |

## 15. Risiko & Pertanyaan Terbuka

### Risiko

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Perilaku jendela level desktop berubah antar versi macOS (Stage Manager, "klik wallpaper untuk tampilkan desktop"). | Widget bisa tersembunyi atau berperilaku aneh. | Uji di prototipe M0 pada beberapa versi macOS; sediakan opsi level. |
| Distribusi tanpa notarization memicu peringatan atau kecurigaan pengguna. | Instalasi gagal atau pengguna ragu. | Jalur resmi lewat `.sh`, checksum, kode terbuka; jalur Developer ID sebagai rencana lanjutan. |
| Pembaruan macOS memperketat aturan Gatekeeper untuk aplikasi tanpa notarization. | Instalasi via `.sh` bisa terblokir di masa depan. | Pantau perubahan; siapkan rencana notarization. |
| Konsumsi CPU membengkak karena animasi atau render berlebihan. | Baterai boros. | Anggaran performa, pause saat tidak terlihat, ukur sejak M0. |
| Cuaca atau widget berjaringan menambah kompleksitas izin dan privasi. | Menunda rilis. | Tunda ke v1.2, putuskan setelah katalog inti stabil. |

### Pertanyaan terbuka

1. **Nama produk** final dan identitas visual.
2. **macOS minimum:** 13 atau 14? (13 menjangkau lebih banyak pengguna; 14 menyederhanakan beberapa API.)
3. Apakah ikon kontrol di **menu bar** diaktifkan secara default, atau hanya lewat Dock/jendela utama?
4. **Open source atau tertutup?** Ini memengaruhi tingkat kepercayaan pada skrip instalasi.
5. Tempat hosting `install.sh` dan rilis (GitHub Releases, domain pribadi, atau keduanya).
6. Pembaruan otomatis di dalam aplikasi, atau cukup menjalankan ulang `install.sh`?
7. Mekanisme buka otomatis saat login: `SMAppService` atau LaunchAgent yang ditulis skrip. Perlu diverifikasi perilakunya untuk aplikasi dengan ad-hoc signature.
