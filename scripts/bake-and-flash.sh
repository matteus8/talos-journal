#!/usr/bin/env bash
# ==============================================================================
# Talos Edge Node Flasher & Staging Script (macOS)
# ==============================================================================
# Decrypts machine configs in-memory with SOPS/age and writes bootable
# Talos images directly to an external USB stick or MicroSD card using dd.
# ==============================================================================

set -euo pipefail

TALOS_VERSION="v1.14.5"
CACHE_DIR=".cache/images"
CONFIGS_DIR="configs"
KEY_FILE="age.key"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*"; }

# ------------------------------------------------------------------------------
# 1. Prerequisite Checks
# ------------------------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  log_err "This script is designed for macOS (Darwin). For Linux, adjust disk utilities."
  exit 1
fi

for cmd in sops age talosctl curl zstd diskutil dd; do
  if ! command -v "$cmd" &>/dev/null; then
    log_err "Missing required dependency: $cmd. Please install via Homebrew (brew install $cmd)."
    exit 1
  fi
done

if [[ ! -f "$KEY_FILE" ]]; then
  log_err "Missing private decryption key: $KEY_FILE. Cannot decrypt cluster configs."
  exit 1
fi
export SOPS_AGE_KEY_FILE="./$KEY_FILE"

# ------------------------------------------------------------------------------
# 2. Parse Target Node Argument
# ------------------------------------------------------------------------------
NODE_TYPE="${1:-}"
if [[ "$NODE_TYPE" != "pi5" && "$NODE_TYPE" != "surface3" ]]; then
  echo -e "\nUsage: $0 <pi5 | surface3>"
  echo "  pi5      : Flash Raspberry Pi 5 Control Plane (ARM64, target 192.168.1.100)"
  echo "  surface3 : Flash Surface 3 Worker Node (x86_64, target 192.168.1.106, TPM 2.0)"
  echo ""
  exit 1
fi

mkdir -p "$CACHE_DIR"

if [[ "$NODE_TYPE" == "pi5" ]]; then
  CONFIG_FILE="$CONFIGS_DIR/controlplane.enc.yaml"
  IMAGE_NAME="pi5-sbc-arm64-${TALOS_VERSION}.raw.xz"
  IMAGE_URL="https://factory.talos.dev/image/ee21ef4a5ef808a9b7484cc0dda0f25075021691c8c09a276591eedb638ea1f9/${TALOS_VERSION}/metal-arm64.raw.xz"
  TARGET_ARCH="ARM64"
  TARGET_ROLE="Control Plane (Master)"
  TARGET_IP="192.168.1.100"
else
  CONFIG_FILE="$CONFIGS_DIR/worker.enc.yaml"
  IMAGE_NAME="surface3-metal-amd64-${TALOS_VERSION}.raw.zst"
  IMAGE_URL="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-amd64.raw.zst"
  TARGET_ARCH="x86_64"
  TARGET_ROLE="Worker Node (TPM 2.0 Enabled)"
  TARGET_IP="192.168.1.106"
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  log_err "Encrypted config file not found: $CONFIG_FILE"
  exit 1
fi

# ------------------------------------------------------------------------------
# 3. Detect External USB / MicroSD Drive
# ------------------------------------------------------------------------------
log_info "Scanning for external USB / MicroSD drives..."
EXTERNAL_DISKS=$(diskutil list external physical 2>/dev/null || true)

if [[ -z "$EXTERNAL_DISKS" || "$EXTERNAL_DISKS" == *"No such"* ]]; then
  log_err "No external USB stick or MicroSD card detected!"
  log_warn "Please plug in your USB drive or MicroSD card and re-run this script."
  exit 1
fi

echo -e "\n${YELLOW}=== Detected External Storage ===${NC}"
echo "$EXTERNAL_DISKS"
echo "=================================="

# Extract candidate disk identifiers (e.g. disk4)
CANDIDATES=($(diskutil list external physical | grep -E '^/dev/disk[0-9]+' | awk '{print $1}'))

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  log_err "Could not parse external disk identifiers. Aborting for safety."
  exit 1
fi

DEFAULT_DISK="${CANDIDATES[0]}"
echo -e "\nTarget device for ${GREEN}$NODE_TYPE ($TARGET_ROLE)${NC}:"
read -rp "Enter target disk device [Default: $DEFAULT_DISK]: " SELECTED_DISK
TARGET_DISK="${SELECTED_DISK:-$DEFAULT_DISK}"

# Safety sanity checks
if [[ "$TARGET_DISK" == "/dev/disk0" || "$TARGET_DISK" == "/dev/disk1" ]]; then
  log_err "DANGER: You selected an internal system drive ($TARGET_DISK). Aborting immediately!"
  exit 1
fi

if ! diskutil info "$TARGET_DISK" &>/dev/null; then
  log_err "Invalid disk device: $TARGET_DISK"
  exit 1
fi

RAW_DISK="${TARGET_DISK/disk/rdisk}" # Use unbuffered /dev/rdisk for 10x faster dd writes

# ------------------------------------------------------------------------------
# 4. In-Memory Config Decryption & Validation
# ------------------------------------------------------------------------------
log_info "Decrypting $CONFIG_FILE in-memory with local age.key..."
DECRYPTED_CONFIG=$(sops -d "$CONFIG_FILE")

