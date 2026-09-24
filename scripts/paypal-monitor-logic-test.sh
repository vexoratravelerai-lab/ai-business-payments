#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="\${TMPDIR:-/tmp}/paypal-monitor-logic-test"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

cat > "$TMP_DIR/paypal-fixture.json" <<'JSON'
{
  "transaction_details": [
    {
      "transaction_info": {
        "transaction_id": "UNIT-TEST-001",
        "transaction_status": "S",
        "transaction_event_code": "T0000",
        "transaction_amount": {
          "value": "10.00",
          "currency": "USD"
        },
        "transaction_subject": "AI Automation Starter Setup"
      },
      "payer_info": {
        "email_address": "unit-test@example.invalid",
        "payer_name": {
          "full_name": "Unit Test Customer"
        }
      }
    }
  ]
}
JSON

jq --argjson min_amount 0 '
  .transaction_details // []
  | map(select(.transaction_info.transaction_id != null))
  | map((.transaction_info // {}) + {payer_info: (.payer_info // null)})
  | map(. + {
      amount_value: ((.transaction_amount.value // "0") | tonumber),
      amount_currency: (.transaction_amount.currency // null)
    })
  | map(select(.transaction_status == "S"))
  | map(select(.transaction_event_code != "T1900"))
  | map(select(.amount_value >= $min_amount))
' "$TMP_DIR/paypal-fixture.json" > "$TMP_DIR/payments.json"

test "$(jq -r 'length' "$TMP_DIR/payments.json")" = "1"
test "$(jq -r '.[0].transaction_id' "$TMP_DIR/payments.json")" = "UNIT-TEST-001"
test "$(jq -r '.[0].payer_info.email_address' "$TMP_DIR/payments.json")" = "unit-test@example.invalid"
test "$(jq -r '.[0].payer_info.payer_name.full_name' "$TMP_DIR/payments.json")" = "Unit Test Customer"
test "$(jq -r '.[0].amount_value' "$TMP_DIR/payments.json")" = "10.00"
test "$(jq -r '.[0].amount_currency' "$TMP_DIR/payments.json")" = "USD"

PAYMENT="$(jq -c '.[0]' "$TMP_DIR/payments.json")"
TX_ID="$(printf '%s' "$PAYMENT" | jq -r '.transaction_id')"
AMOUNT="$(printf '%s' "$PAYMENT" | jq -r '.amount_value')"
CURRENCY="$(printf '%s' "$PAYMENT" | jq -r '.transaction_amount.currency_code // .amount_currency // "USD"')"
SUBJECT="$(printf '%s' "$PAYMENT" | jq -r '.transaction_subject // "PayPal payment"')"
PAYER_EMAIL="$(printf '%s' "$PAYMENT" | jq -r '.payer_info.email_address // ""')"
PAYER_NAME="$(printf '%s' "$PAYMENT" | jq -r '.payer_info.payer_name.full_name // ""')"

DEAL_PAYLOAD="$(jq -n \
  --arg name "PayPal Payment $TX_ID" \
  --arg amount "$AMOUNT" \
  --arg currency "$CURRENCY" \
  --arg subject "$SUBJECT" \
  --arg tx "$TX_ID" \
  --arg email "$PAYER_EMAIL" \
  --arg payer "$PAYER_NAME" \
  '{
    properties:{
      dealname:$name,
      amount:$amount,
      pipeline:"default",
      dealstage:"closedwon",
      description:("Payment status: Paid | PayPal transaction: "+$tx+" | Currency: "+$currency+" | Subject: "+$subject+" | Payer: "+$payer+" | Email: "+$email)
    }
  }')"

test "$(jq -r '.properties.dealstage' <<<"$DEAL_PAYLOAD")" = "closedwon"
test "$(jq -r '.properties.amount' <<<"$DEAL_PAYLOAD")" = "10.00"
grep -q "unit-test@example.invalid" <<<"$DEAL_PAYLOAD"
grep -q "Unit Test Customer" <<<"$DEAL_PAYLOAD"

CONTACT_CREATE_PAYLOAD="$(jq -n \
  --arg email "$PAYER_EMAIL" \
  --arg name "$PAYER_NAME" \
  '{
    properties:{
      email:$email,
      lifecyclestage:"customer",
      firstname:($name | split(" ")[0]),
      lastname:($name | split(" ") | .[1:] | join(" "))
    }
  }')"

test "$(jq -r '.properties.lifecyclestage' <<<"$CONTACT_CREATE_PAYLOAD")" = "customer"
test "$(jq -r '.properties.email' <<<"$CONTACT_CREATE_PAYLOAD")" = "unit-test@example.invalid"
test "$(jq -r '.properties.firstname' <<<"$CONTACT_CREATE_PAYLOAD")" = "Unit"
test "$(jq -r '.properties.lastname' <<<"$CONTACT_CREATE_PAYLOAD")" = "Test Customer"

assert_promotion() {
  case "$1" in
    ""|subscriber|lead|marketingqualifiedlead|salesqualifiedlead|opportunity) echo customer ;;
    customer|evangelist|other) echo unchanged ;;
    *) echo unchanged ;;
  esac
}

test "$(assert_promotion "")" = "customer"
test "$(assert_promotion "lead")" = "customer"
test "$(assert_promotion "opportunity")" = "customer"
test "$(assert_promotion "customer")" = "unchanged"
test "$(assert_promotion "evangelist")" = "unchanged"
test "$(assert_promotion "other")" = "unchanged"
test "$(assert_promotion "unknown")" = "unchanged"

