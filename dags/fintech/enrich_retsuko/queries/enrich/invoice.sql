WITH latest_audit AS (
  SELECT
    id_invoice,
    id_audit,
    MAX(ts_retsuko_updated)
  FROM
    datalake_retsuko.entry
  GROUP BY
    id_invoice,
    id_audit
)
SELECT
    in.id,
    in.id_external,
    in.id_account,
    in.id_contract,
    c.id_external AS id_contract_external,
    la.id_audit,
    in.status,
    in.substatus,
    in.negotiation_status,
    in.paid_via,
    in.purpose,
    in.closing_mode,
    in.reason,
    in.due_amount,
    in.paid_amount,
    in.accrual_year_month,
    in.ts_paid,
    in.ts_canceled,
    in.ts_sent,
    in.ts_due,
    in.ts_created,
    in.ts_retsuko_updated
FROM
    datalake_retsuko_clean.invoice AS in
LEFT JOIN
  latest_audit AS la
ON in.id = la.id_invoice
LEFT JOIN
  datalake_retsuko_clean.contract AS c
      ON c.id = in.id_contract
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY in.id ORDER BY in.ts_retsuko_updated DESC) = 1
