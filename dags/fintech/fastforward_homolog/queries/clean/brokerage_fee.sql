SELECT
    id,
    number_of_rents as rents,
    created_at as ts_created,
    updated_at as ts_updated
FROM
    datalake_fastforward_homolog_raw.brokerage_fee
