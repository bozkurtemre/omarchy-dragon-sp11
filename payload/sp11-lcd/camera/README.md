# Cameras for V4L2 apps

Both cameras of the Surface Pro 11 (front `imx681`, back `ov13858`) work through libcamera's
software ISP and PipeWire only. Chrome and other PipeWire camera apps see them as "Built-in Front
Camera" and "Built-in Back Camera". V4L2 has only the raw CAMSS nodes ("Qualcomm Camera
Subsystem"), so apps that open cameras through V4L2 find nothing usable:

- **Monologue**: Qt's FFmpeg backend finds cameras through V4L2 only.
- **Omarchy's screen recording webcam overlay** (`omarchy-capture-screenrecording --with-webcam`): `ffplay -f v4l2`.

[omarchy-pkgs #3105](https://github.com/omacom/omarchy-pkgs/issues/3105) tracks this upstream.
`setup-camera.sh` sets up what that issue describes: each camera is relayed from PipeWire into a
v4l2loopback device, and only while an app has the device open.

| Device | Name | Camera | PipeWire node |
|---|---|---|---|
| `/dev/video40` | Surface Front Camera | `imx681` | `libcamera_input._base_soc_0_cci_ac16000_i2c-bus_1_camera_1a` |
| `/dev/video41` | Surface Back Camera | `ov13858` | `libcamera_input._base_soc_0_cci_ac15000_i2c-bus_1_camera_10` |

The module options also create `/dev/video42` for the IR camera, which
[../ir-camera/](../ir-camera/README.md) feeds.

This is opt-in. Unlike the rest of this repository, it builds one package that is not Omarchy's:
`v4l2-relayd-sp11`, the AUR's `v4l2-relayd` 0.2.0 with one patch. Everything else comes from
Omarchy's repositories.

## Setup

Run on the installed system, with network access:

```bash
sudo bash /mnt/sp11-lcd/camera/setup-camera.sh    # from the USB stick, mounted as in ../README.md
# or, from a checkout of this repository:
sudo bash payload/sp11-lcd/camera/setup-camera.sh
```

It installs `v4l2loopback-dkms`, `gst-plugins-good`, `gst-plugin-pipewire` and `base-devel` with
pacman, then builds `v4l2-relayd-sp11` as your user with `makepkg` and installs it (it replaces
an unpatched `v4l2-relayd` if one is installed). Then it installs:

| File | Installed as |
|---|---|
| `v4l2loopback.conf` | `/etc/modprobe.d/surface-pro-11-cameras.conf` (with `v4l2loopback` in `/etc/modules-load.d/surface-pro-11-cameras.conf`) |
| `surface-camera@.service` | `/etc/systemd/user/surface-camera@.service`, enabled for every user as `surface-camera@front` and `surface-camera@back` |
| `front.conf`, `back.conf` | `/etc/surface-pro-11-cameras/` |
| `wireplumber-hide-loopback.conf` | `/etc/wireplumber/wireplumber.conf.d/surface-pro-11-cameras.conf` |

It then loads the module, restarts WirePlumber (audio drops for a moment) and starts both relays
in your session. You can rerun it. DKMS rebuilds the module after kernel updates.

In V4L2 apps, pick **Surface Front Camera** or **Surface Back Camera**. Omarchy's webcam picker
still lists the raw `/dev/video2 Qualcomm Camera Subsystem` too, and that entry does not work.

Check:

```bash
systemctl --user status surface-camera@front surface-camera@back
ffmpeg -f v4l2 -i /dev/video40 -frames:v 90 -f null -    # about 3 s for 90 frames
```

## How it works

`v4l2-relayd` keeps a v4l2loopback device fed with a black splash frame. A V4L2 app opening the
device raises v4l2loopback's client count. The relay then starts its input pipeline
(`pipewiresrc` on the camera's libcamera node) and stops it again when the last app closes the
device. PipeWire stays the only libcamera client; the relay is one more PipeWire stream. Output
is YUY2 1280x720 at 30 fps.

Running the relay as it ships failed in three ways. The unit and the patch fix them:

| Problem | Fix |
|---|---|
| `v4l2-relayd` sets the output pipeline's base time to "now", so frames reach the device with running time (seconds since the relay started) instead of `CLOCK_MONOTONIC`. ffmpeg turns those into large negative timestamps, and the first app after a relay start received no frames | `v4l2-relayd-sp11/monotonic-timestamps.patch`: base time 0 |
| libcamera buffers carry sensor timestamps, so `v4l2sink` dropped almost every frame as late | `pipewiresrc do-timestamp=true`, `v4l2sink sync=false` |
| Each open started with a burst of stale duplicate frames, and the relay's memory grew (1.1 GB seen) while nobody was reading | `videorate skip-to-first=true`; `appsrc max-buffers=2 leaky-type=downstream` |

The WirePlumber rule hides the loopbacks from PipeWire. Without it, PipeWire apps list each
camera twice, and WirePlumber's own probing opens the devices and wakes the relays.

## Picture

The picture is libcamera's simple IPA with `uncalibrated.yaml`. No colour matrix is applied and
the sensors have no helper, so the image is dim and slightly green. The front camera's exposure
takes 4 to 5 seconds to settle. #3105 has a colour matrix taken from the Windows camera tuning
(`surfacecamfrontsensor_extension8380`, in this stick's `windows/` archive) and a longer exposure
for the `imx681`. Neither is applied here.

## Tested

2026-11-23, on this Surface Pro 11 LCD: `linux-omarchy` 7.3 (7.3.0-77), libcamera 0.7.2,
PipeWire 1.6.11, `v4l2loopback-dkms` 0.15.4, `gst-plugins-good` 1.28.9.

- `setup-camera.sh` built and installed `v4l2-relayd-sp11` 0.2.0-1 in place of an unpatched
  `v4l2-relayd`, loaded the module and started both relays. A second run skipped the build and
  changed nothing.
- Right after a relay restart, and on every later open: `ffmpeg -f v4l2` got 90 frames in about
  3.4 s from each device, with a real picture.
- When the last reader closes, both libcamera nodes go back to `suspended`.
- `wpctl status` lists only the two libcamera cameras.
- `omarchy-capture-webcam-list` lists `/dev/video40` and `/dev/video41`.
- Not tried: Monologue and the overlay on screen (both open the device through V4L2 the way ffmpeg
  does).

## Removing it

```bash
sudo systemctl --global disable surface-camera@front.service surface-camera@back.service
sudo rm -r /etc/systemd/user/surface-camera@.service /etc/surface-pro-11-cameras \
  /etc/modprobe.d/surface-pro-11-cameras.conf /etc/modules-load.d/surface-pro-11-cameras.conf \
  /etc/wireplumber/wireplumber.conf.d/surface-pro-11-cameras.conf
sudo pacman -Rns v4l2-relayd-sp11 v4l2loopback-dkms
```
