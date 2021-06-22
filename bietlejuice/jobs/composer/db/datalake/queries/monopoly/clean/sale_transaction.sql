SELECT
    id,
    sale_id AS id_sale,
    event,
    description,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_monopoly_raw.sale_transaction