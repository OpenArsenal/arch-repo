#!/usr/bin/env bash
# scripts/build-all.sh — build PKGBUILDs from a separate repo and publish a pacman repo
# Defaults: CLEAN CHROOT via devtools; outputs to ./docs/$arch; repo label = arch-repo

set -Eeuo pipefail
IFS=$'\n\t'
shopt -s nullglob

# Enable inherit_errexit for bash 4.4+ to handle command substitution properly
if [[ ${BASH_VERSINFO[0]} -ge 4 && ${BASH_VERSINFO[1]} -ge 4 ]]; then
  shopt -s inherit_errexit
fi

# Only trap critical script failures, not individual package build failures
trap 's=$?; echo "✖ Critical script error $s at line $LINENO: $BASH_COMMAND" >&2; exit $s' ERR
trap 'echo "Interrupted"; exit 130' INT TERM

# ---------- Config (override via env) ----------
REPO_NAME="${REPO_NAME:-arch-repo}"                          # pacman repo label
PKG_REPO_URL="${PKG_REPO_URL:-git@github.com:OpenArsenal/Packages.git}"
PKG_REF="${PKG_REF:-main}"                                    # branch/tag/sha
PKG_SUBPATH="${PKG_SUBPATH:-packages/alpm}"                   # path to PKGBUILDs in Packages/
OUT_ROOT="${OUT_ROOT:-docs}"                                  # GitHub Pages root
CHROOT="${CHROOT:-0}"                                         # 1=clean chroot (recommended), 0=host
CHROOT_DIR="${CHROOT_DIR:-/var/lib/archbuild/custom}"         # chroot location (devtools)
MAKEPKG_OPTS=("--syncdeps" "--clean" "--cleanbuild" "--noconfirm")
DB_EXT="${DB_EXT:-zst}"                                       # db compression: zst|xz|gz … (repo-add)
KEYSERVER="${KEYSERVER:-keyserver.ubuntu.com}"                # for optional GPG key import
# Optional: Declare GPG_KEYS array before running script:
#   GPG_KEYS=("ABCDEF123456..." "987654FEDCBA...") ./scripts/build-all.sh

# ---------- Safety & prereqs ----------
[[ $EUID -ne 0 ]] || { echo "Do NOT run as root (makepkg)."; exit 1; }
for c in git repo-add; do command -v "$c" >/dev/null || { echo "Missing $c"; exit 127; }; done
if [[ "$CHROOT" == "1" ]]; then
  for c in makechrootpkg mkarchroot; do command -v "$c" >/dev/null || { echo "Missing $c (pacman -S devtools)"; exit 127; }; done
else
  command -v makepkg >/dev/null || { echo "Missing makepkg (pacman)."; exit 127; }
fi

# Detect arch for output directory
case "$(uname -m)" in x86_64) ARCH=x86_64;; aarch64) ARCH=aarch64;; armv7l) ARCH=armv7h;; armv6l) ARCH=armv6h;; i686) ARCH=i686;; *) echo "Unsupported arch"; exit 2;; esac
OUT_DIR="$OUT_ROOT/$ARCH"; mkdir -p "$OUT_DIR"

# ---------- Clone/refresh Packages ----------
WORK_DIR="${WORK_DIR:-_work}"; SRC_DIR="$WORK_DIR/Packages"
if [[ -d "$SRC_DIR/.git" ]]; then
  echo "Updating existing Packages repo..."
  git -C "$SRC_DIR" fetch --depth=1 origin "$PKG_REF"
  git -C "$SRC_DIR" checkout -f FETCH_HEAD
else
  echo "Cloning Packages repo..."
  mkdir -p "$WORK_DIR"
  git clone --depth=1 --filter=blob:none "$PKG_REPO_URL" "$SRC_DIR"
  git -C "$SRC_DIR" checkout -f "$PKG_REF"
fi
git -C "$SRC_DIR" sparse-checkout init --cone >/dev/null 2>&1 || true
git -C "$SRC_DIR" sparse-checkout set "$PKG_SUBPATH" >/dev/null 2>&1 || true

