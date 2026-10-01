#!/usr/bin/env bash
# LineageOS for lisa with Xiaomi MiuiCamera, signed with your own keys.
#
# Usage: ./build.sh <step>...
#   init     repo init + install the local manifest (new tree)
#   migrate  switch an existing tree from upstream device trees to the forks
#   sync     repo sync
#   build    breakfast + build target-files
#   sign     sign with $KEYS, produce OTA zip + fastboot images
#   all      sync build sign
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/config.sh"

MANIFEST=lisa_miuicamera.xml
FORK_BRANCH=lineage-23.2-miuicamera
FORKS=(
    "device/xiaomi/lisa ultrapazniy/android_device_xiaomi_lisa"
    "device/xiaomi/sm8350-common ultrapazniy/android_device_xiaomi_sm8350-common"
)
CAM_REPO=vendor/xiaomi/miuicamera-lisa
CAM_APK=$CAM_REPO/vendor/proprietary/system/priv-app/MiuiCamera/MiuiCamera.apk
DT=device/xiaomi/$DEVICE

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

envsetup() {
    cd "$SRC"
    set +eu
    source build/envsetup.sh
    breakfast "$DEVICE" || die "breakfast $DEVICE failed"
    set -eu
}

install_manifest() {
    mkdir -p "$SRC/.repo/local_manifests"
    cp "$HERE/local_manifests/$MANIFEST" "$SRC/.repo/local_manifests/"
    # The manifest already lists every device dependency
    rm -f "$SRC/.repo/local_manifests/roomservice.xml"
}

step_init() {
    log "repo init $BRANCH in $SRC"
    mkdir -p "$SRC" && cd "$SRC"
    [ -d .repo ] || repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs --no-clone-bundle
    install_manifest
}

step_migrate() {
    log "Switching $SRC to the forked device trees"
    cd "$SRC"
    for f in "${FORKS[@]}"; do
        set -- $f; path=$1; name=$2
        [ -d "$path/.git" ] || continue
        [ -z "$(git -C "$path" status --porcelain)" ] || die "$path has uncommitted changes"
        head=$(git -C "$path" rev-parse HEAD)
        remote=$(git ls-remote "https://github.com/$name" "refs/heads/$FORK_BRANCH" | cut -f1)
        [ -n "$remote" ] || die "$name has no branch $FORK_BRANCH on GitHub yet, push it first"
        [ "$head" = "$remote" ] \
            || die "$path HEAD ($head) differs from github.com/$name $FORK_BRANCH ($remote), push it first"
        log "Removing upstream checkout of $path (its commits are on GitHub)"
        rm -rf "$path" ".repo/projects/$path.git"
    done
    # Projects from the old build kit manifest are now part of $MANIFEST
    rm -f .repo/local_manifests/miuicamera.xml
    install_manifest
}

step_sync() {
    log "repo sync"
    cd "$SRC"
    repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags
    ensure_lfs
}

ensure_lfs() {
    cd "$SRC"
    [ -f "$CAM_APK" ] || return 0
    if [ "$(stat -c %s "$CAM_APK")" -lt 1000000 ]; then
        log "MiuiCamera.apk is an LFS pointer, pulling LFS objects"
        git -C "$CAM_REPO" lfs pull
    fi
    [ "$(stat -c %s "$CAM_APK")" -gt 1000000 ] || die "MiuiCamera.apk is still an LFS pointer (git-lfs installed?)"
}

prepare_extras() {
    cd "$SRC"
    # Optional proprietary face detection model; device.mk picks it up if present
    if [ -n "$FACEDETECT_MODEL" ]; then
        [ -f "$FACEDETECT_MODEL" ] || die "FACEDETECT_MODEL=$FACEDETECT_MODEL does not exist"
        mkdir -p vendor/miuicamera-extras
        cmp -s "$FACEDETECT_MODEL" vendor/miuicamera-extras/facedetectpp_0_5_2_model \
            || cp "$FACEDETECT_MODEL" vendor/miuicamera-extras/facedetectpp_0_5_2_model
    fi
}

