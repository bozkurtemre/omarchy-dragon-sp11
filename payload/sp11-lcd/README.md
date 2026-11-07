# sp11-lcd: Surface Pro 11 LCD (Snapdragon X Plus) kurulum sonrası düzeltme

Bu klasör USB'nin kökünde (`/sp11-lcd`) durur. Omarchy kurulumu bittikten sonra,
**yeniden başlatmadan önce** bir kez çalıştırılır.

1. Kurulum programı "bitti" ekranını gösterince yeniden başlatma.
2. `Ctrl+Alt+F2` → giriş: `root` (parola yok).
3. Çalıştır:

   ```
   bash /run/archiso/bootmnt/sp11-lcd/finish-install.sh
   ```

4. Disk şifreleme parolasını sor(ar)sa gir. Sonunda `It is safe to reboot.` yazmalı.
5. `reboot` yaz, ekran kararınca USB'yi çıkar.

Zaten yeniden başlattıysan ve kurulu sistem açıldıysa, USB'yi takıp onun içinden:

```
sudo bash <usb>/sp11-lcd/apply.sh <usb>/sp11-lcd
```

## Ne yapar

- UKI'de LCD device tree'sini (`x1p64100-microsoft-denali.dtb`) sabitler ve her
  çekirdek/UKI yenilemesinde sabit tutar (`/etc/boot/hooks/pre.d/90-sp11-lcd-devicetree`).
  Aksi halde systemd-stub her Surface Pro 11'e OLED tree'sini yükler.
- Panel, ekran ve Surface klavye sürücülerini initramfs'e ekler
  (`/etc/mkinitcpio.conf.d/zz-sp11-lcd.conf`); disk kilidi ekranı görünür ve klavye çalışır.
- Bu cihazın Windows sürücü deposundan alınmış imzalı ADSP/CDSP/GPU firmware'ini
  Omarchy'nin `qcom-firmware-extract` aracıyla kurar, eksik kalmazsa DSP sürücüsünü açar.
- Boot imajını yeniden üretir ve açılacak UKI'nin gerçekten LCD tree'siyle açılacağını doğrular.

Betikler `/usr/local/lib/sp11-lcd/` altına kopyalanır; istediğinde
`sudo /usr/local/lib/sp11-lcd/apply.sh /usr/local/lib/sp11-lcd` ile (firmware hariç) tekrar çalıştırılabilir.
