# omarchy-dragon-sp11

[English](README.md) | **Türkçe**

[Omarchy](https://omarchy.org) 4.5'i **Microsoft Surface Pro 11'in LCD / Snapdragon X Plus
(X1P64100)** modeline kurmak için resmi Omarchy aarch64 ISO'sunun üzerine ince bir katman.

Resmi, imzalı ISO'ya yalnızca iki şey eklenir:

1. Canlı (live) UKI, LCD modelin device tree'siyle açılır.
2. Kurulumdan sonra bir kez çalıştırılan `sp11-lcd/` düzeltmesi eklenir. Bu düzeltme,
   kurulan sistemin de doğru tree, initramfs ve firmware ile açılmasını sağlar.

Çekirdek, paketler ve kurulum programı Omarchy'nin kendisidir. Hiçbir şey yeniden
derlenmez ve yabancı paket eklenmez.

> **Durum:** ISO derleniyor ve konteynerde otomatik doğrulanıyor. Gerçek cihazda kurulum
> testi henüz yapılmadı; sonuçlar bu dosyaya eklenecek.

## Neden gerekli?

Omarchy 4.5.0 Snapdragon'u resmi olarak destekliyor. Çekirdeği (`linux-omarchy` 7.3)
Surface Pro 11 için çok sayıda yama taşıyor ve LCD modelin tree'si
(`x1p64100-microsoft-denali.dtb`) zaten ISO'nun içinde. Yine de bu modelde dört sorun var:

| Sorun | Kanıt | Bu repo ne yapıyor |
|---|---|---|
| systemd-stub her Surface Pro 11'e **OLED** tree'sini yüklüyor. OLED, LCD ve X Plus modellerinin SMBIOS kimlikleri aynı ve systemd'nin `hwids` kaydı yalnızca `microsoft,denali-oled`'i tanıyor. Eşleşen bir `.dtbauto`, `.dtb`'nin önüne geçiyor (systemd `src/boot/stub.c`). | `tools/sp11-chid.ps1`: bu cihazın CHID'leri OLED kaydıyla 3, 4, 5, 6, 7, 8, 9 ve 10 numarada eşleşiyor. stub, CHID 3 ile OLED'i seçiyor. | Canlı UKI'ye ve kurulu UKI'ye LCD tree'si tek, koşulsuz `.dtb` olarak konuyor. Bir pre.d kancası bunu her yeniden derlemede koruyor. |
| 4.5.0'da Surface Pro 11'e özel kurulum betiği yok. Klavye (`surface_aggregator`, `surface_hid`), ekran (`msm`, `panel-edp`, eDP PHY) ve pmic_glink sürücülerinin hepsi modül. Bu yüzden disk şifresi ekranında klavye ya da görüntü olmayabilir. | ISO'daki `modules.order` | Omarchy'nin quattro dalındaki Surface Pro 11 modül listesi, LCD paneline uyarlanarak initramfs'e ekleniyor. |
| DSP/GPU firmware'i ya stable depoda yok ya da yalnızca Windows bölümünden çıkarılabiliyor. BitLocker açıkken bölüm okunamıyor. | stable aarch64 deposunda `microsoft-surface-pro-11-*` paketleri yok | Bu cihazın Windows sürücü deposundaki imzalı dosyalar ISO'ya konuyor ve Omarchy'nin `qcom-firmware-extract -d` aracıyla kuruluyor. |
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
Kurulum "bitti" dediğinde **yeniden başlatmayın**:

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
```

Windows'u tuttuysanız Limine'e eklemek için `sudo limine-scan` kullanın. Surface'te
*Setup → Direct Boot* **kullanmayın**: Surface UEFI özel EFI girdilerini düşürüyor.

## Bilinen eksikler ve açık konular

- **Wi-Fi board verisi:** Bu kartın alt sistem kimliği (`17cb:1107`), Omarchy'nin OLED cihazda
  doğruladığı kayıttan (`3378`) farklı. `board-2.bin` içinde `1107` için yalnızca board-id 44 ve 82
  var. `dmesg` çıktısında `ath12k ... board data` hatası görürseniz bildirin. OLED kaydı bilerek
  uygulanmadı.
- **Ses, kalem/dokunmatik (iptsd), ışık sensörü, Flex klavye eşleştirme:** Omarchy bunları
  `microsoft-surface-pro-11-support`, `iptsd` ve `microsoft-surface-pro-11-sensors` paketleriyle
  veriyor. Bu paketler şimdilik yalnızca **edge** kanalında ve servisleri yalnızca
  `microsoft,denali-oled` için çalışıyor. Hoparlör koruma limitleyicisi de bu pakette. Rastgele
  UCM ayarlarıyla ses açmayın; hoparlör zarar görebilir.
- Düzeltmeden önce alınmış Snapper anlık görüntülerinin boot girdileri eski UKI'yi, yani OLED
  tree'sini açabilir.

## Nasıl çalışır

| Dosya | Görev |
|---|---|
| `build-iso.ps1` | Windows tarafı: ISO'yu indirir, sp11-lcd'yi ve firmware'i DriverStore'dan hazırlar, konteyneri çalıştırır |
| `build/Dockerfile` | arm64 Debian araç kutusu (ukify, xorriso, squashfs-tools, gnupg) |
| `build/remaster.sh` | İmzayı doğrular. Canlı UKI'yi kendi çekirdeği, initrd'si ve canlı sistemin systemd-stub'ı (262.1) ile, LCD tree'si tek `.dtb` olacak şekilde yeniden kurar. ISO'yu volume tarihleri ve UUID korunarak paketler, sonra her adımı doğrular |
| `build/uki-dtb.py` | UKI bölümlerini ayırır ve "bu UKI hangi tree ile açılır" kontrolünü yapar (bağımlılıksız; ISO'da ve kurulu sistemde de kullanılır) |
| `payload/sp11-lcd/finish-install.sh` | Canlı USB'den kurulu sistemi açar, bağlar ve `apply.sh`'i chroot içinde çalıştırır |
| `payload/sp11-lcd/apply.sh` | Cihaz kontrolü (panel EDID'i LGD mi), tree sabitleme, initramfs, firmware, yeniden derleme ve UKI doğrulama |
| `payload/sp11-lcd/sp11-lcd-devicetree` | `/etc/boot/hooks/pre.d/90-…`: her UKI derlemesinden önce `uki.conf` dosyasında LCD tree'sini sabitler |
| `payload/sp11-lcd/zz-sp11-lcd.conf` | initramfs modülleri (yalnızca çekirdekte bulunanlar, `?` kullanmadan) |
| `tools/sp11-chid.ps1` | Bu cihazın systemd CHID'lerini hesaplar ve hangi tree'nin seçileceğini gösterir |

## Upstream'e gönderilebilecekler
- **systemd:** `x1p64100-microsoft-denali.json` (`microsoft,denali-lcd`). EDID panel CHID'leri
  (LGD077B) daha öncelikli olduğu için LCD modeli otomatik ayırt edilebilir.
- **Omarchy:** `install/hardware/microsoft/surface-pro-11.sh` dosyasına `denali-lcd` desteği
  (LCD tree'si ve `panel-edp`).
- **omarchy-pkgs:** `microsoft-surface-pro-11-support` kontrolleri `microsoft,denali-oled` yerine
  `microsoft,denali` üzerinden yapılmalı.

## Kaynaklar
- [omacom/omarchy](https://github.com/omacom/omarchy) (v4.5.0 ve quattro dalı), [omarchy-iso](https://github.com/omacom/omarchy-iso), [omarchy-pkgs](https://github.com/omacom/omarchy-pkgs)
- [Introducing Omarchy Dragon](https://omarchy.org/news/2026/09/introducing-omarchy-dragon/)
- [qBitnaut/omarchy-dragon-sl7](https://github.com/qBitnaut/omarchy-dragon-sl7): Surface Laptop 7 (X1P-64-100). Initramfs ve "upstream tehlikeleri" listesi.
- [harrisonvanderbyl/surface-pro-12-inch-linux](https://github.com/harrisonvanderbyl/surface-pro-12-inch-linux), [bprendie/omarchy-snapdragon](https://github.com/bprendie/omarchy-snapdragon), [javon27/omarchy-surface-touch](https://github.com/javon27/omarchy-surface-touch)
- Linux `arch/arm64/boot/dts/qcom/x1p64100-microsoft-denali.dts` (Dale Whinham), systemd `src/boot/{stub,pe,chid,devicetree}.c`
