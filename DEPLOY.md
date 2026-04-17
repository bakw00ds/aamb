# DEPLOY.md — One-Time AWS + GitHub Bootstrap

This is everything you need to do **once** to wire the repo to AWS. After this, pushing to `main` deploys to staging; tagging `v*` (or a manual approval) deploys to production.

All commands assume:

- AWS CLI authenticated with an admin/bootstrap identity
- Region **`us-east-1`** for both buckets and both ACM certs (CloudFront requires certs in us-east-1)
- Replace `YOUR-GITHUB-ORG/YOUR-REPO` with the actual GitHub slug before running the IAM steps
- Replace `XXXX` in bucket names with a short random suffix (S3 bucket names are global)

---

## 1. Create the two private S3 buckets

Leave **"Block all public access" ON** — CloudFront reaches them via Origin Access Control (OAC), not public URLs.

```bash
aws s3api create-bucket \
  --bucket aam-site-staging-XXXX \
  --region us-east-1

aws s3api create-bucket \
  --bucket aam-site-production-XXXX \
  --region us-east-1

# Make sure public-access block is on (it is by default, but be explicit):
for B in aam-site-staging-XXXX aam-site-production-XXXX; do
  aws s3api put-public-access-block \
    --bucket "$B" \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
done
```

Enable versioning on production (cheap insurance against a bad `aws s3 sync --delete`):

```bash
aws s3api put-bucket-versioning \
  --bucket aam-site-production-XXXX \
  --versioning-configuration Status=Enabled
```

---

## 2. Request ACM certificates (us-east-1)

One cert for staging, one cert covering both prod hostnames.

```bash
# Staging
aws acm request-certificate \
  --region us-east-1 \
  --domain-name staging.aambarbershop.com \
  --validation-method DNS

# Production (apex + www on one cert)
aws acm request-certificate \
  --region us-east-1 \
  --domain-name aambarbershop.com \
  --subject-alternative-names www.aambarbershop.com \
  --validation-method DNS
```

For each cert, open the **ACM console → Certificate → Domains** and copy the CNAME validation records into Route 53 (or wherever DNS is hosted). ACM auto-validates once the CNAME resolves. Don't proceed until both certs show **Issued**.

---

## 3. Create two CloudFront distributions

For each environment (staging, then production), in the CloudFront console create a distribution with:

- **Origin domain**: the S3 bucket (e.g. `aam-site-staging-XXXX.s3.us-east-1.amazonaws.com`) — pick **"Use origin access control"** and create a new OAC. CloudFront will offer to auto-update the bucket policy; either accept or copy the policy yourself in step 4.
- **Viewer protocol policy**: **Redirect HTTP to HTTPS**
- **Allowed HTTP methods**: `GET, HEAD`
- **Cache policy**: **CachingOptimized** (managed)
- **Origin request policy**: none
- **Response headers policy**: create the one from step 9 and attach it
- **Default root object**: `index.html`
- **Alternate domain names (CNAMEs)**:
  - Staging: `staging.aambarbershop.com`
  - Production: `aambarbershop.com`, `www.aambarbershop.com`
- **SSL certificate**: pick the ACM cert from step 2
- **Custom error response**: **404 → `/index.html`, response code 200** (so anchor/hash routing and any typed path fall back to the single page)
- **Price class**: "Use only North America and Europe" is typically fine
- **Default TTL**: leave managed (cache headers on the objects drive behavior)

Note the **Distribution ID** for each — you'll need them as GitHub secrets in step 8.

---

## 4. Apply the OAC bucket policies

