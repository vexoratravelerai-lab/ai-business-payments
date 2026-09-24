# AI Business Payments

This repository is the cloud automation layer for the Vexora AI managed-service payment flow.

## First Sale Mode

The project is designed to obtain the first paying customer without requiring a monthly SaaS subscription, paid server, paid domain, or paid Calendly plan.

The commercial flow is:

Landing Page → Calendly → Strategy Session → PayPal → HubSpot → Notion Onboarding → Delivery → Measurement

Email automation is optional during the first-sale phase. A customer can be handled manually by email after a confirmed payment; the payment and CRM/onboarding automation do not depend on Resend.

## Cloud payment monitor

GitHub Actions checks PayPal every 5 minutes.

The monitor:

1. Finds successful PayPal transactions in the lookback window.
2. Preserves PayPal payer information when it is available.
3. Creates or reuses the matching HubSpot deal as Closed Won.
4. Creates or promotes the payer Contact to HubSpot Customer when an email is available.
5. Creates the Notion onboarding page and Funnel Tracker record.
6. Sends a welcome email through Resend when the optional sender configuration is ready.
7. Uses downstream idempotency instead of storing payment state in public repository files.

There is no `data/processed_transactions.json` or `data/new_payments.json` production state file.

## PayPal environment

The workflow supports:

- `sandbox` — default when `PAYPAL_ENVIRONMENT` is not set.
- `live` — uses `https://api-m.paypal.com`.

Switching to Live does not require rewriting the workflow. It requires a PayPal Business account plus Live API credentials stored as GitHub Actions secrets.

## Required GitHub Actions secrets

- `PAYPAL_CLIENT_ID`
- `PAYPAL_CLIENT_SECRET`
- `HUBSPOT_SERVICE_KEY`
- `NOTION_TOKEN` (needed for Notion automation)
- `RESEND_API_KEY` (optional for first-sale mode)
- `RESEND_FROM_ADDRESS` (optional for first-sale mode)
- `PAYPAL_ENVIRONMENT` (optional; use `sandbox` or `live`)

Never put secrets, customer payment data, or API credentials in source code, README files, commits, or public state files.

## Current architecture

The local computer is not required for payment monitoring. The production workflow runs in GitHub Actions.

n8n/localtunnel is not part of the payment detection path.

## Verification

The repository contains an isolated logic test at:

`scripts/paypal-monitor-logic-test.sh`

It uses only synthetic fixture data and does not create real payments, contacts, or customers.

The payment monitor is intentionally re-runnable: HubSpot deal names, Notion transaction identifiers, and Resend idempotency keys protect against duplicate downstream processing.

## Operating principle

Do not pay for infrastructure before there is revenue to justify it. Start with the free/transactional path, close the first customer, deliver the first measurable result, then upgrade only where the revenue proves the expense is worthwhile.
