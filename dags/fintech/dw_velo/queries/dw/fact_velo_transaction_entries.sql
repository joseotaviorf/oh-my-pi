SELECT
    id_transaction_entry AS sk_transaction_entry,
    id_trasaction AS sk_transaction,
    id_category AS sk_category,
    id_propose AS sk_propose,
    id_bank_account AS sk_bank_account,
    id_omie_client AS sk_omie_client,
    category_percent_amount,
    category_due_amount,
    category_paid_amount,
    is_occurency,
    dt_issue,
    dt_register,
    dt_created,
    dt_modified,
    dt_due,
    dt_paid,
    NOW() AS ts_load
FROM
    datalake_velo.transaction_entries