If CloudFront didn't auto-write the bucket policy, paste one in by hand. Template (swap in each bucket name, each distribution ARN, and the AWS account id):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipalReadOnly",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::aam-site-staging-XXXX/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT_ID:distribution/EDFDVBD6EXAMPLE"
        }
      }
    }
  ]
}
```

Apply both (staging and production) to the respective buckets:

```bash
aws s3api put-bucket-policy --bucket aam-site-staging-XXXX    --policy file://staging-bucket-policy.json
aws s3api put-bucket-policy --bucket aam-site-production-XXXX --policy file://production-bucket-policy.json
```

---

## 5. DNS — point the hostnames at CloudFront

In Route 53 (or your DNS provider), add **ALIAS / A-records** (or a CNAME if your provider doesn't support ALIAS on apex) pointing at the CloudFront distribution domain (e.g. `d111111abcdef8.cloudfront.net`).

| Record | Type | Target |
| --- | --- | --- |
| `staging.aambarbershop.com` | A (alias) or CNAME | staging CloudFront domain |
| `aambarbershop.com` | A (alias — apex requires alias) | prod CloudFront domain |
| `www.aambarbershop.com` | A (alias) or CNAME | prod CloudFront domain |

Verify with:

```bash
curl -I https://staging.aambarbershop.com
curl -I https://aambarbershop.com
curl -I https://www.aambarbershop.com
```

Each should return `200` and a `server: CloudFront` header.

---

## 6. Create the GitHub OIDC identity provider in IAM

Only needs to be done **once per AWS account**:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

(AWS now validates GitHub's cert chain automatically, but the thumbprint is still a required parameter.)

---

## 7. Create the two IAM deploy roles

Two roles, each scoped to a single bucket + distribution. Production additionally requires the GitHub `environment:production` claim in the trust policy, so nothing outside the protected environment can assume it.

**Staging trust policy** (`trust-staging.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:YOUR-GITHUB-ORG/YOUR-REPO:*"
      }
    }
  }]
}
```

**Production trust policy** (`trust-production.json`) — note the tighter `sub` claim:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:YOUR-GITHUB-ORG/YOUR-REPO:environment:production"
      }
    }
  }]
}
```

**Permission policy** (one per env — swap bucket + distribution id):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::aam-site-staging-XXXX"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject", "s3:GetObject", "s3:PutObjectAcl"],
      "Resource": "arn:aws:s3:::aam-site-staging-XXXX/*"
    },
    {
      "Effect": "Allow",
      "Action": ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"],
      "Resource": "arn:aws:cloudfront::ACCOUNT_ID:distribution/EDFDVBD6EXAMPLE"
    }
  ]
}
```

Create both roles:

```bash
aws iam create-role --role-name GitHubActions-AAM-Staging \
  --assume-role-policy-document file://trust-staging.json
aws iam put-role-policy --role-name GitHubActions-AAM-Staging \
  --policy-name deploy --policy-document file://perm-staging.json

aws iam create-role --role-name GitHubActions-AAM-Production \
  --assume-role-policy-document file://trust-production.json
aws iam put-role-policy --role-name GitHubActions-AAM-Production \
  --policy-name deploy --policy-document file://perm-production.json
```

Copy the two role ARNs — you'll paste them into GitHub secrets next.

---

## 8. Add GitHub repo secrets

In **GitHub → Settings → Secrets and variables → Actions → New repository secret**, add these six secrets:

| Secret name | Value |
| --- | --- |
| `AWS_DEPLOY_ROLE_ARN_STAGING` | ARN of `GitHubActions-AAM-Staging` |
| `AWS_DEPLOY_ROLE_ARN_PRODUCTION` | ARN of `GitHubActions-AAM-Production` |
| `S3_BUCKET_STAGING` | `aam-site-staging-XXXX` |
| `S3_BUCKET_PRODUCTION` | `aam-site-production-XXXX` |
| `CLOUDFRONT_DIST_STAGING` | staging distribution id, e.g. `EDFDVBD6EXAMPLE` |
| `CLOUDFRONT_DIST_PRODUCTION` | production distribution id |

---

## 9. Create the `production` GitHub environment + reviewer rule

**GitHub → Settings → Environments → New environment → `production`**:

- **Required reviewers** — add Joe (or the maintainer) so every production deploy blocks until a human approves
- Optionally **Deployment branches and tags**: restrict to `main` and tags matching `v*`

Repeat for `staging` if you want it, but reviewers aren't required there.

Without this environment, the `environment:production` subject claim in step 7 won't exist and the production role will refuse to assume — this step is required for the trust policy to be satisfiable.

---

## 10. CloudFront response-headers policy (required)

Static sites don't get hacked via SQL injection — they get abused via header-less CDN configs. Create a **Response Headers Policy** (CloudFront → Policies → Response headers → Create) with **all** the headers below and attach it to the default cache behavior on **both** distributions.

| Header | Value | Why |
| --- | --- | --- |
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains; preload` | Forces HTTPS for 2y, covers subdomains, HSTS-preload eligible |
| `X-Content-Type-Options` | `nosniff` | Blocks MIME-type confusion attacks |
| `X-Frame-Options` | `DENY` | Blocks clickjacking via iframe embed |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Prevents leaking full URL paths on outbound clicks |
| `Permissions-Policy` | `geolocation=(), microphone=(), camera=(), payment=(), usb=(), magnetometer=(), gyroscope=()` | Denies browser APIs we don't use |
| `Cross-Origin-Opener-Policy` | `same-origin` | Browsing-context isolation |
| `Cross-Origin-Resource-Policy` | `same-origin` | Prevents cross-site embedding of our resources |
| `Content-Security-Policy` | *see below* | Restricts script/style/image/font/frame origins |

