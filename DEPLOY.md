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

## 10. Recommended CloudFront response-headers policy

Create a **Response Headers Policy** (CloudFront → Policies → Response headers → Create) with at minimum:

- **Strict-Transport-Security**: `max-age=31536000; includeSubDomains; preload`
- **X-Content-Type-Options**: `nosniff`
- **Referrer-Policy**: `strict-origin-when-cross-origin`
- **Permissions-Policy**: `geolocation=(), microphone=(), camera=()`
- **X-Frame-Options**: `DENY`

Attach to the default cache behavior on **both** distributions.

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
