SELECT
    id,
    person_sale_id AS id_person_sale,
    invoice_id AS id_invoice,
    event,
    status,
    CAST(amount AS float) AS amount,
    payer_info,
    invoice_link,
    due_date AS dt_due,
    expiration_date AS dt_expiration,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_monopoly_raw.income