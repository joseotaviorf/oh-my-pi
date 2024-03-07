SELECT
    `id` AS id_business_unit,
    name,
    negotiation_type,
    created_at AS ts_created
FROM
    datalake_nazare_raw.business_unit
