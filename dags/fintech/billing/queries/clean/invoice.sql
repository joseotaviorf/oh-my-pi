WITH
original_invoice_base AS (
SELECT
  id,
  regexp_replace(
    regexp_replace(payload, '^"|"$', ''),
    '\\\\"', '"'
  ) AS unescaped_payload
FROM
	datalake_billing_raw.invoice
),
original_invoice AS (
SELECT
  id,
  get_json_object(unescaped_payload, '$.original-id') as id_original
FROM
  original_invoice_base
)
SELECT
	i.id,
	account_id AS id_account,
	contract_id AS id_contract,
	source_invoice_id AS id_source_invoice,
	o.id_original,
	i.seubarriga_invoice_id AS id_seubarriga_invoice,
	account_type,
	status,
	sub_status,
	purpose,
	transaction_type,
	payload,
	due_amount,
	accrual_year_month AS dt_accrual_year_month,
	due_date AS dt_due,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
	datalake_billing_raw.invoice i
LEFT JOIN
  original_invoice o
  ON i.id = o.id
-- This filter ensures that only records created after the billing cleanup are considered.
WHERE i.created_at > '2026-01-21'