### CSP — copy-pasteable string

```
default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: https://aambarbershop.com; connect-src 'self'; frame-src 'self' https://www.google.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self' mailto:; upgrade-insecure-requests
```

**Notes on the directives:**

- **No `'unsafe-inline'` needed.** All JS and CSS live in `/app.js` and `/app.css` — same-origin external files, covered by `'self'`. Inline `style=""` attributes have been migrated to utility classes. Only `<script type="application/ld+json">` blocks remain inline, and those are non-executable data which CSP `script-src` doesn't gate.
- **Optional: SRI hashes** — for defense-in-depth against origin tampering, add `integrity="sha384-..."` and `crossorigin="anonymous"` to the `<link>` and `<script src>` tags. Compute hashes with `openssl dgst -sha384 -binary app.css | openssl base64 -A`. This is belt-and-suspenders for a same-origin static site; fine to skip.
- `img-src https://aambarbershop.com` allows the absolute OG image URL used in `<meta property="og:image">`. If OG is moved to a relative path, you can remove this allowance.
- `frame-src 'self' https://www.google.com` permits the embedded Google Map iframe on the Contact section.
- `frame-ancestors 'none'` prevents others from embedding us (complementary to `frame-src`; opposite direction).
- `form-action 'self' mailto:` permits the contact form's runtime-assembled `mailto:` action until it's replaced by a real backend endpoint.

**Do not set CSP via `<meta http-equiv>` in the HTML** — the CloudFront response-headers policy is the single source of truth. A meta-tag version can't enforce `frame-ancestors` and can be stripped or modified in transit.

### Validating the policy

After attaching, run:

```bash
curl -sI https://staging.aambarbershop.com | grep -i -E "^(strict-transport|x-content|x-frame|referrer|permissions|cross-origin|content-security)"
```

All eight headers should appear.

---

## 11. AWS WAF — optional hardening

A Web ACL in front of CloudFront adds an inexpensive layer of protection against the most common automated abuse (credential stuffing, WordPress-probe traffic, aggressive scrapers). **Recommended but optional** for a low-traffic local business — turn on if the bill spikes suspiciously or if the site gets unwanted attention.

### What to turn on

Attach a **WAFv2 Web ACL** (CLOUDFRONT scope) to both distributions, with:

- **Managed rule groups** (AWS-provided, free to enable but metered per request):
  - `AWSManagedRulesCommonRuleSet` — baseline protection
  - `AWSManagedRulesKnownBadInputsRuleSet` — blocks known exploit payloads
  - `AWSManagedRulesAmazonIpReputationList` — blocks AWS-flagged bad IPs
- **Rate-based rule** — 1000 requests per 5 minutes per source IP → **Block**. This is enough headroom for a real browsing human and punishes scrapers.
- Enable sampled-requests logging so you can see what's being blocked.

