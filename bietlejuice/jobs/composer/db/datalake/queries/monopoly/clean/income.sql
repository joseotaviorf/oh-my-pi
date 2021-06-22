SELECT
    id,
    person_sale_id AS id_person_sale,
    invoice_id AS id_invoice,
    event,
    status,
    amount,
    created_at AS ts_created
FROM
    datalake_monopoly_raw.income