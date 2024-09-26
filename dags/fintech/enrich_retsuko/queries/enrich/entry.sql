SELECT
    e.id,
    e.id_external,
    e.id_invoice,
    e.id_contract,
    e.id_from_account,
    e.id_to_account,
    e.id_external_reversed_entry,
    e.id_audit,
    e.accounting_transaction_identifier,
    ROUND(CASE
          WHEN af.type = 'contract'
              AND at.type <> 'contract' THEN -1.0 * e.amount
      ELSE e.amount
      END, 2) AS amount,
    e.bill_item,
    e.description,
    e.producer,
    e.status,
    e.accrual_year_month,
    e.due_year_month,
    e.ts_created,
    e.ts_synced,
    e.ts_retsuko_updated,
    e.ts_database_transaction
FROM
    datalake_retsuko_clean.entry e
LEFT JOIN
    datalake_retsuko_clean.account AS af
        ON e.id_from_account = af.id
LEFT JOIN
    datalake_retsuko_clean.account AS at
        ON e.id_to_account = at.id
LEFT JOIN
    datalake_retsuko_clean.contract c
        ON c.id = e.id_contract
