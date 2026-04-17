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
| Prices / service list | `<ul class="price-list">` inside the `#services` section |
| Testimonials | `<div class="review-grid">` inside the `#reviews` section |
| Hours | `<table class="hours-table">` inside the `#contact` section |
| Address / phone | `#contact` section and the JSON-LD in `<head>` |
| Meevo booking URL | Search for `na0.meevo.com` — appears in 3 places |
| First-responder copy | `<section class="responders">` |
| Marquee strip text | `<div class="marquee-track">` |
| Hero headline / sub | `<section class="hero">` |
| Featured products / shop landing | `<section class="shop" id="shop">` — see Shop below |

### Shop

The `#shop` section is a **landing page**, not a storefront. All products, inventory, pricing logic, tax, and checkout live in **Square Online**, which Joe already uses for in-shop retail. The site exists only to brand the Angry Barber line and drive traffic into Square.

**To update the featured products row:**

1. Drop a new product photo into `./images/` — keep the same filename (e.g. `product-beard-oil.jpg`), or add a new filename and update the `<img src>` in `index.html`.
2. Edit the product name, italic description, and price in the matching `<article class="product-card">` block.
3. Update the per-product placeholder (e.g. `REPLACE_WITH_SQUARE_PRODUCT_1_URL`) to the Square Online product URL.

**To change the "Visit The Full Shop" destination:** search for `REPLACE_WITH_SQUARE_STORE_URL` and update the single store URL placeholder (it's used by the shop-section CTA and the footer link).

**When Joe launches a new product or restocks:** swap it into the featured row so the homepage promotes it. The row is intentionally just three cards — if you're tempted to add a fourth, promote a product out instead.

> **Note:** the three product photos (`product-beard-oil.jpg`, `product-beard-balm.jpg`, `product-beard-line.jpg`) are expected to be dropped in manually — they're not pulled by `scripts/download-images.sh`. See the trailing comment in that script for suggested framing.

### TODO placeholders to fill in before launch

Literal placeholder strings are marked with `<!-- TODO -->` comments. Find them with:

```bash
grep -n "REPLACE_WITH" index.html
```

- **`REPLACE_WITH_JOES_EMAIL@example.com`** — contact form `mailto:` target (1 instance, in the form `action`).
- **`REPLACE_WITH_SQUARE_STORE_URL`** — Angry Barber Square Online store (2 instances — shop-section CTA and footer link).
- **`REPLACE_WITH_SQUARE_PRODUCT_1_URL`** / **`_2_URL`** / **`_3_URL`** — per-product deep-links for the three featured Angry Barber items.

The contact form is currently a plain `mailto:`. Replacing it with Formspree, a Lambda, or similar is a separate future task.

### Updating images

Images are committed to the repo (they're first-party assets and rarely change). To refresh them from the live WordPress site:

```bash
./scripts/download-images.sh
git add images/ && git commit -m "Refresh images"
```

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

Both workflows lint `index.html` with `html5validator`, sync to S3 (respecting `.gitignore` and excluding `.github/`, `scripts/`, `*.md`), re-set cache headers on `index.html` (5 min, revalidate) and `images/` (1 year, immutable), and invalidate CloudFront `/*`.

First-time AWS + GitHub bootstrap is documented in **[DEPLOY.md](DEPLOY.md)**.

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
         │  — Response-headers policy (HSTS etc.)     │
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
         └────────────────────────────────────────────┘
```

## Costs

Roughly **$30–55/mo** at the claimed ~10K visits/day, assuming CloudFront egress dominates:

- S3 storage of a few MB: **~$0**
- S3 requests: **~$1**
- CloudFront requests + egress (~9 GB/day if average page weight stays ~1 MB with images): **$25–50**
- ACM: **free**
- Route 53 hosted zone: **$0.50/mo**

Real traffic is worth verifying — the 10K/day figure could be inflated by bots. If genuine, compressing/resizing the large JPGs in `images/` will cut the egress bill considerably.

---

## Repo layout

```
.
├── index.html                   # the entire site
├── images/                      # committed image assets (run download-images.sh to refresh)
├── scripts/
│   └── download-images.sh       # pulls originals from the live WP site
├── .github/workflows/
│   ├── deploy-staging.yml
│   └── deploy-production.yml
├── .gitignore
├── DEPLOY.md                    # one-time AWS + GitHub bootstrap
└── README.md
```
