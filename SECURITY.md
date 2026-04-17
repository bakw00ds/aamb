# Security Policy

## Scope

This policy covers the static website at **https://aambarbershop.com** (and its staging counterpart). Our shop's booking, POS, and retail systems are hosted by third parties (Meevo, Square) and are out of scope — please report issues in those systems directly to their vendors.

## Reporting a vulnerability

If you believe you've found a security issue that affects this website, please report it privately. We prefer email over public disclosure so that any risk to customers is minimized until a fix is in place.

- Email: see `.well-known/security.txt`
- Phone (shop): (301) 682-9992 (ask for the shop manager; we'll route it)

Please include:

- A clear description of the issue and its impact
- Steps to reproduce (URLs, payloads, screenshots if helpful)
- Any proof-of-concept — keep it minimal and non-destructive
- Your preferred credit (name/handle) if you'd like us to acknowledge you when the fix ships

## What to expect

- **Acknowledgement** within 5 business days
- **Triage** and a good-faith timeline within 10 business days
- **Fix and disclosure** coordinated with you; a short delay is fine, indefinite silence is not

## Safe harbor

We won't pursue civil or criminal action against researchers acting in good faith under this policy — meaning you:

- Don't access, modify, or exfiltrate data that isn't yours
- Don't degrade service for real users (no DoS, mass scraping, or social-engineering our staff)
- Give us reasonable time to fix before any public disclosure
- Follow the law

If you're unsure whether something is in scope or safe, ask first.

## What's out of scope

- Issues in third-party platforms (Meevo booking, Square checkout, Google Maps, the WordPress blog during transition)
- Findings that require physical access to the shop or its POS hardware
- Vulnerabilities in outdated browsers or misconfigured client devices
- Theoretical CSP / header findings that don't show a working exploit path
- Automated-scanner output without a reproducible POC
