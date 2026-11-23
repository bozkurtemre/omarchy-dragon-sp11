# omarchy-dragon-sp11

[English](README.md) | **Türkçe**

[Omarchy](https://omarchy.org)'yi **Microsoft Surface Pro 11'in LCD / Snapdragon X Plus (X1P64100,
`microsoft,denali-lcd`)** modeline, Omarchy'nin kendi aarch64 **edge** ISO'suyla kurmak; buna ek
olarak upstream'in dağıtamayacağı tek şey: tam disk kurulumunun sildiği, bu makineye ait Windows
dosyaları.

> **Durum, 2026-11-20:** edge ISO'yla gerçek cihazda henüz hiçbir şey açılmadı. Bu reponun önceki,
> 4.5.0 tabanlı ISO'suyla 2026-11-08'de yapılan deneme açılışı LCD panelde kurulum programına kadar
> geldi. Burada üretilen ISO aşağıdaki konteyner testlerinden geçiyor; Surface'teki sonuçlar buraya
> eklenecek.

## Omarchy artık ne yapıyor

LCD model upstream'de destekleniyor, ama yalnızca edge kanalında (stable ve rc hâlâ 4.5.0-3; 4.5.0'dan
yeni bir sürüm yok):

- **omarchy [PR #18276](https://github.com/omacom/omarchy/pull/18276)**, Iván Ruiz (rdereparadores),
  2026-11-11'de birleştirildi (`b19ad9764d78`): `install/hardware/microsoft/surface-pro-11.sh` her
  Surface Pro 11'i (`microsoft,denali`) tanıyor, `/sys/devices/soc0/soc_id` 615 (X1P-64-100) ise
  UKI'ye `x1p64100-microsoft-denali.dtb`'yi sabitliyor, disk şifresi ekranı panele ulaşsın diye
  initramfs'e `panel_edp`, `pwm_bl` ve `leds_qcom_lpg` ekliyor ve Surface Pro 11 paketlerini
  (`microsoft-surface-pro-11-support`, `iptsd`, `microsoft-surface-pro-11-sensors`) kuruyor.
- **omarchy-pkgs #2378, #2379, #2382**, aynı yazardan: sensör ve destek paketleri iki modelin ortak
  compatible'ı `microsoft,denali` üzerinden çalışıyor; çekirdek paketinde LCD tree'sine PWM arka
  ışığı eklendi, X1P-64-100'de devre dışı olan çekirdekler çıkarıldı ve LCD hwids kaydı
  (`x1p64100-microsoft-denali.json`) geldi; böylece systemd-stub LCD tree'sini panelin EDID'iyle
  seçebiliyor. Edge bunları bugün `linux-omarchy` 7.3-73 ve `linux-omarchy-dtbs` 7.3-52 olarak
  taşıyor.
- **Yazarın LCD cihazda test ettikleri:** parlaklık, cpufreq'li on çekirdek, ses, uyku ve disk şifresi
  ekranı (PR #18276); Wi-Fi, Bluetooth, hoparlörler ve mikrofonlar, iki kamera, Surface Pro
  Keyboard'un klavyesi ve touchpad'i, dokunmatik ve kalem, uykudan dönüşte de (omarchy-pkgs #2379).
  **Orada test edilmeyenler:** LCD modele ISO'dan temiz kurulum, Flex Keyboard'un Bluetooth
  eşleştirmesi, Slim Pen eşleştirmesi.

Bu reponun eskiden etrafından dolaştığı her şey (device tree sabitleme, initramfs modülleri,
paketlerin yalnızca OLED'i kabul eden kontrolleri, stable sistemde edge paketleri, Wi-Fi board verisi,
DSP ve GPU firmware'i) artık edge kurulum programı ve paketleri tarafından yapılıyor. Bkz.
[2026-11-20'de ne değişti](#2026-11-20de-ne-değişti).

## Bu repo ne ekliyor

1. **ISO'da `/sp11-lcd/`**; varsayılan olarak Omarchy'nin edge ISO'sundaki tek değişiklik:
   - `windows/`: bu makinenin Windows sürücü deposunda INF'i sağlayıcı olarak Surface, Qualcomm ya da
     Dolby diyen her sürücü paketi (burada 202 paket, 1104 dosya, 1,3 GB), `device-facts.json` ve bir
     `SHA256SUMS` listesiyle. Bkz. [Windows arşivi](#windows-arşivi).
   - `setup.sh`, ilk açılıştan sonra bir kez çalıştırılır: arşivi `/var/lib/sp11-lcd/windows`'a
     (yalnızca root) kopyalar ve Omarchy'nin kendi `surface-pro-11-sensors-extract -d` aracını onun
     üzerinde çalıştırır. Işık sensörü yapılandırması, upstream'in hâlâ Windows'tan
     (`DriverStore/.../surfacepro_snscfgcrd8380.inf_arm64_*`) okuduğu tek şey; tam disk kurulumu
     onu siler, BitLocker gizler.
   - `camera/setup-camera.sh`, isteğe bağlı: iki kamerayı da yalnızca V4L2 kullanan uygulamalarda
     (Monologue, Omarchy'nin ekran kaydındaki webcam overlay'i) talep üzerine çalışan v4l2loopback
     aktarımlarıyla kullanılabilir yapar. Bkz.
     [payload/sp11-lcd/camera/README.md](payload/sp11-lcd/camera/README.md) (İngilizce).
   - `ir-camera/setup-ir-camera.sh`, isteğe bağlı, kamera kurulumundan sonra: IR (Windows Hello)
     kamerasını `/dev/video42` olarak sunar, IR ışığı yalnızca görüntü alınırken yanar; omaFace
     gibi yüzle kilit açma için. Bkz.
     [payload/sp11-lcd/ir-camera/README.md](payload/sp11-lcd/ir-camera/README.md) (İngilizce).
   - `touchscreen/setup-touchscreen.sh`, isteğe bağlı: menüdeki *Disable Touchscreen*'in parmakla
     dokunmayı gerçekten kapatmasını sağlar. Bkz.
     [payload/sp11-lcd/touchscreen/README.md](payload/sp11-lcd/touchscreen/README.md) (İngilizce).
2. **`-LcdOnlyUki`, varsayılan olarak kapalı:** Surface firmware'i panelin EDID'ini systemd-stub'a
   vermezse diye canlı UKI'yi yalnızca LCD tree'siyle yeniden kurar. Bkz.
   [Canlı oturum OLED tree'siyle açılırsa](#canlı-oturum-oled-treesiyle-açılırsa).
3. **[contrib/](contrib/README.md):** upstream'e hâlâ gönderilmeye değer olanlar (İngilizce).

Çekirdek, paketler ve kurulum programı Omarchy'nin kendisidir. İsteğe bağlı kamera kurulumu dışında
hiçbir şey yeniden derlenmez, başka bir yerden hiçbir şey kurulmaz: o, kurulan sistemde
`v4l2-relayd-sp11`'i (AUR'daki `v4l2-relayd` ve bir yama) derler.

## Windows'u silmeden önce

Bunları hiçbir betik sizin yerinize yapamaz:

- **Windows Update'i ve bütün Surface firmware güncellemelerini bitirin.** Surface firmware'i (UEFI
  ile dokunmatik, kalem ve klavye firmware'i) Windows Update üzerinden gelir; Omarchy'de Surface
  UEFI'sini güncellemenin bir yolu yok.
- <https://support.microsoft.com/surface-recovery-image> adresinden bir **Surface Recovery Image
  USB'si** hazırlayın (seri numarası gerekir; ayağın altında ya da *Ayarlar > Sistem > Hakkında*'da).
  Windows'a ve firmware güncellemelerine dönüş yolu odur.
- **Kişisel verilerinizi yedekleyin** ve **BitLocker kurtarma anahtarını** kaydedin
  (<https://aka.ms/myrecoverykey>).
- **ISO'yu Windows hâlâ duruyorken oluşturun** (aşağıda): arşiv bu Windows kurulumundan kopyalanır.
- **Makinenin dışında bir kopya daha tutun.** Kurulumdan sonra bu dosyaların tek kopyaları USB bellek
  ve `/var/lib/sp11-lcd/windows` olur. ISO'yu ya da hazırlanan
  `%USERPROFILE%\sp11-omarchy-build\payload\sp11-lcd` klasörünü başka bir diske ya da kendi bulut
  depolamanıza kopyalayın. İçinde bu cihaza ait Microsoft, Qualcomm ve Dolby dosyaları var: kimseyle
  paylaşmayın.

## Kurulum

### 1. ISO'yu oluşturun (bu Surface'te, Windows'ta)

Docker Desktop açıkken:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-iso.ps1
```

- Taban, <https://nightly.omarchy.org/edge-aarch64/latest.json> dosyasının gösterdiği resmi edge
  nightly ISO'su (8,5 GB, `%USERPROFILE%\sp11-omarchy-build\dl` içine bir kez indirilir). Betik
  boyutunu ve SHA256'sını `latest.json` ve `.sha256` dosyasıyla karşılaştırır. **Edge ISO'larının
  sürüm imzası yoktur**: sağlama toplamı indirmenin Omarchy'nin sunucusundan bozulmadan geldiğini
  kanıtlar, ISO'yu kimin oluşturduğunu değil. [build/edge/build-edge-iso.sh](build/edge/build-edge-iso.sh)
  ile kendiniz oluşturduğunuz bir ISO'yu kullanmak için `-Iso <yol>` verin.
- Çıktı `%USERPROFILE%\sp11-omarchy-build\out\<taban adı>-sp11-lcd.iso` (yaklaşık 9,9 GB); yanında
  `.sha256` ve `.provenance.txt` (taban sürümü, `iso_commit`, `omarchy_version`, çekirdek, sağlama
  toplamları) olur. Toplamda yaklaşık 20 GB gerekir (8,5 GB'lık indirme, 1,3 GB'lık arşiv ve çıktı);
  betik, boş alan 8 GB'ın altına inecekse başlamadan durur.
- Sonda volume UUID'sinin, tarihlerin, boot kayıtlarının, GRUB menüsünün ve canlı UKI'nin tabanınkiyle
  aynı olduğunu, `/sp11-lcd`'nin de hazırlananla dosya dosya eşleştiğini kontrol eder.

### 2. USB belleğe yazın

En az 16 GB. [Rufus](https://rufus.ie)'un ARM64 sürümünü **DD imaj modunda** kullanın. Ventoy
kullanmayın: ISO, GRUB ve bir UKI üzerinden açılır ve kendini volume UUID'siyle bulur.

### 3. Deneme açılışı (önerilir, geri dönüşü olmayan adımlardan önce)

1. Yönetici PowerShell'de: `Suspend-BitLocker -MountPoint 'C:' -RebootCount 0`; böylece Secure Boot
   kapatıldıktan sonra Windows kurtarma anahtarı istemez.
2. Surface kapalıyken UEFI için **Ses Açma + Güç**'e basılı tutun. *Security > Secure Boot*'u
   **Disabled** yapın. USB'den **Ses Kısma + Güç** ile başlatın ya da *Boot configuration*'da USB'yi
   en üste alın.
3. GRUB, Snapdragon'da "device tree" girdisini kendisi seçer; bir dakika ya da daha uzun siyah ekran
   normaldir. Canlı oturum doğrudan Omarchy'nin kurulum programını açar. Henüz kurmayın.
4. **Ctrl+Alt+F2** bir konsol açar; `root` olarak girin (parola yok). Kontrol edin:
   ```
   tr -d '\0' </proc/device-tree/model; echo   # Microsoft Surface Pro 11th Edition (LCD)
   cat /sys/devices/soc0/soc_id                 # 615
   cd /run/archiso/bootmnt/sp11-lcd/windows && sha256sum --quiet -c SHA256SUMS && echo archive ok
   ```
   Son satır, Windows hâlâ yerindeyken bu bellekteki arşivin okunabilir ve eksiksiz olduğunu
   kanıtlar (yol farklıysa `findmnt -n -o TARGET /run/archiso/bootmnt` ortamı gösterir).
   Görüntüyü, klavyeyi ve touchpad'i de kontrol edin. Model "(OLED)" diyorsa
   [aşağıya](#canlı-oturum-oled-treesiyle-açılırsa) bakın.
5. Windows'a dönünce: `Resume-BitLocker -MountPoint 'C:'`.

### 4. Kurun

- **Tam disk kurulumu** (Windows'u siler): kurulum programında diskin tamamını seçin. Omarchy'nin
  Surface Pro 11 adımı ışık sensörü yapılandırmasını okuyacak bir Windows bulamaz; onu ilk açılıştan
  sonra `setup.sh` sağlar.
- **Çift açılış:** Omarchy'nin boş alana kurulumu için BitLocker'ın kapatılması (*Ayarlar > Gizlilik
  ve güvenlik > Cihaz şifreleme*; şifre çözme saatler sürer) ve *Disk Yönetimi*'nde C: küçültülerek
  boş alan açılması gerekir. Omarchy sensör yapılandırmasını o zaman Windows'tan kendisi okur; arşivi
  saklamanın yolu yine `setup.sh`.
- **Secure Boot kapalı** kalsın. Disk şifrelemeyi açık bırakın.

### 5. İlk açılış

Belleği bağlayın ve `setup.sh`'i bir kez çalıştırın (ayrıntılar
[payload/sp11-lcd/README.md](payload/sp11-lcd/README.md) dosyasında, İngilizce):

```bash
sudo mount -o ro /dev/disk/by-label/OMARCHY_* /mnt    # etiketi lsblk -f gösterir
sudo bash /mnt/sp11-lcd/setup.sh
sudo umount /mnt
```

Sonra kontrol edin:

```bash
tr -d '\0' </proc/device-tree/model; echo           # Microsoft Surface Pro 11th Edition (LCD)
cat /sys/devices/soc0/soc_id                         # 615
grep -A2 'BEGIN OMARCHY SURFACE PRO 11' /etc/kernel/uki.conf   # DeviceTree=.../x1p64100-microsoft-denali.dtb
omarchy-channel-current                              # edge
systemctl status surface-pro-11-sensors              # active (ışık sensörü)
wpctl status | grep -A3 Sinks                        # varsayılan çıkış "Internal speakers"
bluetoothctl show | grep -E 'Controller|Powered'     # 00:00:00:00:00:00 değil, gerçek bir adres
sudo jq .addresses /var/lib/sp11-lcd/windows/device-facts.json   # Windows'un kullandığı adresler
qcom-firmware-extract --list-missing                 # hiçbir şey yazmaz
```

Model "(OLED)" diyorsa ya da `uki.conf` `x1e80100-microsoft-denali-oled.dtb`'yi gösteriyorsa, kurulum
programı socinfo kimliği 615'i görmemiştir (bkz. açık konular). PR #18276'nın migration'ı tam olarak
bu durum için yazıldı (burada denenmedi): kendi kullanıcınızla
`OMARCHY_PATH=/usr/share/omarchy bash /usr/share/omarchy/migrations/1794228778.sh` çalıştırın (sudo
ister, Surface Pro 11 kurulumunu yeniden çalıştırır ve UKI'yi yeniden derler), sonra yeniden başlatın.

Kameraları V4L2 uygulamalarında kullanmak için (isteğe bağlı, internet gerekir;
[ayrıntılar](payload/sp11-lcd/camera/README.md)):

```bash
sudo mount -o ro /dev/disk/by-label/OMARCHY_* /mnt
sudo bash /mnt/sp11-lcd/camera/setup-camera.sh       # root kabuğundan değil, kendi hesabınızdan
sudo umount /mnt
```

Ardından IR kamera için (isteğe bağlı; [ayrıntılar](payload/sp11-lcd/ir-camera/README.md)):

```bash
sudo mount -o ro /dev/disk/by-label/OMARCHY_* /mnt
sudo bash /mnt/sp11-lcd/ir-camera/setup-ir-camera.sh
sudo umount /mnt
```

*Disable Touchscreen* tetikleyicisinin çalışması için (isteğe bağlı; sudo olmadan, kendi
kullanıcınızla; [ayrıntılar](payload/sp11-lcd/touchscreen/README.md)):

```bash
sudo mount -o ro /dev/disk/by-label/OMARCHY_* /mnt
bash /mnt/sp11-lcd/touchscreen/setup-touchscreen.sh
sudo umount /mnt
```

### Kurulan sistem edge kanalını izler

Edge ISO'su `omarchy-dev`'i ve Omarchy'nin edge depolarını kurar; böylece `omarchy-update` Omarchy'nin,
çekirdeğin ve Surface paketlerinin edge'deki günlük derlemelerini, bir sürümden geçmeden getirir:
Omarchy'nin aldığı Snapper anlık görüntülerini tutun ve güncelleme çıktısını okuyun. 4.5.0'dan yeni bir stable sürüm PR #18276'yı ve
yukarıdaki paketleri içerene kadar **stable'a geçmeyin** (`omarchy-channel-set stable`): 4.5.0'da
Surface Pro 11 kurulumu hiç yok.

## Canlı oturum OLED tree'siyle açılırsa

Canlı UKI her Snapdragon tree'sini `.dtbauto` olarak ve systemd'nin `.hwids` bölümünü taşır.
systemd-stub LCD tree'sini yalnızca panelin EDID kimliğini (`LGD077b`) içeren üç CHID ile seçer;
OLED, LCD ve 5G modellerinin paylaştığı yalnızca SMBIOS'tan oluşan CHID'ler `microsoft,denali-oled`'i
seçer ([testler](#testler) iki durumu da hesaplıyor). Surface firmware'inin EDID'i stub'a verip
vermediği **henüz doğrulanmadı**. Vermiyorsa canlı oturum OLED tree'siyle açılır. PR #18276 bunun bu
modelde ne yaptığını anlatıyor: LG paneli, parlaklık kontrolünü panelin yok saydığı Samsung OLED panel
sürücüsüyle çalışır ve on çekirdeğin altısı cpufreq almaz. Yazarın LCD cihazı düzeltmeden önce bu
şekilde kurulmuştu; bu, panelin yine de yandığını ve kurulum programının kullanılabilir kaldığını
düşündürüyor (bir çıkarım; burada denenmedi). Kurulan sistem buna bağlı değil: kurulum programı
tree'yi socinfo kimliğine göre sabitler.

Panel karanlık kalırsa ya da canlı oturumu yine de LCD tree'siyle açmak isterseniz yedek yapıyı
oluşturun. Canlı UKI'yi Omarchy'nin kendi çekirdeği, initrd'si ve stub'ıyla, LCD tree'si tek ve
koşulsuz `.dtb` olacak şekilde yeniden kurar; 2026-11-08'de kurulum programına kadar gelen yaklaşım
budur:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-iso.ps1 -LcdOnlyUki
```

## Bilinen açık konular

- **V4L2 uygulamalarında kameralar:** Monologue ve ekran kaydındaki webcam overlay'i kamera
  bulamıyor, çünkü iki kamera da yalnızca libcamera ve PipeWire üzerinden çalışıyor
  ([omarchy-pkgs #3105](https://github.com/omacom/omarchy-pkgs/issues/3105)). İsteğe bağlı
  [camera/setup-camera.sh](payload/sp11-lcd/camera/README.md) bunu aşar. Görüntü, libcamera'nın
  simple IPA'sıyla hâlâ loş ve hafif yeşil.
- **IR kamera kullanılmıyor:** IR sensörü ve ışığı çalışıyor, ama sensör PipeWire'dan gizli ve
  düz bir V4L2 cihazı yok; yüzle kilit açma IR kamera bulamıyor. İsteğe bağlı
  [ir-camera/setup-ir-camera.sh](payload/sp11-lcd/ir-camera/README.md) bir tane sağlar.
- **Disable Touchscreen işe yaramıyor:** Omarchy ham SPI dokunmatik ekranını kapatıyor, ama
  parmakla dokunma iptsd'nin sanal dokunmatik ekranından geliyor. İsteğe bağlı
  [touchscreen/setup-touchscreen.sh](payload/sp11-lcd/touchscreen/README.md) bunu aşar.
- **Sağ hoparlör:** ikinci WSA884x amplifikatörü çalma sırasında hataya düşüyor
  ([omarchy #18383](https://github.com/omacom/omarchy/issues/18383)).
- **Flex Keyboard Bluetooth eşleştirmesi ve Slim Pen eşleştirmesi** upstream'de LCD modelde test
  edilmedi.
- **KVM ve hazırda bekletme** bu makinede yok.
- **Direct Boot** upstream'den kaldırıldı. *Reset Computer* artık *Remove > Factory Reset*: kök
  subvolume'u kurulum anındaki anlık görüntüyle değiştirir ve `/home`'u yeniden oluşturur; bu yüzden
  sonrasında `/var/lib/sp11-lcd` ve sensör yapılandırması gider. `setup.sh`'i bellekten ya da diğer
  kopyanızdan yeniden çalıştırın.
- **Kurulum sırasında socinfo:** kurulum programı LCD tree'sini yalnızca kendisi çalışırken
  `/sys/devices/soc0/soc_id` 615 okuyorsa sabitler (socinfo bir modül); yoksa OLED tree'si
  sabitlenir. Temiz kurulumda doğrulanmadı; yukarıdaki ilk açılış kontrolleri bunu yakalar.
- **Wi-Fi board verisi:** bkz. [contrib/README.md](contrib/README.md#2-linux-firmware-has-an-exact-wi-fi-board-record-now).

## Windows arşivi

`build-iso.ps1`, yönetici hakkı olmadan, `C:\Windows\System32\DriverStore\FileRepository` içinde
INF'inin `[Version]` bölümü sağlayıcı olarak Surface, Qualcomm ya da Dolby diyen her paketi
kopyalar. Bu makinede bu 202 paket, 1104 dosya, 1,3 GB ediyor. Hepsini almak, Linux araçlarının
hangilerini okuyacağını tahmin etmekten hem basit hem güvenli. İçinde şunlar var:

| Ne | Sürücü paketleri | Linux'ta okuyan |
|---|---|---|
| Işık sensörü yapılandırması | `surfacepro_snscfgcrd8380` | `surface-pro-11-sensors-extract` (bugün) |
| ADSP, CDSP, GPU ve video firmware'i, pil yöneticisi yapılandırması | `surfacepro_ext_adsp8380`, `qcnspmcdm_ext_cdsp8380`, `qcdx8380` (`qcvss8380.mbn`, `qcdxkmsuc8380.mbn`) | `qcom-firmware-extract -d` (Omarchy'nin firmware paketi aynı dosyaları taşıyor, bkz. [Testler](#testler)) |
| Dolby hoparlör ayarı (`AUCD_DEV_0C29_SUBSYS_MSHW0486_REV_0D_ADCM_SUBSYS_MSHW0486.xml`) | `dax3_ext_qc` | hoparlör limitleyicisinin üretildiği `/usr/lib/surface-pro-11-support/dolby2pipewire.py` |
| Kamera sensörü ve ISP ayarları | `surfacecam*8380`, `qccam*8380` | henüz hiçbir şey; ön kamera renk çalışması (omarchy-pkgs #3105) |
| Wi-Fi board verisi (`bdwlan*`, `regdb.bin`), Bluetooth firmware'i ve NVM | `qcwlanhmt8380`, `qcbluetooth8380` | henüz hiçbir şey; bu Surface'in kendi kalibrasyonu, ileride bir board-2.bin kaydı için |
| Dokunmatik, kalem, klavye, UEFI, SAM ve retimer firmware'i | `surfacetouchpen*`, `surfacetypecover*`, `surface_uefi*`, `surfacesam`, `surfaceretimer*` | hiçbir şey; kayıt için saklanıyor |

`device-facts.json` SMBIOS alanlarını, firmware bileşen sürümlerini, SoC'yi, panelin EDID kimliğini
(`LGD077b`), Wi-Fi, Bluetooth ve ses kimliklerini (`AUCD\VEN_QCOM&DEV_0C29&SUBSYS_MSHW0486&REV_0D`),
Windows'un kullandığı Wi-Fi ve Bluetooth adreslerini ve bunlardan çıkan `MacAddressEmulationAddress`'i
kaydeder (Wi-Fi + 2 = Bluetooth + 1, `microsoft-surface-snapdragon-addresses`'in okuduğu düzen; UEFI
değişkeninin kendisini Windows'ta okumak yönetici hakkı ister). İçinde kurtarma anahtarı, ürün
anahtarı, seri numarası ya da hesap bilgisi yok. `SHA256SUMS` her dosyayı listeler.

## Nasıl çalışır

| Dosya | Görev |
|---|---|
| `build-iso.ps1` | Windows tarafı: edge ISO'sunu alır (nightly, `latest.json`'a göre doğrulanır, ya da `-Iso`), `sp11-lcd/`'yi sürücü arşivi ve cihaz bilgileriyle hazırlar, remaster'ı çalıştırır, kaynak bilgisini yazar |
| `build/Dockerfile` | Remaster için Debian araç kutusu (xorriso, ukify, squashfs-tools) |
| `build/remaster.sh` | Volume UUID'si, tarihleri ve boot kayıtları korunarak `/sp11-lcd`'yi ekler; `LCD_ONLY_UKI=1` ile canlı UKI'yi `systemd-stub-omarchy` üzerinde yalnızca LCD tree'siyle yeniden kurar (bütün GRUB girdileri bu tek dosyayı açar, 256 MiB sınırı); değiştirdiği ve değiştirmediği her şeyi doğrular |
| `build/uki-dtb.py` | UKI bölümlerini ayırır ve bir UKI'nin hangi tree ile açılacağını kontrol eder |
| `build/edge/build-edge-iso.sh` | Edge ISO'sunu omarchy-iso'nun kendi `omarchy-iso-make --arch aarch64 --edge` komutuyla yerelde oluşturur |
| `build/edge/verify-edge-iso.sh` | Bir edge ISO'sunun LCD model için ne taşıdığını açmadan kontrol eder: GRUB, `.dtbauto` ve `.hwids`, initramfs modülleri, paketler, kurulum programının LCD dalı |
| `build/edge/hwids.py` | Bir UKI'nin `.hwids` bölümünü okur ve systemd-stub'ın panel EDID'iyle ve EDID'siz hangi tree'yi seçeceğini hesaplar |
| `build/edge/Dockerfile` | Doğrulama ve testler için Arch Linux ARM araç kutusu (omarchy-iso'nun derleme imajı) |
| `payload/sp11-lcd/setup.sh`, `README.md` | ISO'ya giderler; kurulum sonrası adım |
| `payload/sp11-lcd/camera/` | ISO'ya gider; isteğe bağlı kamera aktarımı: `setup-camera.sh`, `v4l2-relayd-sp11` PKGBUILD'i ve yaması, kullanıcı servisi, v4l2loopback seçenekleri ve bir WirePlumber kuralı |
| `payload/sp11-lcd/ir-camera/` | ISO'ya gider; isteğe bağlı IR kamera: `setup-ir-camera.sh`, aktarım ve IR ışığı servisleri ve `surface-ir-emitter` izleyicisi |
| `payload/sp11-lcd/touchscreen/` | ISO'ya gider; isteğe bağlı dokunmatik ekran anahtarı: `setup-touchscreen.sh` ve `surface-touchscreen` |
| `tools/sp11-chid.ps1` | Bu makinenin systemd CHID'lerini Windows'ta hesaplar ve bir hwids JSON'uyla karşılaştırır |
| `test/edge-test.ps1`, `test/edge-test.sh`, `test/dtb2fs.py` | Konteyner testi |
| `contrib/` | Upstream adayları |

## Testler

```powershell
powershell -ExecutionPolicy Bypass -File .\test\edge-test.ps1 -BaseIso <edge ISO> [-Iso <çıktı>]
```

Test iki ISO'yu ve edge hedef kök imajını (overlay olarak; hiçbirine yazılmaz) ayrıcalıklı bir
konteynerde bağlar ve şunları kontrol eder:

1. Çıktı tabanla aynı şekilde açılır: volume UUID'si ve tarihleri, El Torito ve GPT kayıtları,
   GRUB'lu EFI boot bölümü bayt bayt, `grub.cfg`, tabanın her dosyası değişmeden (`-LcdOnlyUki` ile
   canlı UKI hariç hepsi) ve ortamın kendi sağlama toplamları (`omarchy-root.img.zst.sha256`,
   `airootfs.sha512`, `qcom-firmware/SHA256SUMS`).
2. `/sp11-lcd`'de reponun `payload/sp11-lcd/` altındaki her dosyası (`setup.sh`, `README.md`,
   `camera/`, `ir-camera/`, `touchscreen/`) var, betiklerinin sözdizimi geçerli ve `windows/`
   eksiksiz. Bu klasörlerdeki kurulum betikleri çalışan bir sistem ister, konteynerde
   çalıştırılmaz; Surface üzerinde çalıştırıldılar (bkz. [kamera](payload/sp11-lcd/camera/README.md),
   [IR kamera](payload/sp11-lcd/ir-camera/README.md) ve [dokunmatik ekran](payload/sp11-lcd/touchscreen/README.md) README'leri).
3. Varsayılan yapı: canlı UKI Omarchy'nin kendisi ve `build/edge/verify-edge-iso.sh` çıktı üzerinde
   geçiyor. Yedek yapı: `uki-dtb.py check` geçiyor; çekirdek, initrd, os-release ve uname Omarchy'ninkiyle
   bayt bayt aynı; `.cmdline` ya da `.dtbauto` yok; 256 MiB içinde.
4. `setup.sh`, bağlanmış ISO'dan, edge hedef kök imajının içinde, imajın kendi
   `x1p64100-microsoft-denali.dtb`'si çalışan tree ve socinfo kimliği 615 olarak iki kez çalıştırılıyor:
   arşiv `/var/lib/sp11-lcd/windows`'a yalnızca root'a açık ve eksiksiz iniyor, sensör yapılandırması
   oradan çıkarılıyor. Başka bir makinenin tree'sinde çalışmayı reddediyor.
5. Burada yazan bilgiler: Omarchy'nin `microsoft-surface-pro-11-firmware` paketi bu makinenin sürücü
   deposuyla dosya dosya; `contrib/`'deki CHID'ler Omarchy'ninkilerle ve `device-facts.json` ile.

2026-11-20 sonuçları, `omarchy-2026.11.20-aarch64-edge.iso`'ya karşı (omarchy-iso `acf0d36` ve
omarchy `b20d787` ile yerel derleme; nightly 2026.11.20.497'nin commit'leri): sondaki
[Test sonuçları](#test-sonuçları) bölümünde.

## 2026-11-20'de ne değişti

2026-11-19'a kadar bu repo imzalı stable 4.5.0 ISO'sunu yeniden paketliyor ve kurulan sistemi ilk
açılıştan önce USB'den düzeltiyordu: LCD tree sabitlemesi ve onu koruyan bir pre.d kancası, initramfs
modülleri, paketlerin yalnızca OLED'i kabul eden kontrollerini yeniden yazan bir pacman kancası,
edge'den USB'ye çekilen Omarchy Surface Pro 11 paketleri ve yalnızca bu beşini edge'de tutan bir
güncelleyici, Wi-Fi board kaydı ve sürücü deposundan DSP/GPU firmware'i. Omarchy'nin edge kanalı artık
bunların hepsini kendisi yapıyor (yukarıda) ve "stable artı beş edge paketi" tasarımı artık çalışmıyor:
support 1-9, edge'in `linux-firmware-qcom` 20261019-1.1 paketini istiyor. Stable çekirdek de artık LCD
modelin ihtiyacı olan her şeyi taşımıyor: LCD tree'sinin PWM arka ışığı ve devre dışı çekirdeklerinin
çıkarılması edge'deki `linux-omarchy-dtbs` 7.3-52'de. Eski betikler git geçmişinde (`5c4807d` ve öncesi).

## Kaynaklar

- [omacom/omarchy](https://github.com/omacom/omarchy) (PR #18276), [omarchy-iso](https://github.com/omacom/omarchy-iso)
  (quattro, `acf0d36`), [omarchy-pkgs](https://github.com/omacom/omarchy-pkgs) (#2378, #2379, #2382)
- [Introducing Omarchy Dragon](https://omarchy.org/news/2026/09/introducing-omarchy-dragon/)
- [qBitnaut/omarchy-dragon-sl7](https://github.com/qBitnaut/omarchy-dragon-sl7): Surface Laptop 7 (X1P-64-100)
- Linux `arch/arm64/boot/dts/qcom/x1p64100-microsoft-denali.dts` (Dale Whinham), systemd `src/boot/{stub,chid,devicetree,edid}.c`

## Test sonuçları

2026-11-20, taban `omarchy-2026.11.20-aarch64-edge.iso` (SHA256 `3754d075…26878612`), bu Surface'teki
Docker Desktop'ta:

| Yapı | Sonuç |
|---|---|
| Varsayılan: `omarchy-2026.11.20-aarch64-edge-sp11-lcd.iso`, 9.878.634.496 bayt, SHA256 `b111cc9f…20320c175` | 38 kontrol geçti, hiçbiri başarısız olmadı; bunlardan biri çıktı üzerinde kendi 16 kontrolüyle `verify-edge-iso.sh` |
| `-LcdOnlyUki`: `omarchy-2026.11.20-aarch64-edge-sp11-lcd-fallback.iso`, 9.854.517.248 bayt (oluşturuldu, test edildi, sonra disk alanı için silindi) | 43 kontrol geçti, hiçbiri başarısız olmadı (testin EFI bölümü kontrolü olmayan önceki sürümüyle); yeniden kurulan canlı UKI 225.617.408 bayt |

Belgelerin dayandığı bulgular:

- `microsoft-surface-pro-11-firmware` 20261102-3'ün 11 dosyasının hepsi bu makinenin sürücü
  deposundaki kopyalarla bayt bayt aynı: `qcadsp8380.mbn`, `adsp_dtb.mbn` (`adsp_dtbs.elf`),
  `adspr.jsn`, `adsps.jsn`, `adspua.jsn`, `battmgr.jsn`, `qccdsp8380.mbn`, `cdsp_dtb.mbn`
  (`cdsp_dtbs.elf`), `cdspr.jsn`, `qcvss8380.mbn`, `qcdxkmsuc8380.mbn`.
- Bu makinenin ışık sensörü dosyaları, `surface-pro-11-sensors-extract`'ın doğruladığı özetlere sahip.
- `device-facts.json`'dan hesaplandığında systemd-stub, panelin EDID'i varken CHID EXTRA+2 ile
  `microsoft,denali-lcd`'yi, yokken CHID 3 ile `microsoft,denali-oled`'i seçiyor.
- Kök imajdaki `board-2.bin` (`linux-firmware-atheros` 20261019-1), destek paketinin `board.bin`'inin
  (Qualcomm'un 3378/255 referans kaydı) yanında, bu Wi-Fi kartı için birebir bir
  `subsystem-device=1107`, board-id 255 kaydı taşıyor.

Test edilmeyenler: Surface'in kendisinde hiçbir şey; ISO'dan kurulum; nightly indirmesi (2026-11-20'de
`latest.json` okundu, ISO HEAD isteğine onun verdiği boyutla yanıt verdi ve `.sha256` dosyası aynı
SHA256'yı gösteriyor, ama 8,5 GB'lık ISO indirilmedi); Omarchy'nin `surface-pro-11.sh`'i, okunarak
kontrol ediliyor, çalıştırılmıyor.