### Cost envelope (10K visits/day)

- Web ACL: **$5/mo**
- Managed rule groups: **$1/mo each × 3 = $3/mo**
- Requests: **$0.60 per million** (10K/day → 300K/mo → ~$0.20)
- **Total: ~$8–10/mo**, occasionally higher if the rate-based rule fires on a big scrape.

### Quick CLI (abbreviated)

```bash
# Create the Web ACL
aws wafv2 create-web-acl \
  --name aam-site \
  --scope CLOUDFRONT \
  --region us-east-1 \
  --default-action Allow={} \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=aam-site \
  --rules file://waf-rules.json

# Then associate with each distribution via the CloudFront console or:
aws cloudfront update-distribution ...
```

Rule-definition JSON is verbose; the AWS console is honestly faster for a one-time setup.

---

## 12. Local SEO — things the site alone can't fix

Local rankings for a barbershop are 80% **off-site** signals. The site is the table stakes; these are the actual wins.

1. **Claim and fully fill out the Google Business Profile** (`business.google.com`). Every field. Services menu with prices (keep it in sync with the two price boards in `index.html`). Attributes (wheelchair accessible, LGBTQ+ friendly, kid-friendly, etc). Photos — post 5+ per month for the first quarter. Use **Google Posts** weekly for 3 months to kickstart engagement. This single lever outweighs almost everything else.
2. **NAP (Name, Address, Phone) consistency** across Google Business, Facebook, Yelp, Apple Maps, Bing Places, Yellow Pages, Foursquare, and the website footer — **exactly the same formatting**. `1700 Kingfisher Dr. Suite 8, Frederick, MD 21701` / `(301) 682-9992`. Inconsistencies (`Ste` vs `Suite`, missing dot, different area-code format) actively confuse ranking.
3. **Request reviews** — target 50+ Google reviews at a 4.7+ average. Reviews are the single biggest local ranking factor after NAP. Ask every satisfied customer to drop one; the review CTAs on the site link directly to the Google + Yelp review forms.
4. **Local citations** — Yelp, Apple Business Connect, Bing Places, Yellow Pages, Foursquare. All free. One focused hour of data entry pays dividends.
5. **Search Console + Bing Webmaster Tools** — submit the sitemap (`/sitemap.xml`) to both once the site is live on the real domain. Check for crawl errors monthly. Watch "Performance" for organic queries to understand what people are actually searching.
6. **Monitor the WordPress blog**. If the live WP site is retired during this migration, redirect the old URLs or keep them live on `blog.aambarbershop.com`. Dropped URLs cost ranking.

---

## Rollback

Every production deploy is tied to a git tag or commit, and the S3 bucket has versioning on (step 1). Two easy rollback paths:

**Option A — redeploy a previous tag** (preferred; keeps history linear):

```bash
# find the last known-good tag
git tag --list 'v*' --sort=-creatordate | head

# re-run the production workflow against that tag
git checkout v1.2.3
# then in GitHub → Actions → "Deploy — Production" → Run workflow → select the tag
```

Or push the tag again if it was deleted:

```bash
git push origin v1.2.3
```

**Option B — S3 object-version restore** (fastest; useful if a tag isn't available):

```bash
# List versions of index.html
aws s3api list-object-versions \
  --bucket aam-site-production-XXXX \
  --prefix index.html

# Copy the desired prior version back into place
aws s3api copy-object \
  --bucket aam-site-production-XXXX \
  --copy-source "aam-site-production-XXXX/index.html?versionId=PREV_VERSION_ID" \
  --key index.html \
  --metadata-directive REPLACE \
  --cache-control "public, max-age=300, must-revalidate" \
  --content-type "text/html; charset=utf-8"

aws cloudfront create-invalidation \
  --distribution-id EDFDVBD6EXAMPLE \
  --paths "/*"
```

After either option, create a new git tag for the rolled-back state so the deployed commit is traceable (`git tag v1.2.4-rollback` etc.).
