# omarchy-dragon-sp11

[English](README.md) | **Türkçe**

[Omarchy](https://omarchy.org) 4.5'i **Microsoft Surface Pro 11'in LCD / Snapdragon X Plus
(X1P64100)** modeline kurmak için resmi Omarchy aarch64 ISO'sunun üzerine ince bir katman.

Resmi, imzalı ISO'ya yalnızca iki şey eklenir:

1. Canlı (live) UKI, LCD modelin device tree'siyle açılır.
2. Kurulumdan sonra bir kez çalıştırılan `sp11-lcd/` düzeltmesi eklenir. Bu düzeltme,
   kurulan sistemin de doğru tree, initramfs ve firmware ile açılmasını sağlar ve Omarchy'nin
   Surface Pro 11 paketlerini (ses, dokunmatik ve kalem, ışık sensörü, Bluetooth) USB'den kurar.

Çekirdek, paketler ve kurulum programı Omarchy'nin kendisidir. Hiçbir şey yeniden
derlenmez ve yabancı paket eklenmez: Surface Pro 11 paketleri, Omarchy'nin edge deposundaki
imzalı paketlerdir. Yalnızca bu beş paket edge'i izler (`omarchy-update` içindeki bir kancayla),
geri kalan her şey stable'da kalır. Değerlendirilen seçenekler için
[docs/full-hardware-support.md](docs/full-hardware-support.md) (İngilizce).

> **Durum:** ISO derleniyor ve otomatik kontrollerden geçiyor. `sp11-lcd` düzeltmesi de resmi ISO'nun
> hedef kök imajında bütün kontrolleri geçiyor (`test/`). Gerçek cihazda kurulum henüz yapılmadı;
> sonuçlar bu dosyaya eklenecek.

## Neden gerekli?

Omarchy 4.5.0 Snapdragon'u resmi olarak destekliyor. Çekirdeği (`linux-omarchy` 7.3)
Surface Pro 11 için çok sayıda yama taşıyor ve LCD modelin tree'si
(`x1p64100-microsoft-denali.dtb`) zaten ISO'nun içinde. Yine de bu modelde beş sorun var:

| Sorun | Kanıt | Bu repo ne yapıyor |
|---|---|---|
| systemd-stub her Surface Pro 11'e **OLED** tree'sini yüklüyor. OLED, LCD ve X Plus modellerinin SMBIOS kimlikleri aynı ve systemd'nin `hwids` kaydı yalnızca `microsoft,denali-oled`'i tanıyor. Eşleşen bir `.dtbauto`, `.dtb`'nin önüne geçiyor (systemd `src/boot/stub.c`). | `tools/sp11-chid.ps1`: bu cihazın CHID'leri OLED kaydıyla 3, 4, 5, 6, 7, 8, 9 ve 10 numarada eşleşiyor. stub, CHID 3 ile OLED'i seçiyor. | Canlı UKI'ye ve kurulu UKI'ye LCD tree'si tek, koşulsuz `.dtb` olarak konuyor. Bir pre.d kancası bunu her yeniden derlemede koruyor. |
| 4.5.0'da Surface Pro 11'e özel kurulum betiği yok. Klavye (`surface_aggregator`, `surface_hid`), ekran (`msm`, `panel-edp`, eDP PHY) ve pmic_glink sürücülerinin hepsi modül. Bu yüzden disk şifresi ekranında klavye ya da görüntü olmayabilir. | ISO'daki `modules.order` | Omarchy'nin quattro dalındaki Surface Pro 11 modül listesi, LCD paneline uyarlanarak initramfs'e ekleniyor. |
| DSP/GPU firmware'i ya stable depoda yok ya da yalnızca Windows bölümünden çıkarılabiliyor. BitLocker açıkken bölüm okunamıyor. | stable aarch64 deposunda `microsoft-surface-pro-11-*` paketleri yok | Bu cihazın Windows sürücü deposundaki imzalı dosyalar ISO'ya konuyor ve Omarchy'nin `qcom-firmware-extract -d` aracıyla kuruluyor. |
| Wi-Fi yok. Surface'in WCN7850 kartı genel kimlikler bildiriyor (alt sistem `17cb:1107`, board-id 255) ve bunlar `board-2.bin` içindeki hiçbir kayıtla eşleşmiyor. | Omarchy'nin `microsoft-surface-pro-11-support` PKGBUILD'i bunu Surface Pro 11 için belirtiyor. Surface Laptop 7 projesi de aynı kartta aynı kimlikle karşılaşmış. | Omarchy'nin paketinin kullandığı kaydın aynısı, aynı boyut ve SHA256 ile Qualcomm referans kaydı `board.bin` olarak kuruluyor. ath12k bu dosyayı yalnızca `board-2.bin` içinde birebir eşleşme yoksa okuyor. |
| `ENABLE_UKI`, initramfs ve firmware hataları sessizce geçebilir. | Surface Laptop 7 projesinin deneyimi | `apply.sh`, açılacak UKI'yi baytlarına kadar okuyup doğruluyor. Doğrulama geçmezse "reboot güvenli" demiyor. |

## Bu cihazda doğrulananlar

| | |
|---|---|
| Model | Surface Pro 11th Edition, SKU `Surface_Pro_11th_Edition_2076`, UEFI 175.449.235 |
| SoC | Snapdragon X Plus 10 çekirdek **X1P64100** |
| Dahili panel | **LGD077B** (LG LP129WT3 LCD), dahili eDP (`0x80000000`). SAM7395 harici bir monitör. |
| Wi-Fi | Qualcomm WCN7850 (FastConnect 7800), `17cb:1107`, alt sistem `17cb:1107` |
| Firmware | `qcadsp8380.mbn`, `adsp_dtbs.elf`, `qccdsp8380.mbn`, `cdsp_dtbs.elf`, `qcdxkmsuc8380.mbn` ve `battmgr.jsn` dosyalarının SHA256 değerleri Omarchy'nin `microsoft-surface-pro-11-firmware` paketindekilerle (Microsoft MSI 26.094.41119.0) **birebir aynı** |
| Disk | SK hynix UFS 256 GB, GPT, BitLocker **açık** |
| ISO | `omarchy-4.5.0-aarch64.iso`: SHA256 ve GPG imzası doğrulandı (Omarchy anahtarı `40DF B630 FF42 BCFF B047 046C F013 4EE6 80CA C571`) |

## Kurulum

### 0. Windows'ta hazırlık
- Windows Update'ten bütün güncellemeleri ve Surface firmware güncellemelerini kurun. Surface UEFI
  yalnızca Windows üzerinden güncellenir.
- **BitLocker kurtarma anahtarını** kaydedin (<https://aka.ms/myrecoverykey>). Secure Boot
  kapatıldığında Windows bu anahtarı isteyecektir.
- **Windows'u tutacaksanız (önerilen):**
  1. *Ayarlar → Gizlilik ve güvenlik → Cihaz şifreleme* menüsünden BitLocker'ı kapatın.
     Şifre çözme saatler sürebilir. Omarchy'nin "free space" kurulumu BitLocker açıkken çalışmaz.
  2. *Disk Yönetimi*'nde C:'yi küçültün. 80–120 GB önerilir; şu an 157 GB boş.
- En az 16 GB'lık bir **USB-C bellek** hazırlayın. ISO 6,1 GB.

### 0.5 Keşif açılışı (önerilir, geri dönüşü zor adımlardan önce)
BitLocker'ı çözmeden veya C:'yi küçültmeden önce USB'yi bir kez yalnızca canlı masaüstüne kadar açın:
- Önce yönetici PowerShell'de `Suspend-BitLocker -MountPoint 'C:' -RebootCount 0` çalıştırın. Böylece
  Secure Boot kapatıldıktan sonra Windows kurtarma anahtarı istemez. Windows'a döndüğünüzde
  `Resume-BitLocker -MountPoint 'C:'` çalıştırın.
- Aşağıdaki 1–4. adımları kurulum yapmadan, canlı masaüstüne kadar izleyin. Görüntüyü, klavyeyi ve
  touchpad'i kontrol edin, `tr -d '\0' </proc/device-tree/model` çalıştırın; çıktıda "(LCD)" yazmalı.
- Wi-Fi, ses ve pil burada değerlendirilemez: canlı sistemde Wi-Fi firmware'i yok ve DSP kapalı tutuluyor.

### 1. ISO'yu oluşturun (bu Surface'te, Windows'ta)
Docker Desktop açıkken:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-iso.ps1
```

Çıktı `%USERPROFILE%\sp11-omarchy-build\out\omarchy-4.5.0-aarch64-sp11-lcd.iso` olur.
Betik önce resmi ISO'nun imzasını doğrular. Sonuçta volume UUID'sinin, boot kayıtlarının ve
LCD-only UKI'nin doğru olduğunu kontrol eder; biri bile tutmazsa durur.

### 2. USB'ye yazın
[Rufus](https://rufus.ie)'un ARM64 sürümünü kullanın ve **DD imaj modunu** seçin. Ventoy kullanmayın:
ISO, GRUB → UKI zinciriyle ve volume UUID'siyle açılır.

### 3. Surface UEFI ayarları
- Surface kapalıyken **Ses Açma + Güç** tuşlarına basarak UEFI'ye girin.
- *Security → Secure Boot* ayarını **Disabled** yapın.
- *Boot configuration* altında USB'yi en üste alın, ya da açılışta **Ses Kısma + Güç** ile USB'den başlatın.

### 4. USB'den başlatın ve kurun
- GRUB, Snapdragon'u algılayıp "device tree" girdisini kendiliğinden açar. 1–3 dakika siyah ekran normal.
- Canlı ortamda pil yüzdesi ve ses çalışmaz (DSP bilerek kapalı). Bu bir hata değil.
- Kurulum programında Windows'u tutuyorsanız **Free space install** seçin. Disk şifrelemeyi açık bırakın.

### 5. Yeniden başlatmadan önce: `sp11-lcd`
Kurulum "bitti" dediğinde **yeniden başlatmayın**. Canlı USB'de Wi-Fi yoktur; paketlerin USB'de
taşınmasının sebebi bu:

```
Ctrl+Alt+F2  →  root (parola yok)
bash /run/archiso/bootmnt/sp11-lcd/finish-install.sh
```

Disk parolanızı girin. Ekranda `It is safe to reboot.` yazısını görünce `reboot` yazın ve ekran
kararınca USB'yi çıkarın. Ayrıntılar `payload/sp11-lcd/README.md` dosyasında.

### 6. İlk açılışta kontrol

```bash
tr -d '\0' </proc/device-tree/model; echo        # "Microsoft Surface Pro 11th Edition (LCD)"
sudo dmesg | grep -iE 'remoteproc|ath12k|msm_dpu' | head -30
qcom-firmware-extract --list-missing             # boş olmalı
systemctl status 'iptsd@*' surface-pro-11-sensors   # dokunmatik/kalem ve ışık sensörü servisleri
wpctl status | grep -A3 Sinks                    # varsayılan çıkış "Internal speakers" olmalı
bluetoothctl show | grep -E 'Controller|Powered' # 00:00:00:00:00:00 değil, gerçek bir adres
```

Windows'u tuttuysanız Limine'e eklemek için `sudo limine-scan` kullanın. Surface'te
*Setup → Direct Boot* **kullanmayın**: Surface UEFI özel EFI girdilerini düşürüyor.

## Ses, dokunmatik, sensörler ve Bluetooth

Omarchy'nin Surface Pro 11 paketleri yalnızca edge deposunda ve OLED modelin device tree'sini
arıyor. `apply.sh` bunları USB'den kurar (`sp11-lcd/pkgs/`; ISO derlenirken resmi hedef imajın içinde
pacman'le, imzalarıyla birlikte çekilir), her güncellemede yeniden çalışan bir pacman kancasıyla
`microsoft,denali-oled` kontrolünü ortak `microsoft,denali` ile değiştirir ve ışık sensörünün
yapılandırmasını bu cihazın Windows sürücü deposundan çıkarır (`sp11-lcd/sensors/`). Stable kanalında
bu paketler yok ve pacman edge'i stable'ın yanına ikinci depo olarak ekleyemiyor (deponun veritabanı
bölüm adını taşır; Omarchy yalnızca `omarchy.db` sunuyor). Bu yüzden `sp11-lcd-update`, edge'in
veritabanını okuyup yalnızca bu paketlerin yeni sürümlerini `pacman -U` ile URL'den, imza doğrulamalı
kurar. Omarchy'nin `post-update` kancası bunu her `omarchy-update` sonrasında çalıştırır.

| Paket | Sağladığı |
|---|---|
| `microsoft-surface-pro-11-support` | Hoparlör topolojisi ve UCM, hoparlör koruması (bu cihazın Dolby ayarı `MSHW0486 REV_0D` ile üretilmiş limitleyici), Wi-Fi board verisi, Flex Klavye ve Slim Pen Bluetooth eşleştirmesi, uyku kancaları |
| `iptsd` | Dokunmatik ekran ve kalem |
| `microsoft-surface-pro-11-sensors` | Ortam ışığı sensörü (otomatik parlaklık), ADSP üzerinden |
| `microsoft-surface-snapdragon-addresses` | Bluetooth adresi ve sabit Wi-Fi MAC'i; bu olmadan WCN7850 yapılandırılmamış bir Bluetooth denetleyicisi olarak kalıyor |
| `microsoft-surface-pro-11-firmware` | DSP/GPU firmware'i, Microsoft'un MSI'sinden (sürücü deposundaki kopyalarla aynı) |

Bunun LCD modele uyması neden bekleniyor: ses kartı düğümü, hoparlör yolları ve dijitalleştirici iki
modelin paylaştığı device tree'de; bu cihazın ses ayar kimliği ve sensör yapılandırma özetleri
Omarchy'nin OLED cihazda doğruladıklarıyla aynı; Surface Pro 11 çekirdek yamalarının hepsi zaten stable
çekirdekte. Sesi başka UCM ayarlarıyla açmayın; hoparlörün tek koruması bu limitleyici.

## Bilinen eksikler ve açık konular

- **Wi-Fi board verisi:** Omarchy'nin OLED kurulumunda olduğu gibi `board.bin`, bu Surface'e özel
  kalibrasyon değil, Qualcomm'un referans kalibrasyonu. Kartın istediği board-id'yi
  `sudo dmesg | grep ath12k` ile görebilirsiniz.
- **Stable sistemde edge paketleri:** edge bu beş paketten birini stable aynasında henüz olmayan bir
  kütüphaneye karşı derlerse, `omarchy-update` o paket için bağımlılık hatası verir; stable aynası
  yetişince (en fazla bir ay) geçer. Başka hiçbir şey etkilenmez.
- Düzeltmeden önce alınmış Snapper anlık görüntülerinin boot girdileri eski UKI'yi, yani OLED
  tree'sini açabilir.
- *Setup → Reset Computer*, kurulum programının düzeltmeden önceki temel anlık görüntüsüne döner.
  Sıfırlamadan sonra `apply.sh`'i USB'den yeniden çalıştırın.

## Nasıl çalışır

| Dosya | Görev |
|---|---|
| `build-iso.ps1` | Windows tarafı: ISO'yu indirir, sp11-lcd'yi firmware ve sensör yapılandırmasıyla DriverStore'dan hazırlar, paketleri çeker, konteyneri çalıştırır |
| `build/fetch-packages.sh` | Omarchy'nin Surface Pro 11 paketlerini ve eksik bağımlılıklarını, imzalarıyla, resmi hedef imajın içinde pacman çalıştırarak çözer ve indirir |
| `build/Dockerfile` | arm64 Debian araç kutusu (ukify, xorriso, squashfs-tools, gnupg) |
| `build/remaster.sh` | İmzayı doğrular. Canlı UKI'yi kendi çekirdeği, initrd'si ve canlı sistemin systemd-stub'ı (262.1) ile, LCD tree'si tek `.dtb` olacak şekilde yeniden kurar. ISO'yu volume tarihleri ve UUID korunarak paketler, sonra her adımı doğrular |
| `build/uki-dtb.py` | UKI bölümlerini ayırır ve "bu UKI hangi tree ile açılır" kontrolünü yapar (bağımlılıksız; ISO'da ve kurulu sistemde de kullanılır) |
| `payload/sp11-lcd/finish-install.sh` | Canlı USB'den kurulu sistemi açar, bağlar ve `apply.sh`'i chroot içinde çalıştırır |
| `payload/sp11-lcd/apply.sh` | Cihaz kontrolü (panel EDID'i LGD mi), tree sabitleme, initramfs, Surface Pro 11 paketleri, firmware, Wi-Fi board verisi, yeniden derleme, UKI doğrulama ve firmware boot sırası |
| `payload/sp11-lcd/sp11-lcd-ungate`, `90-sp11-lcd-ungate.hook` | pacman kancası: destek ve sensör paketlerinin her kurulum/güncellemeden sonra `-oled` yerine `microsoft,denali` ile çalışmasını sağlar |
| `payload/sp11-lcd/sp11-lcd-update`, `sp11-lcd-post-update` | Beş paketi edge'deki sürümlere getirir (`pacman -U` ile URL'den, imza doğrulamalı); Omarchy'nin `post-update` kancasından ya da elle çalışır |
| `payload/sp11-lcd/extract-ath12k-board.py` | Omarchy'nin MIT lisanslı board kaydı çıkarıcısının değiştirilmemiş kopyası |
| `payload/sp11-lcd/sp11-lcd-devicetree` | `/etc/boot/hooks/pre.d/90-…`: her UKI derlemesinden önce `uki.conf` dosyasında LCD tree'sini sabitler |
| `payload/sp11-lcd/zz-sp11-lcd.conf` | initramfs modülleri (yalnızca çekirdekte bulunanlar, `?` kullanmadan) |
| `tools/sp11-chid.ps1` | Bu cihazın systemd CHID'lerini hesaplar ve hangi tree'nin seçileceğini gösterir |
| `test/chroot-test.ps1`, `test/chroot-test.sh` | `build-iso.ps1`'den sonra çalıştırılır. Hazırlanan düzeltmeyi resmi hedef kök imajında (copy-on-write) uygular. Tree sabitlemesini, hedef çekirdek için üretilen initramfs'i, imza doğrulamalı çevrimdışı paket kurulumunu ve kilidin açılmasını, sensör çıkarımını, LCD device tree'sine göre firmware'i, Wi-Fi board kaydını ve `limine-mkinitcpio`'nun derlediği şekilde üretilen UKI'yi kontrol eder |
| `test/fstab-test.sh` | `finish-install.sh`'in fstab işleyişinin birim testi (Omarchy ISO ve genfstab biçimleri) |

## Upstream'e gönderilebilecekler
- **systemd:** `x1p64100-microsoft-denali.json` (`microsoft,denali-lcd`). EDID panel CHID'leri
  (LGD077B) daha öncelikli olduğu için LCD modeli otomatik ayırt edilebilir.
- **Omarchy:** `install/hardware/microsoft/surface-pro-11.sh` dosyasına `denali-lcd` desteği
  (LCD tree'si ve `panel-edp`).
- **omarchy-pkgs:** `microsoft-surface-pro-11-support` ve `-sensors` kontrolleri `microsoft,denali-oled` yerine
  `microsoft,denali` üzerinden yapılmalı.

## Kaynaklar
- [omacom/omarchy](https://github.com/omacom/omarchy) (v4.5.0 ve quattro dalı), [omarchy-iso](https://github.com/omacom/omarchy-iso), [omarchy-pkgs](https://github.com/omacom/omarchy-pkgs)
- [Introducing Omarchy Dragon](https://omarchy.org/news/2026/09/introducing-omarchy-dragon/)
- [qBitnaut/omarchy-dragon-sl7](https://github.com/qBitnaut/omarchy-dragon-sl7): Surface Laptop 7 (X1P-64-100). Initramfs ve "upstream tehlikeleri" listesi.
- [harrisonvanderbyl/surface-pro-12-inch-linux](https://github.com/harrisonvanderbyl/surface-pro-12-inch-linux), [bprendie/omarchy-snapdragon](https://github.com/bprendie/omarchy-snapdragon), [javon27/omarchy-surface-touch](https://github.com/javon27/omarchy-surface-touch)
- Linux `arch/arm64/boot/dts/qcom/x1p64100-microsoft-denali.dts` (Dale Whinham), systemd `src/boot/{stub,pe,chid,devicetree}.c`