log_info "Validating configuration with talosctl..."
echo "$DECRYPTED_CONFIG" | talosctl validate --mode metal -c /dev/stdin
log_ok "Configuration is valid for metal mode!"

# ------------------------------------------------------------------------------
# 5. Fetch / Build Talos Image
# ------------------------------------------------------------------------------
if [[ "$NODE_TYPE" == "pi5" ]]; then
  RAW_IMAGE="$CACHE_DIR/pi5-prebaked.raw"
  if [[ ! -f "$RAW_IMAGE" ]]; then
    log_info "Building DoD-standard pre-baked Pi 5 image with local imager container..."
    TMP_CONFIG=$(mktemp)
    echo "$DECRYPTED_CONFIG" > "$TMP_CONFIG"
    docker run --rm \
      -v "$TMP_CONFIG:/workspace/controlplane.yaml" \
      -v "$(pwd)/$CACHE_DIR:/out" \
      ghcr.io/siderolabs/imager:${TALOS_VERSION} rpi_generic \
      --arch arm64 \
      --overlay-image ghcr.io/siderolabs/sbc-raspberrypi:v0.1.0 \
      --overlay-name rpi_generic \
      --embedded-config-path /workspace/controlplane.yaml
    rm -f "$TMP_CONFIG"
    xz -dc "$CACHE_DIR/metal-arm64.raw.xz" > "$RAW_IMAGE"
    rm -f "$CACHE_DIR/metal-arm64.raw.xz"
    log_ok "Pre-baked Pi 5 SSD image ready: $RAW_IMAGE"
  else
    log_ok "Using pre-baked Pi 5 image: $RAW_IMAGE"
  fi
else
  CACHED_IMAGE="$CACHE_DIR/$IMAGE_NAME"
  RAW_IMAGE="$CACHE_DIR/${NODE_TYPE}.raw"

  if [[ ! -f "$CACHED_IMAGE" ]]; then
    log_info "Downloading Talos $TALOS_VERSION $TARGET_ARCH base image..."
    curl -L --progress-bar -o "$CACHED_IMAGE" "$IMAGE_URL"
    log_ok "Image cached at $CACHED_IMAGE"
  else
    log_ok "Using cached base image: $CACHED_IMAGE"
  fi

  if [[ ! -f "$RAW_IMAGE" ]]; then
    log_info "Decompressing image to SSD cache ($RAW_IMAGE) for maximum write speed..."
    if [[ "$CACHED_IMAGE" == *.zst ]]; then
      zstd -d -f "$CACHED_IMAGE" -o "$RAW_IMAGE"
    else
      xz -dc "$CACHED_IMAGE" > "$RAW_IMAGE"
    fi
    log_ok "Decompressed SSD image ready: $RAW_IMAGE"
  else
    log_ok "Using pre-decompressed SSD image: $RAW_IMAGE"
  fi
fi

# ------------------------------------------------------------------------------
# 6. Final Confirmation before Destructive Write
# ------------------------------------------------------------------------------
echo -e "\n${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
echo -e "${RED}WARNING: ALL DATA ON $TARGET_DISK WILL BE PERMANENTLY ERASED!${NC}"
echo -e "${YELLOW}  Node Type   : $NODE_TYPE ($TARGET_ROLE)"
echo -e "  Static IP   : $TARGET_IP"
echo -e "  Destination : $TARGET_DISK ($RAW_DISK)${NC}"
echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
read -rp "Are you absolutely sure you want to write to $TARGET_DISK? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  log_warn "Operation cancelled by user. Nothing was written."
  exit 0
fi

# ------------------------------------------------------------------------------
# 7. Unmount & Stream to Disk via dd
# ------------------------------------------------------------------------------
log_info "Unmounting $TARGET_DISK..."
diskutil unmountDisk "$TARGET_DISK"

log_info "Streaming from SSD cache directly to $RAW_DISK via dd (caffeinated)..."
caffeinate -i sudo dd if="$RAW_IMAGE" of="$RAW_DISK" bs=4m status=progress
sync

log_ok "Raw image successfully written to $RAW_DISK!"

# ------------------------------------------------------------------------------
# 8. Post-Flash Guidance
# ------------------------------------------------------------------------------
if [[ "$NODE_TYPE" == "pi5" ]]; then
  log_info "Pi 5 MicroSD is flashed with pre-baked configuration!"
  log_info "Node will boot directly to $TARGET_IP with static IP and cluster CA active (Zero --insecure needed)."
  log_info "Once powered on and connected via Ethernet, bootstrap the cluster with:"
  echo -e "  ${GREEN}talosctl bootstrap -n $TARGET_IP --talosconfig configs/talosconfig${NC}"
else
  log_info "Surface 3 USB installer is flashed!"
  log_info "Insert into Surface 3, hold Volume Down, press Power to boot from USB."
  log_info "Remember: disable Secure Boot in Surface UEFI (Volume Up + Power)."
fi

log_info "Ejecting $TARGET_DISK safely..."
diskutil eject "$TARGET_DISK" || true
log_ok "Done! Safe to unplug media."
