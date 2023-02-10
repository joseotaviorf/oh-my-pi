SELECT
    id_transaction_entry AS sk_transaction_entry,
    id_trasaction AS sk_transaction,
    id_category AS sk_category,
    id_propose AS sk_propose,
    id_bank_account AS sk_bank_account,
    id_omie_client AS sk_omie_client,
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
