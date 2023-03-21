SELECT
    id_occurrence AS sk_occurrence,
    id_propose AS sk_propose,
    id_payment AS sk_payment,
    id_client AS sk_client,
    id_occurrence_type AS sk_occurrence_type,
    id_occurrence_status AS sk_occurrence_status,
    id_unicid,
    description,
    invoice_url,
    due_amount,
    due_amount_original,
    paid_amount,
    is_valid,
    dt_due,
    ts_paid,
    ts_created,
    NOW() AS ts_load
FROM
    datalake_velo.occurrence
