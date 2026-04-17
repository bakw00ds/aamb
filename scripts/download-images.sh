#!/usr/bin/env bash
set -euo pipefail

# Pulls original image assets from the live WordPress site into ./images/
# Run from the repo root: ./scripts/download-images.sh

BASE="https://aambarbershop.com/wp-content/uploads"
DEST="./images"

mkdir -p "$DEST"

# local_name|source_path_under_BASE
ASSETS=(
  "logo.png|/2023/11/Logo.png"
  "joe-owner.webp|/2024/01/joe-owner.webp"
  "barbershop-hero.webp|/2023/11/barbershop-scaled.webp"
  "shop-1.jpg|/2024/01/DSC8051-2-1.jpg"
  "shop-2.jpg|/2024/01/DSC8015.jpg"
  "shop-3.jpg|/2024/01/DSC8070-2.jpg"
  "shop-4.jpg|/2024/01/DSC8038-2.jpg"
  "shop-5.jpg|/2024/01/DSC8031-2.jpg"
  "shop-6.jpg|/2024/01/DSC8804.jpg"
  "front-desk.jpg|/2024/01/Front-Desk-Team.jpg"
  "work-1.jpg|/2023/11/340112736_605317664805129_2598058640728603379_n.jpg"
  "work-2.jpg|/2023/11/IMG_2494-1.jpg"
  "work-3.jpg|/2023/11/335465067_1397137474467074_4502418125969218698_n.jpg"
  "work-4.jpg|/2023/11/365557144_786914770102176_3268762660438307073_n.jpg"
  "work-5.jpg|/2023/11/364087187_790265226433797_5339319229144934971_n.jpg"
  "meevo-qr.png|/2023/11/MEEVOBOOKING-1.png"
)

FAILED=()

for entry in "${ASSETS[@]}"; do
  name="${entry%%|*}"
  path="${entry##*|}"
  url="${BASE}${path}"
  out="${DEST}/${name}"
  printf "↓ %-28s  <-  %s\n" "$name" "$url"
  if curl -fsSL "$url" -o "$out"; then
    if [[ ! -s "$out" ]]; then
      FAILED+=("$name (empty file)")
      rm -f "$out"
    fi
  else
    FAILED+=("$name")
  fi
done

echo
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "✓ All ${#ASSETS[@]} images downloaded into ${DEST}/"
else
  echo "⚠ Completed with ${#FAILED[@]} failure(s):"
  for f in "${FAILED[@]}"; do echo "  - $f"; done
  exit 1
fi

# -----------------------------------------------------------------------------
# Manual-drop product photos (NOT fetched by this script)
# -----------------------------------------------------------------------------
# The Shop section (#shop in index.html) references three product photos that
# do NOT exist on the legacy WordPress site. Joe needs to shoot / supply them
# and drop them into ./images/ by the exact filenames below. Until then, the
# <img> tags will 404 — alt text keeps the layout accessible.
#
#   ./images/product-beard-oil.jpg    — Angry Barber Beard Oil
#   ./images/product-beard-balm.jpg   — Angry Barber Beard Balm
#   ./images/product-beard-line.jpg   — Angry Barber Beard Line (shaping tool)
#
# Suggested framing: 4:5 portrait, product centered on a warm/neutral surface,
# ~1200px on the short edge, JPG quality 80. Keep the file names as listed.
# -----------------------------------------------------------------------------
