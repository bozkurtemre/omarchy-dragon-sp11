# The IR camera as a V4L2 device

The Surface Pro 11 has an IR (Windows Hello) camera: an ST `vd55g0` mono sensor on the camera
subsystem, and an IR flood light, the LED class device `ir:flash` on the PMIC. libcamera finds the
sensor (`cam -l` lists it as `'vd55g0'`). The Surface package hides it from PipeWire, and face
unlock tools such as [omaFace](https://github.com/L0adn9/omaface) or Howdy look for a plain V4L2
camera giving `GREY` frames, so nothing uses it.

`setup-ir-camera.sh` makes it `/dev/video42` "Surface IR Camera", `GREY` 644x604 (the sensor's
full frame). The IR light is on only while something streams the device.

| Part | What it does |
|---|---|
| `surface-ir-camera.service` (system) | `v4l2-relayd-sp11` with `libcamerasrc` on the sensor, into the third v4l2loopback device. The sensor streams only while a reader streams `/dev/video42`; otherwise a black frame is held |
| `surface-ir-emitter` / `.service` (system) | Watches the device's v4l2loopback client-usage event. While a reader streams, it sets `ir:flash` to 40 of 255 and lowers the sensor's auto-exposure target to -2 EV (`auto_exposure_bias` 2); both go back when the reader stops, and the light goes off when it exits |
| `../camera/v4l2loopback.conf` | Three loopback devices: 40 front, 41 back, 42 IR |

Both are system services, not user ones: face unlock also scans at the login screen, before any
user session. The light and the sensor's controls are root-only.

## Setup

Run `../camera/setup-camera.sh` first. It installs `v4l2loopback-dkms` and `v4l2-relayd-sp11`. Then:

```bash
sudo bash /mnt/sp11-lcd/ir-camera/setup-ir-camera.sh
```

It installs `gst-plugin-libcamera`, reloads v4l2loopback if `/dev/video42` is missing (the front
and back relays stop for a moment), installs the watcher to `/usr/local/lib/surface-pro-11-ir/`
and both units to `/etc/systemd/system/`, and enables them. You can rerun it.

Check: `ffmpeg -f v4l2 -i /dev/video42 -frames:v 90 -f null -`. The light comes on while it runs.

## Why these settings

Measured in a dark room, sitting in front of the screen:

| Setting | Result |
|---|---|
| Light off | Black frame (mean 16 of 255, the sensor's pedestal) |
| Light at 16, 40, 80 or 255, sensor auto-exposure at 0 EV | The sensor exposes for the dark room; the face is pure white |
| Manual exposure (`auto_exposure=1`) | Black under libcamera at every value tried |
| Light at 40, auto-exposure bias -1 / -2 / -3 EV | -2 EV: face well exposed, 0.06% of pixels saturated |

The bias is set after the stream starts. libcamera configures the sensor when the relay's
pipeline starts, so the watcher sets it twice, 0.4 s and 1.2 s after the reader's stream begins.

## With omaFace

`omaface-engine cameras` (from the omaFace source, built here) lists:

```
/dev/video40  Surface Front Camera  YUYV  colour camera, not used
/dev/video41  Surface Back Camera   YUYV  colour camera, not used
/dev/video42  Surface IR Camera     GREY  used by omaFace
```

`omaface-engine probe` picks `/dev/video42` as `ir`, and `omaface-engine emitter` reports
`steady` (the light is on for every frame, not every other one), which omaFace counts as "IR light
comes on". omaFace's face detector (YuNet) found the face in a relayed frame with score 0.92.

Then install omaFace itself as its README says (`./install.sh` from its source). Its setup adds a
`sufficient` line to PAM for sudo, polkit, the login screen and the lock screen; the password
keeps working everywhere.

## Tested

2026-11-23, on this Surface Pro 11 LCD (7.3.0-78, libcamera 0.7.2):

- `/dev/video42` lists `GREY` 644x604. ffmpeg reads frames through it; the light reads 40 while
  ffmpeg streams and 0 before and after, and the bias goes from 6 to 2 and back.
- The front and back relays still work with the third device.
- `setup-ir-camera.sh` on the machine where this was set up by hand changed nothing and left the
  installed files byte-identical to these.
- Not tested: enrolling and unlocking with omaFace, daylight (sunlight is bright in infrared),
  the light level at other distances.

## Removing it

```bash
sudo systemctl disable --now surface-ir-camera.service surface-ir-emitter.service
sudo rm /etc/systemd/system/surface-ir-{camera,emitter}.service
sudo rm -r /usr/local/lib/surface-pro-11-ir
```

The third loopback device stays until `../camera/v4l2loopback.conf` changes.