step_build() {
    cd "$SRC"
    [ -d "$DT" ] || die "$DT missing, run 'init sync' first"
    grep -q miuicamera-lisa "$DT/device.mk" \
        || die "$DT is not the MiuiCamera fork, run './build.sh migrate sync'"
    ensure_lfs
    prepare_extras
    envsetup
    log "Building target-files (this takes many hours the first time)"
    cd "$SRC"
    set +u
    mka -j"$JOBS" target-files-package otatools
    set -u
    TF=$(ls -t "$OUT"/obj/PACKAGING/target_files_intermediates/*-target_files*.zip 2>/dev/null | head -1 || true)
    [ -f "$TF" ] || die "target-files zip not found"
    listing=$(unzip -l "$TF")
    grep -q 'priv-app/MiuiCamera/MiuiCamera.apk' <<<"$listing" || die "MiuiCamera.apk is not in $TF"
    log "Target files: $TF"
}

step_sign() {
    [ -f "$KEYS/platform.pk8" ] || die "no keys in $KEYS, run gen-keys.sh first"
    envsetup
    cd "$SRC"
    TF=$(ls -t "$OUT"/obj/PACKAGING/target_files_intermediates/*-target_files*.zip 2>/dev/null | head -1 || true)
    [ -f "$TF" ] || die "no target-files, run 'build' first"

    args=()
    for a in "${APEX_APKS[@]}"; do args+=(--extra_apks "$a.apk=$KEYS/releasekey"); done
    for a in "${APEXES[@]}";    do args+=(--extra_apks "$a.apex=$KEYS/$a"); done
    for a in "${APEXES[@]}";    do args+=(--extra_apex_payload_key "$a.apex=$KEYS/$a.pem"); done

    mkdir -p "$OUTDIR"
    stamp=$(date +%Y%m%d-%H%M)
    STF="$OUTDIR/signed-target_files-$DEVICE-$stamp.zip"
    OTA="$OUTDIR/lineage-miuicamera-$DEVICE-$stamp.zip"
    IMG="$OUTDIR/images-$DEVICE-$stamp.zip"

    log "Signing"
    sign_target_files_apks -o -d "$KEYS" "${args[@]}" "$TF" "$STF"

    # META/apkcerts.txt keeps the original key names, so compare the real certificate
    tmp=$(mktemp -d)
    unzip -q "$STF" SYSTEM/priv-app/MiuiCamera/MiuiCamera.apk -d "$tmp"
    want=$(openssl x509 -in "$KEYS/platform.x509.pem" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d : | tr A-F a-f)
    got=$(PATH="$SRC/prebuilts/jdk/jdk21/linux-x86/bin:$PATH" apksigner verify --print-certs \
        "$tmp/SYSTEM/priv-app/MiuiCamera/MiuiCamera.apk" | sed -n 's/.*SHA-256 digest: //p' | head -1)
    rm -rf "$tmp"
    [ -n "$got" ] && [ "$got" = "$want" ] \
        || die "MiuiCamera.apk is not signed with your platform key (got '${got:-none}')"
    log "MiuiCamera.apk is signed with your platform key ($want)"

    log "Generating OTA package"
    ota_from_target_files -k "$KEYS/releasekey" --block --backup=true "$STF" "$OTA"

    log "Extracting fastboot images"
    img_from_target_files "$STF" "$IMG"

    log "Done:"
    ls -la "$OTA" "$IMG"
}

[ $# -gt 0 ] || { sed -n '4,10p' "$0"; exit 1; }
for s in "$@"; do
    case "$s" in
        init)    step_init ;;
        migrate) step_migrate ;;
        sync)    step_sync ;;
        build)   step_build ;;
        sign)    step_sign ;;
        all)     step_sync; step_build; step_sign ;;
        *)       die "unknown step: $s" ;;
    esac
done
