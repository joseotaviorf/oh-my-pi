SELECT
    id_transaction_entry AS sk_transaction_entry,
    COALESCE(id_trasaction, -1) AS sk_transaction,
    COALESCE(id_category, -1) AS sk_category,
    id_propose AS sk_propose,
    COALESCE(id_bank_account, -1) AS sk_bank_account,
    COALESCE(id_omie_client, -1) AS sk_omie_client,
    percent_amount_from_transaction,
    due_amount,
    paid_amount,
    is_occurency,
    dt_issue,
    dt_register,
    dt_due,
    dt_paid,
    ts_created,
    ts_modified,
    NOW() AS ts_load
FROM
    datalake_velo.transaction_entries
