#!/usr/bin/env bash
# One-time preparation of an Ubuntu (22.04+/24.04) host or WSL2 for building LineageOS.
set -euo pipefail

sudo apt update
sudo apt install -y \
    bc bison build-essential ccache curl erofs-utils flex g++-multilib gcc-multilib \
    git git-lfs gnupg gperf imagemagick protobuf-compiler python3-protobuf \
    lib32readline-dev lib32z1-dev libdw-dev libelf-dev libgnutls28-dev lz4 \
    libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
    squashfs-tools xsltproc xxd yasm zip unzip zlib1g-dev openssl python-is-python3

mkdir -p "$HOME/bin"
if [ ! -x "$HOME/bin/repo" ]; then
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/bin/repo"
    chmod a+x "$HOME/bin/repo"
fi
grep -q 'HOME/bin' "$HOME/.profile" 2>/dev/null || \
    echo 'if [ -d "$HOME/bin" ]; then PATH="$HOME/bin:$PATH"; fi' >> "$HOME/.profile"

git lfs install
git config --global user.name  >/dev/null || git config --global user.name  "builder"
git config --global user.email >/dev/null || git config --global user.email "builder@localhost"

grep -q USE_CCACHE "$HOME/.bashrc" 2>/dev/null || cat >> "$HOME/.bashrc" <<'EOF'
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
EOF
ccache -M 50G

echo
echo "Done. Re-login (or 'source ~/.profile ~/.bashrc') so that ~/bin/repo is in PATH."