# Optional: import GPG keys for PKGBUILDs with validpgpkeys
# Check if GPG_KEYS array is set and has elements
if [[ -v GPG_KEYS && ${#GPG_KEYS[@]} -gt 0 ]]; then
  if command -v gpg >/dev/null; then
    echo "Importing GPG keys..."
    for k in "${GPG_KEYS[@]}"; do 
      echo "  Importing key: $k"
      gpg --keyserver "$KEYSERVER" --recv-keys "$k" || echo "  ⚠ Failed to import $k (continuing...)"
    done
  else
    echo "⚠ gpg not found, skipping key import"
  fi
fi

# ---------- Build all packages ----------
# Set PKGDEST safely (avoid command substitution in assignment)
if ! cd "$OUT_DIR"; then
  echo "✖ Failed to access output directory: $OUT_DIR" >&2
  exit 1
fi
export PKGDEST="$PWD"
cd - >/dev/null

# Count packages for progress tracking (avoid command substitution masking errors)
PKGBUILD_FILES=()
while IFS= read -r -d '' file; do
  PKGBUILD_FILES+=("$file")
done < <(find "$SRC_DIR/$PKG_SUBPATH" -name PKGBUILD -print0)

TOTAL_PKGS=${#PKGBUILD_FILES[@]}
echo "Found $TOTAL_PKGS packages to build"
[[ $TOTAL_PKGS -gt 0 ]] || { echo "No PKGBUILDs found in $SRC_DIR/$PKG_SUBPATH"; exit 1; }

# Initialize counters (important for arithmetic operations with set -e)
BUILT=0; FAILED=0; CURRENT=0

for pkgdir in "$SRC_DIR/$PKG_SUBPATH"/*; do
  [[ -f "$pkgdir/PKGBUILD" ]] || continue
  
  # Use pre-increment to avoid set -e issues when CURRENT=0
  ((++CURRENT))
  PKGNAME="$(basename "$pkgdir")"
  echo "[$CURRENT/$TOTAL_PKGS] Building $PKGNAME..."
  
  # Build in a subshell so failures don't kill the main script
  if (
    set -e  # Fail fast within this subshell only
    if [[ "$CHROOT" == "1" ]]; then
      sudo mkdir -p "$CHROOT_DIR/root"
      # Ensure base-devel in chroot root (first run)
      sudo mkarchroot "$CHROOT_DIR/root" base-devel >/dev/null 2>&1 || true
      cd "$pkgdir" && sudo env PKGDEST="$PKGDEST" makechrootpkg -r "$CHROOT_DIR" -c -u -- "${MAKEPKG_OPTS[@]}"
    else
      cd "$pkgdir" && makepkg "${MAKEPKG_OPTS[@]}"
    fi
  ); then
    echo "  ✅ Built $PKGNAME"
    ((++BUILT))
  else
    echo "  ✖ Failed to build $PKGNAME (continuing with other packages...)"
    ((++FAILED))
  fi
done

# ---------- Create/refresh repo DB ----------
echo "Creating repository database..."
cd "$OUT_DIR"
pkgs=( ./*.pkg.tar.* )

if (( ${#pkgs[@]} == 0 )); then
  echo "⚠ No packages were successfully built"
  exit 0
fi

echo "Adding ${#pkgs[@]} packages to repository..."
repo-add -R "${REPO_NAME}.db.tar.${DB_EXT}" "${pkgs[@]}"    # -R prunes old entries

# ---------- Summary ----------
echo
echo "🎉 Build Summary:"
echo "  Built: $BUILT packages"
echo "  Failed: $FAILED packages" 
echo "  Total packages in repo: ${#pkgs[@]}"
echo
echo "Repository ready at: $OUT_DIR"
echo
echo "Add to pacman.conf:"
echo "[$REPO_NAME]"
# Safely get git root without nested command substitution
REPO_ROOT="."
if GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  REPO_ROOT="${GIT_ROOT##*/}"  # basename equivalent using parameter expansion
fi
echo "Server = https://openarsenal.github.io/$REPO_ROOT/\$arch"