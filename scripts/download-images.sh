#!/usr/bin/env bash
set -euo pipefail

# Pulls original image assets from the live WordPress site into ./images/
# Run from the repo root: ./scripts/download-images.sh

BASE="https://aambarbershop.com/wp-content/uploads"
DEST="./images"

mkdir -p "$DEST" "$DEST/blog"

# ----------------------------------------------------------------------
# Part 1 — core assets (required; hard-fail on error)
# ----------------------------------------------------------------------
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

if [[ ${#FAILED[@]} -ne 0 ]]; then
  echo
  echo "⚠ Core downloads completed with ${#FAILED[@]} failure(s):"
  for f in "${FAILED[@]}"; do echo "  - $f"; done
  exit 1
fi

echo
echo "✓ Core ${#ASSETS[@]} images downloaded into ${DEST}/"

# ----------------------------------------------------------------------
# Part 2 — popup image (soft-fail)
# ----------------------------------------------------------------------
# The first-visit modal uses /images/popup.jpg. This script tries to fetch
# the current one from the live WP site; if it 404s, the <img> tag in
# index.html falls back to a text-only welcome card at runtime.
echo
echo "↓ popup.jpg (soft-fail)"
if ! curl -fsSL -o "${DEST}/popup.jpg" \
    "https://aambarbershop.com/wp-content/uploads/2026/03/policyupdate26.jpg"; then
  echo "⚠ popup.jpg missing — drop a fresh graphic at ${DEST}/popup.jpg when ready (the modal will text-fallback until then)"
  rm -f "${DEST}/popup.jpg"
fi

# ----------------------------------------------------------------------
# Part 3 — blog featured images (soft-fail each)
# ----------------------------------------------------------------------
# 9 post cards in #blog reference ./images/blog/blog-1.jpg through blog-9.jpg.
# Self-hosting — CSP img-src does not need a third-party allowance.
echo
echo "↓ blog featured images (soft-fail each)"
BLOG_ASSETS=(
  "blog-1.jpg|/2025/12/handsome-man-with-fresh-haircut-and-beard-wearing-blue-denim-outfit-posing-in-front-of-grey-wall.jpg"
  "blog-2.jpg|/2025/10/Closeup-face-headshot-portrait-of-middle-age-mature-adult-man.jpg"
  "blog-3.jpg|/2025/07/Portrait-of-joyful-man-enjoying-summer-holiday-at-beach.jpg"
  "blog-4.jpg|/2025/05/Confident-bearded-man-in-casual-attire-standing-outdoors-with-a-focused-expression.jpg"
  "blog-5.jpg|/2024/11/A-profile-view-of-a-handsome-man-grooming-brushing-and-moisturizing-the-beard-hair-in-front-of-the-mirror-in-a-bathroom-1-1.jpg"
  "blog-6.jpg|/2024/09/Shaving-accessories-on-wooden-background.jpg"
  "blog-7.jpg|/2024/07/A-close-up-portrait-of-a-mans-large-red-beard-his-facial-hair-filling-the-image-frame.-His-face-is-obscured-by-the-composition-emphasizing-the-masculine-mustache-and-beard.-1.jpg"
  "blog-8.jpg|/2024/03/Close-up-of-barbers-tattooed-hands-holding-comb-and-scissors-and-giving-man-trendy-hairstyle.jpg"
  "blog-9.jpg|/2022/10/man-against-a-gray-background-showing-off-his-fresh-haircut-beard-trim-and-maroon-sweater-.jpg"
)
BLOG_FAILED=()
for entry in "${BLOG_ASSETS[@]}"; do
  name="${entry%%|*}"
  path="${entry##*|}"
  out="${DEST}/blog/${name}"
  if curl -fsSL "${BASE}${path}" -o "$out"; then
    if [[ ! -s "$out" ]]; then
      BLOG_FAILED+=("$name")
      rm -f "$out"
    fi
  else
    BLOG_FAILED+=("$name")
  fi
done
if [[ ${#BLOG_FAILED[@]} -eq 0 ]]; then
  echo "✓ All 9 blog images downloaded into ${DEST}/blog/"
else
  echo "⚠ ${#BLOG_FAILED[@]} blog image(s) failed: ${BLOG_FAILED[*]} (cards render with cream placeholder)"
fi

# ----------------------------------------------------------------------
# Part 4 — hero carousel fallback copies
# ----------------------------------------------------------------------
# The carousel references carousel-1/2/3.jpg. Joe can drop in dedicated
# slider photos later; until then, copy in fallbacks from the shop images
# so the carousel works out of the box on a fresh clone.
echo
echo "↓ carousel fallbacks"
declare -a CAROUSEL_MAP=(
  "carousel-1.jpg|shop-1.jpg"
  "carousel-2.jpg|shop-4.jpg"
  "carousel-3.jpg|barbershop-hero.webp"
)
for entry in "${CAROUSEL_MAP[@]}"; do
  target="${entry%%|*}"
  source_file="${entry##*|}"
  if [[ -f "${DEST}/${target}" ]]; then
    echo "  = ${target} already exists, leaving it alone"
  elif [[ -f "${DEST}/${source_file}" ]]; then
    cp "${DEST}/${source_file}" "${DEST}/${target}"
    echo "  + ${target} (fallback copy of ${source_file})"
  else
    echo "  ⚠ ${target} — source ${source_file} missing, skipped"
  fi
done

# ----------------------------------------------------------------------
# Manual-drop product photos (NOT fetched by this script)
# ----------------------------------------------------------------------
# The Shop section (#shop) references three product photos that do NOT
# exist on the legacy WordPress site. Joe supplies these manually:
#
#   ./images/product-beard-oil.jpg    — Angry Barber Beard Oil
#   ./images/product-beard-balm.jpg   — Angry Barber Beard Balm
#   ./images/product-beard-line.jpg   — Angry Barber Beard Line (shaping tool)
#
# Suggested framing: 4:5 portrait, product centered on a warm/neutral
# surface, ~1200px short edge, JPG quality 80. Keep the filenames exact.
# Until they exist, the product cards render with a cream placeholder;
# alt text keeps the layout accessible.

echo
echo "✓ Done."
