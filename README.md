# All About Men Barbershop — Marketing Site

Static marketing site for [All About Men Barbershop](https://aambarbershop.com) in Frederick, MD. One `index.html`, a `/images/` folder, no build step, no framework. Deployed to AWS S3 + CloudFront with GitHub Actions CI/CD.

---

## Local preview

```bash
git clone <repo-url>
cd aamb
./scripts/download-images.sh      # first time only — images are also committed
python3 -m http.server 8000       # then open http://localhost:8000
```

Any static file server will do — the site has no build step.

---

## Making content edits

Everything lives in a single `index.html`. Common edits:

| What you want to change | Where |
| --- | --- |
| Prices / services (two boards) | `#services` — haircuts on the left board, shaves on the right. **Prices must stay in sync with the `hasOfferCatalog` block in the LocalBusiness JSON-LD.** |
| Testimonials | `<div class="review-grid">` inside `#reviews` |
| Hours | `<table class="hours-table">` in `#contact` + the `openingHoursSpecification` JSON-LD + the compressed line in the footer Visit column |
| Address / phone | `#contact` + the `PostalAddress` JSON-LD + the map iframe `title` + the footer Visit column (NAP consistency — see DEPLOY.md §12) |
| Meevo booking URL | Search for `na0.meevo.com` — appears in several places (hero slides, header, mobile CTA, popup, QR link, footer) |
| First-responder copy | `<section class="responders">` |
| Gift cards copy / phone | `<section class="giftcards">` |
| First visit cards | `.fv-grid` inside `#first-visit` |
| FAQ | see "Updating FAQs" below |
| Carousel slides | see "Updating carousel slides" below |
| Popup modal image | see "Updating the popup" below |
| Marquee strip text | `<div class="marquee-track">` — duplicate into **both** halves so the scroll stays seamless |
| Hero slides | three `<article class="slide">` blocks in `<section class="hero-carousel">` |
| Blog | see "Adding a new blog post" below |
| Featured products / shop landing | `#shop` — see Shop below |
| Social links | footer band 2 only — see "Social links" below |

### Updating carousel slides

Three `<article class="slide">` blocks inside `<section class="hero-carousel">`. Each has a `style="background-image: url('./images/carousel-N.jpg')"`, a badge, a headline, a subhead, and two CTAs. Replace the image files with `./images/carousel-1.jpg`, `carousel-2.jpg`, `carousel-3.jpg` to update photography. If the files don't exist, `scripts/download-images.sh` copies in fallbacks from the shop photos so the site stays functional.

### Updating the popup

- The popup uses `./images/popup.jpg`. Drop in a new graphic to change the message.
- The popup is gated by `localStorage['aam-popup-dismissed-v1']`. **To force all returning visitors to see a new popup, bump the key** from `-v1` to `-v2` (and so on) in the `<script>` block — search for `POPUP_KEY`.
- If the image fails to load, a text fallback appears automatically ("Welcome to All About Men" + book CTA). No 404 breakage.

### Updating FAQs

FAQs live in two places and **must match verbatim**:

1. `<details class="faq-item">` blocks inside `#faq`
2. The `FAQPage` JSON-LD block in `<head>` (search for `"@type": "FAQPage"`)

Google penalizes schema mismatches for FAQ rich results. Edit both when you edit either.

### Updating the services menus

Two `.price-board` elements inside `#services` — haircuts on the left, shaves on the right. When updating a price:

1. Edit the `<span class="price-amt">` and the `<div class="price-desc">` for the row
2. Update the matching `{ "@type": "Offer", ... }` entry in the `hasOfferCatalog` block of the LocalBusiness JSON-LD in `<head>`

**18 services total** (10 haircuts + 8 shaves). If you add or remove one, the HTML count and the JSON-LD count must both change.

### Social links

Facebook, Instagram, TikTok, YouTube, Pinterest are hardcoded in the footer socials band (band 2). **The footer band is the canonical home for social icons** — they don't appear anywhere else. Don't re-add them to About or Contact.

### Review platform URLs

Google Maps and Yelp URLs are hardcoded in three places:

1. The two "Review Us On ___" buttons at the bottom of `#reviews`
2. The Off-Site column in the footer ("Google Reviews", "Yelp")
3. The `sameAs` array in the LocalBusiness JSON-LD

If a URL changes, update all three.

### Embedded map

The iframe in `#contact` uses Google's public embed URL — **no API key required**. To change the location, search for a new place in Google Maps → Share → Embed a map → copy the `src` URL.

### Shop

The `#shop` section is a **landing page**, not a storefront. All products, inventory, pricing logic, tax, and checkout live in **Square Online**, which Joe already uses for in-shop retail. The site exists only to brand the Angry Barber line and drive traffic into Square.

**To update the featured products row:**

1. Drop a new product photo into `./images/` — keep the same filename (e.g. `product-beard-oil.jpg`), or add a new filename and update the `<img src>` in `index.html`.
2. Edit the product name, italic description, and price in the matching `<article class="product-card">` block.
3. Update the per-product placeholder (e.g. `REPLACE_WITH_SQUARE_PRODUCT_1_URL`) to the Square Online product URL.

**To change the "Visit The Full Shop" destination:** search for `REPLACE_WITH_SQUARE_STORE_URL` and update the placeholder — it's used by the shop-section CTA, the hero carousel's slide 3, and the footer link.

### Adding a new blog post

1. Add a new `<article class="blog-card">` at the **top** of the `.blog-grid` inside `#blog` with the post's title, date (in `MM.DD.YYYY` format), and full public URL
2. Drop the featured image at `./images/blog/blog-N.jpg` (next unused number)
3. Commit and push — the grid renders newest-first by code order

**Future blog decision** — the cards currently deep-link to the WordPress site at `aambarbershop.com/…`. When WP is decommissioned, those links break. Options:

- **Keep WP archived** on `blog.aambarbershop.com` (simplest, preserves history)
- **Migrate post bodies** to static HTML in this repo (more work, fewer moving parts)
- **Move to a headless CMS** (Ghost, Contentful, headless WP) — overkill for a barbershop

Document whichever path Joe picks before pulling the plug on WP.

### Email obfuscation — never hardcode a raw email

Visible emails on the page are harvester bait. We use a `data-u` / `data-d` split pattern:

```html
<a class="email-link" data-u="info" data-d="example.com"><span class="email-fallback">contact us</span></a>
```

A runtime script assembles `info@example.com`, wires `href="mailto:…"`, and sets the text. The source HTML never contains a literal address.

- The contact form uses the same pattern on the `<form>` itself (`data-u` + `data-d`; submit handler sets `action`).
- When Joe's real email lands, **use the pattern** — don't regress to raw `mailto:`.

### Honeypot field

The contact form has an invisible `#f-website` input wrapped in `.honeypot`. Bots fill it; humans can't see it. Any future backend (Formspree, Lambda, SES, etc.) **must reject submissions where `website !== ""`** — this is server-side-enforced spam filtering that costs nothing.

### Accessibility statement

The `#accessibility` section before the footer, plus a fixed bottom-left accessibility icon, are the full accessibility UX. **The site intentionally does NOT use a third-party accessibility-overlay widget** (UserWay / accessiBe / EqualWeb). Those overlays are widely considered anti-patterns, have been named in ADA class-action lawsuits, and often break real screen readers. Do not add one without reading up first. Real accessibility = semantic HTML + alt text + keyboard nav + AA contrast — which this site does.

### AI crawlers (robots.txt)

`robots.txt` currently **allows** AI training bots (GPTBot, Claude-Web, Google-Extended, Applebot-Extended). For a local business, being cited by AI assistants is a discovery win — the same reason you want to be in Google. To block them, add explicit `User-agent: GPTBot` / `Disallow: /` blocks to `robots.txt`. Make the choice explicit.

### Analytics (not currently present)

No analytics is installed — no Google Analytics, no Plausible, no Fathom, no tracking of any kind. When analytics is added later:

1. Update CSP `connect-src` in the CloudFront response-headers policy to allow the analytics host
2. Add a privacy policy section mentioning it
3. If the analytics sets cookies, add a cookie consent banner

### TODO placeholders to fill in before launch

Literal placeholder strings are marked with `<!-- TODO -->` comments. Find them with:

```bash
grep -rn "REPLACE_WITH" .
```

Expected remaining placeholders:

- **`REPLACE_WITH_JOES_EMAIL`** — contact form (`data-u`/`data-d` split) and `security.txt`
- **`REPLACE_WITH_SQUARE_STORE_URL`** — Angry Barber Square store (3 usages: hero slide 3, shop CTA, footer)
- **`REPLACE_WITH_SQUARE_PRODUCT_1_URL`** / **`_2_URL`** / **`_3_URL`** — per-product deep-links

### Updating images

Images are committed to the repo (they're first-party assets and rarely change). To refresh them from the live WordPress site:

```bash
./scripts/download-images.sh
git add images/ && git commit -m "Refresh images"
```

The script pulls originals where available and soft-fails on anything that's missing (product photos, carousel-specific shots). Soft-failed files show placeholders; the page still renders.

---

## Deploying

There are two environments, both static S3 + CloudFront.

| Environment | URL | Trigger |
| --- | --- | --- |
| **Staging** | https://staging.aambarbershop.com | Auto on every push to `main` (or manual `workflow_dispatch`) |
| **Production** | https://aambarbershop.com · https://www.aambarbershop.com | Push a `v*` tag **or** run the production workflow manually (requires typing `deploy` in the confirm input, plus a GitHub-environment reviewer approval) |

```bash
# deploy to staging — just push
git push origin main

# deploy to production — tag a release
git tag v1.0.0
git push origin v1.0.0
```

Both workflows lint `index.html` with `html5validator`, stamp the current date into `sitemap.xml`, sync to S3 (respecting `.gitignore` and excluding `.github/`, `scripts/`, `*.md`, but re-including `.well-known/*`), re-set cache headers on `index.html` (5 min, revalidate) and `images/` (1 year, immutable), and invalidate CloudFront `/*`.

First-time AWS + GitHub bootstrap — buckets, ACM, CloudFront, OIDC/IAM, response-headers policy (CSP included), optional WAF, and the Local-SEO checklist — is documented in **[DEPLOY.md](DEPLOY.md)**.

### Branch protection (recommended)

In **GitHub → Settings → Branches** on `main`:

- Require a pull request before merging
- Require status checks to pass (html5validator + the deploy workflows)
- Require signed commits (if contributors have GPG set up)
- Do not allow force pushes

---

## Architecture

```
                     ┌──────────────────────────────┐
                     │   Route 53 (aambarbershop.com)│
                     └──────────────┬───────────────┘
                                    │  ALIAS / A-record
                                    ▼
         ┌────────────────────────────────────────────┐
         │  CloudFront distributions (prod + staging) │
         │  — TLS via ACM (us-east-1)                 │
         │  — OAC → S3 origin                         │
         │  — 404 → /index.html (for anchor routing)  │
         │  — Response-headers policy + CSP           │
         │  — (optional) AWS WAF Web ACL              │
         └────────────────────────┬───────────────────┘
                                  │
                                  ▼
         ┌────────────────────────────────────────────┐
         │  S3 buckets (private, OAC-only)            │
         │  — aam-site-production-XXXX                │
         │  — aam-site-staging-XXXX                   │
         └────────────────────────┬───────────────────┘
                                  ▲
                                  │ aws s3 sync
                                  │
         ┌────────────────────────┴───────────────────┐
         │  GitHub Actions                             │
         │  — OIDC → IAM role (per-env, repo-scoped)   │
         │  — push to main ⇒ staging                   │
         │  — v* tag or manual ⇒ production            │
         │  — sed stamps sitemap lastmod each deploy   │
         └────────────────────────────────────────────┘
```

## Costs

Roughly **$30–55/mo** at the claimed ~10K visits/day, assuming CloudFront egress dominates:

- S3 storage of a few MB: **~$0**
- S3 requests: **~$1**
- CloudFront requests + egress (~9 GB/day if average page weight stays ~1 MB with images): **$25–50**
- ACM: **free**
- Route 53 hosted zone: **$0.50/mo**
- WAF (optional): **~$8–10/mo** — see DEPLOY.md §11

Real traffic is worth verifying — the 10K/day figure could be inflated by bots. If genuine, compressing/resizing the large JPGs in `images/` will cut the egress bill considerably.

---

## Repo layout

```
.
├── index.html                      # the entire site
├── robots.txt                      # bot allow/block + sitemap pointer
├── sitemap.xml                     # single-URL sitemap; lastmod stamped by CI
├── SECURITY.md                     # disclosure policy
├── .well-known/
│   └── security.txt                # RFC 9116 disclosure metadata
├── images/
│   ├── (shop + work photos)
│   ├── product-*.jpg               # manually dropped in
│   ├── carousel-*.jpg              # fallback-copied by download script
│   ├── popup.jpg                   # first-visit modal graphic
│   └── blog/                       # blog-1.jpg … blog-9.jpg
├── scripts/
│   └── download-images.sh          # pulls originals + fallbacks
├── .github/
│   ├── dependabot.yml              # monthly Actions bumps
│   └── workflows/
│       ├── deploy-staging.yml
│       └── deploy-production.yml
├── .gitignore
├── DEPLOY.md                       # one-time AWS bootstrap + CSP + WAF + Local SEO
└── README.md
```
