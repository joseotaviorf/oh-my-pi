SELECT
    id,
    id_property,
    status,
    type,
    forsale_type,
    client,
    category,
    bandaid_cause,
    CAST(amount as DECIMAL(8,4)) as amount,
    CAST(dt_created as DATE) as dt_created
FROM
    datalake_gsheets_raw.for_sale_bandaids