#!/bin/bash
set -euo pipefail

ROOT="/Users/alperea/ios-apps/fringe-ingredient-decoder"
PROJECT="$ROOT/FringeIngredientDecoder.xcodeproj"
APP_PATH=$(find /Users/alperea/Library/Developer/Xcode/DerivedData -path '*Debug-iphonesimulator/FringeIngredientDecoder.app' -print0 | xargs -0 ls -td | head -n 1)
OUT_DIR="$ROOT/fastlane/screenshots/en-US"

mkdir -p "$OUT_DIR"

if [ -z "$APP_PATH" ]; then
  echo "App build not found. Build first." >&2
  exit 1
fi

capture_for_device() {
  local device_name="$1"
  local device_udid="$2"

  xcrun simctl boot "$device_udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$device_udid" -b >/dev/null
  xcrun simctl status_bar "$device_udid" override \
    --time "9:41" \
    --dataNetwork "wifi" \
    --wifiMode "active" \
    --wifiBars 3 \
    --cellularMode "active" \
    --cellularBars 4 \
    --batteryState "charged" \
    --batteryLevel 100 >/dev/null 2>&1 || true
  xcrun simctl install "$device_udid" "$APP_PATH"

  local scenes=("home" "result" "detail")
  local labels=("01_Home" "02_Result" "03_Detail")

  for i in "${!scenes[@]}"; do
    local scene="${scenes[$i]}"
    local label="${labels[$i]}"
    xcrun simctl terminate "$device_udid" com.pandasoft.fringeingredientdecoder >/dev/null 2>&1 || true
    SIMCTL_CHILD_FID_SCREENSHOT_SCENE="$scene" xcrun simctl launch "$device_udid" com.pandasoft.fringeingredientdecoder >/dev/null
    sleep 4
    xcrun simctl io "$device_udid" screenshot "$OUT_DIR/${device_name}-${label}.png" >/dev/null
  done
}

capture_for_device "iPhone 17 Pro Max" "9A34F069-D84F-4C2F-A1C7-A9252428AE5A"
capture_for_device "iPhone 17 Pro" "636235CF-E098-4484-92A0-38ED5637E40B"

echo "Screenshots saved to $OUT_DIR"
