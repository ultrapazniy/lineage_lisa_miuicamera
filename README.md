# LineageOS 23.2 for lisa with Xiaomi MiuiCamera

Build kit for **LineageOS 23.2 (Android 16)** on the **Xiaomi 11 Lite 5G NE (lisa)** with the
Xiaomi stock camera (MiuiCamera) integrated into the system, the same way PixelOS ships it.

The build is signed with **your own release keys**. MiuiCamera is signed with your platform key,
so it gets the same privileges as on PixelOS: `signature` permissions and the `platform_app`
SELinux domain. This is something a Magisk module cannot provide.

## How it works

Only two LineageOS repositories are modified. They are forked, and a local manifest swaps them in
during `repo sync`:

| Repository | Branch | Change |
|---|---|---|
| [ultrapazniy/android_device_xiaomi_lisa](https://github.com/ultrapazniy/android_device_xiaomi_lisa) | `lineage-23.2-miuicamera` | Inherit `vendor/xiaomi/miuicamera-lisa` |
| [ultrapazniy/android_device_xiaomi_sm8350-common](https://github.com/ultrapazniy/android_device_xiaomi_sm8350-common) | `lineage-23.2-miuicamera` | Drop the stub `camera_cnf.txt`; the camera package installs the real SenseTime license there |

Everything else comes from upstream:

- **LineageOS** — kernel, `hardware/xiaomi` and the rest of the tree.
- **[TheMuppets](https://github.com/TheMuppets)** — proprietary vendor blobs.
- **[xiaomi-lisa-resources/proprietary_vendor_xiaomi_miuicamera-lisa](https://github.com/xiaomi-lisa-resources/proprietary_vendor_xiaomi_miuicamera-lisa)** —
  the camera package: APK, JNI libraries, `libgui` shim, sepolicy and props.

| File | Purpose |
|---|---|
| `local_manifests/lisa_miuicamera.xml` | Forks plus all device dependencies |
| `build.sh` | `init` / `migrate` / `sync` / `build` / `sign` / `all` |
| `gen-keys.sh` | One-time generation of release and APEX signing keys |
| `setup-host.sh` | Build dependencies, `repo` and ccache for Ubuntu / WSL2 |
| `config.sh` | Paths, job count, optional extras, APEX key lists |

## Requirements

- Ubuntu 22.04/24.04, native or WSL2. The source tree must live on a Linux filesystem, not `/mnt/*`.
- About 400 GB of free disk space.
- 16 GB of RAM plus **64 GB of swap**. Soong analysis alone peaks at about 50 GB on Android 16.
- Many hours for the first build: about 27 h on an i7-6700HQ with an external HDD.

On WSL2, put this in `%UserProfile%\.wslconfig`:

```ini
[wsl2]
memory=16GB
processors=6
swap=64GB
```

## Building

```bash
git clone https://github.com/ultrapazniy/lineage_lisa_miuicamera ~/lineage_lisa_miuicamera
cd ~/lineage_lisa_miuicamera
bash setup-host.sh          # once, then re-login
bash build.sh init sync     # ~150 GB download
bash gen-keys.sh            # once; back up ~/.android-certs somewhere safe and private
bash build.sh build sign
```

The output lands in `~/android/release/`:

- `lineage-miuicamera-lisa-*.zip` is the package for `adb sideload`.
- `images-lisa-*.zip` holds the fastboot images (`boot`, `dtbo`, `vendor_boot`, ...).

To update later: `bash build.sh all`.

### Existing LineageOS tree

If you already have a LineageOS 23.2 tree with upstream device trees, run:

```bash
bash build.sh migrate sync
```

`migrate` removes the upstream checkouts of the two device trees and installs the manifest.
It refuses to touch a tree that has uncommitted changes or commits not pushed to the fork.

### Optional: face detection model

PixelOS also ships `/vendor/etc/camera/facedetectpp_0_5_2_model`. The file is proprietary, so it
is not in any of these repositories. If you have it, for example extracted from a PixelOS `vendor`
image, point the build at it:

```bash
FACEDETECT_MODEL=/path/to/facedetectpp_0_5_2_model bash build.sh build sign
```

## Installing

The build is signed with your keys, so recovery from another build will reject it. Flash the
recovery from the same build first. On lisa, recovery lives in `boot`. Extract the images:

```bash
adb reboot bootloader
fastboot flash dtbo dtbo.img
fastboot flash vendor_boot vendor_boot.img
fastboot flash boot boot.img
fastboot reboot recovery
```

In recovery, run **Factory reset → Format data**. Coming from another build requires a wipe
because the keys are different. Then use **Apply update → Apply from ADB**:

```bash
adb sideload lineage-miuicamera-lisa-XXXXXXXX-XXXX.zip
```

For Magisk, patch `boot.img` from the same build. A MiuiCamera Magisk module is not needed.

## Keeping the forks up to date

After upstream updates, typically monthly security patches, rebase both forks:

```bash
cd ~/android/lineage/device/xiaomi/lisa     # and device/xiaomi/sm8350-common
git fetch https://github.com/LineageOS/android_device_xiaomi_lisa lineage-23.2
git rebase FETCH_HEAD
git push -f https://github.com/ultrapazniy/android_device_xiaomi_lisa HEAD:lineage-23.2-miuicamera
```

## Security

- **Never publish `~/.android-certs`.** Anyone holding these keys can sign an "update" that
  devices running your builds will accept as a system update. `.gitignore` blocks key files, but
  check before every push.
- Builds published from these keys are trusted only as much as you protect the keys.

## Credits

- [LineageOS](https://lineageos.org) and the lisa maintainers
- [xiaomi-lisa-resources](https://github.com/xiaomi-lisa-resources) for the MiuiCamera package
- [PixelOS](https://pixelos.net), whose lisa builds this integration mirrors
- [TheMuppets](https://github.com/TheMuppets) for the vendor blobs

MiuiCamera and the vendor blobs are proprietary Xiaomi software and are not part of this repository.
