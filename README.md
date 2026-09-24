# AI Business Payments

This repository is the cloud layer for the AI Business payment automation.

## Current design

GitHub Actions checks PayPal Sandbox every 5 minutes. It looks for successful transactions from the recent 15-minute window and stores transaction IDs already handled, preventing duplicate processing.

The workflow is:

- `/.github/workflows/paypal-monitor.yml`
- State: `/data/processed_transactions.json`
- Latest detected payments for the current run: `/data/new_payments.json`

## Required PayPal secrets

The workflow needs these **repository Actions secrets**:

- `PAYPAL_CLIENT_ID`
- `PAYPAL_CLIENT_SECRET`

Never put either value in source code, README files, commits, or the Library.

## Environment

Current target: PayPal Sandbox.

PayPal production can be enabled later by changing the API base URL after the end-to-end Sandbox flow is verified.

## Next layer

After payment detection is verified, the next cloud step is to connect a payment event to the business workflow (HubSpot → Notion → Outlook) without depending on the user's local computer or a temporary public tunnel.

<!-- workflow-trigger-check -->
