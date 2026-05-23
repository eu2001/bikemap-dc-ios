#!/bin/bash
# Drops screenshots from Desktop into screenshots/ios/, names them 02..07
# in mtime order (oldest first), then runs the App Store frame generator.
set -e

SRC="$HOME/Desktop"
DST="/Users/ericsousa/Desktop/BikeMapDC/screenshots/ios"
mkdir -p "$DST"

# Find PNGs on Desktop with iPhone-screenshot dimensions, sorted by mtime
mapfile -t SHOTS < <(find "$SRC" -maxdepth 1 -type f -name "*.png" -newer "$DST/01-welcome.png" -print0 2>/dev/null \
  | xargs -0 ls -tr 2>/dev/null)

if [ ${#SHOTS[@]} -eq 0 ]; then
  echo "No new PNGs found on Desktop after 01-welcome.png."
  echo "Drag the 6 remaining screenshots from chat onto your Desktop, then re-run."
  exit 1
fi

NAMES=("02-map-poi-detail.png" "03-layers-infra.png" "04-layers-pois.png" \
       "05-add-point.png" "06-report-theft.png" "07-edit-profile.png")

i=0
for shot in "${SHOTS[@]}"; do
  if [ $i -ge ${#NAMES[@]} ]; then break; fi
  cp "$shot" "$DST/${NAMES[$i]}"
  echo "  ${NAMES[$i]} <- $(basename "$shot")"
  i=$((i+1))
done

echo ""
echo "Imported $i screenshots."
echo ""
python3 /Users/ericsousa/Desktop/BikeMapDC/scripts/make_appstore_screenshots.py
