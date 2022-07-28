SELECT
    id,
    account_id AS id_account,
    sale_transaction_id AS id_sale_transaction,
    person_type,
    type AS entry_type,
    credit,
    debit,
    created_at AS ts_created
FROM
    datalake_monopoly_raw.accounting_entry