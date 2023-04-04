SELECT
    id_occurrence AS sk_occurrence,
    id_propose AS sk_propose,
    id_payment AS sk_payment,
    COALESCE(id_client, -1) AS sk_client,
    COALESCE(id_occurrence_type, -1) AS sk_occurrence_type,
    COALESCE(id_occurrence_status, -1) AS sk_occurrence_status,
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