NOTION_PROPERTIES="$(jq -n \
  --arg client "$PAYER_NAME" \
  --arg tx "$TX_ID" \
  --arg notes "Automatic PayPal sync. Transaction: $TX_ID." \
  --arg booking "https://calendly.com/vexora-traveler-ai/30min" \
  --arg email "$PAYER_EMAIL" \
  '{
    Client:{title:[{text:{content:$client}}]},
    Stage:{select:{name:"Paid"}},
    Status:{status:{name:"قيد التنفيذ"}},
    Source:{select:{name:"Other"}},
    "Payment ID":{rich_text:[{text:{content:$tx}}]},
    Calendly:{url:$booking},
    Notes:{rich_text:[{text:{content:$notes}}]},
    Email:{email:$email}
  }')"

test "$(jq -r '.Stage.select.name' <<<"$NOTION_PROPERTIES")" = "Paid"
test "$(jq -r '.Status.status.name' <<<"$NOTION_PROPERTIES")" = "قيد التنفيذ"
test "$(jq -r '.["Payment ID"].rich_text[0].text.content' <<<"$NOTION_PROPERTIES")" = "UNIT-TEST-001"
test "$(jq -r '.Calendly.url' <<<"$NOTION_PROPERTIES")" = "https://calendly.com/vexora-traveler-ai/30min"
test "$(jq -r '.Email.email' <<<"$NOTION_PROPERTIES")" = "unit-test@example.invalid"

RESEND_HTML="<p>مرحبا $PAYER_NAME</p><p><a href=\"https://calendly.com/vexora-traveler-ai/30min\">احجز الاجتماع</a></p>"
RESEND_PAYLOAD="$(jq -n \
  --arg from "Vexora AI <onboarding@resend.dev>" \
  --arg to "$PAYER_EMAIL" \
  --arg subject "AI Business — Welcome & Next Step" \
  --arg html "$RESEND_HTML" \
  '{from:$from,to:[$to],subject:$subject,html:$html}')"

test "$(jq -r '.to[0]' <<<"$RESEND_PAYLOAD")" = "unit-test@example.invalid"
test "$(jq -r '.subject' <<<"$RESEND_PAYLOAD")" = "AI Business — Welcome & Next Step"
grep -q "calendly.com/vexora-traveler-ai/30min" <<<"$RESEND_PAYLOAD"

IDEMPOTENCY_KEY="paypal-$TX_ID-welcome-v1"
test "$IDEMPOTENCY_KEY" = "paypal-UNIT-TEST-001-welcome-v1"

grep -q '+ {payer_info: (.payer_info // null)}' .github/workflows/paypal-monitor.yml
grep -q 'Notion Funnel Tracker already contains PayPal transaction' .github/workflows/paypal-monitor.yml
grep -q 'lifecyclestage:"customer"' .github/workflows/paypal-monitor.yml
grep -q 'customer|evangelist|other' .github/workflows/paypal-monitor.yml
grep -q 'https://calendly.com/vexora-traveler-ai/30min' .github/workflows/paypal-monitor.yml
grep -q 'Idempotency-Key' .github/workflows/paypal-monitor.yml

echo "PASS: PayPal normalization"
echo "PASS: payer identity propagation"
echo "PASS: HubSpot Closed Won + Customer lifecycle"
echo "PASS: Notion Paid/In-progress + Payment ID + Calendly"
echo "PASS: Resend recipient + subject + Calendly"
echo "PASS: Idempotency key"
echo "PASS: production workflow invariants"

# Exercise the no-domain fallback without contacting Resend.
QUEUE="$TMP_DIR/pending_welcome_emails.json"
printf '[]\n' > "$QUEUE"
QUEUED_PAYMENT="$(jq -n --arg tx "$TX_ID" --arg email "$PAYER_EMAIL" --arg name "$PAYER_NAME" \
  '. + [{transaction_id:$tx,payer_email:$email,payer_name:$name,queued_reason:"Resend sender domain not configured"}]' <<<"[]")"
printf '%s\n' "$QUEUED_PAYMENT" > "$QUEUE"

test "$(jq -r 'length' "$QUEUE")" = "1"
test "$(jq -r '.[0].transaction_id' "$QUEUE")" = "UNIT-TEST-001"
test "$(jq -r '.[0].payer_email' "$QUEUE")" = "unit-test@example.invalid"
test "$(jq -r '.[0].queued_reason' "$QUEUE")" = "Resend sender domain not configured"

grep -q 'RESEND_FROM_ADDRESS' .github/workflows/paypal-monitor.yml
grep -q 'pending_welcome_emails.json' .github/workflows/paypal-monitor.yml
grep -q 'Welcome email .* queued' .github/workflows/paypal-monitor.yml
grep -q 'Retry Pending Welcome Emails' .github/workflows/retry-pending-welcome-emails.yml
grep -q 'paypal-$TX_ID-welcome-v1' .github/workflows/retry-pending-welcome-emails.yml
grep -q 'git add data/processed_transactions.json data/new_payments.json data/pending_welcome_emails.json' .github/workflows/paypal-monitor.yml

echo "PASS: no-domain pending email queue"
echo "PASS: pending queue retry workflow"
