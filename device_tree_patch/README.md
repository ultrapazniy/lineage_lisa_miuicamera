# Device tree change: MIUI auto-brightness curve

Copy `config.xml` into the fork `ultrapazniy/android_device_xiaomi_sm8350-common`
(branch `lineage-23.2-miuicamera`) at:

    rro_overlays/FrameworkOverlaySM8350/res/values/config.xml

(this file is already **merged** with all the existing keys from the fork —
drop-in replacement), then commit. The values are extracted verbatim from
the stock HyperOS OS2.0.8.0.UKOMIXM `product/overlay/AospFrameworkResOverlay.apk`.

Files involved in the analysis (all under D:\XIAOMI_FLASH\stock_os2):
- out_vendor/etc/sensors/config/  — stock sensor HAL configs; **byte-identical**
  to TheMuppets lineage-23.2 blobs, so the light sensor stack is not the culprit.
- apks/aosp_overlay.txt           — aapt2 dump of the stock brightness arrays.
- rro_src/                        — source of the RRO APK in the Magisk module.

## Aux camera hiding (crash on camera IDs 5/6)

HyperOS hides the virtual cameras (IDs 5, 6) from every app except a
package whitelist (`camera_aux_package_list` / `camera.aux.packagelist`).
LineageOS already has the filter hook (`Camera.shouldExposeAuxCamera()`,
driven by `vendor.camera.aux.packagelist`) but lisa does not set the prop,
so every app sees all 7 cameras and some crash opening the virtual ones.

Two changes:
1. `patches/frameworks_base/0001-...patch` (applied automatically by
   `build.sh build` via `git am`): instead of the stock Qualcomm
   "truncate after 2 cameras" behaviour it skips only the IDs listed in
   `vendor.camera.aux.hiddenids` (default `5,6`), so real cameras stay
   visible to everyone.
2. In the `sm8350-common` fork add to `vendor.prop`:

       vendor.camera.aux.packagelist=com.android.camera

   (the MiuiCamera package name; add more comma-separated packages if
   needed). Without this property nothing is hidden.
