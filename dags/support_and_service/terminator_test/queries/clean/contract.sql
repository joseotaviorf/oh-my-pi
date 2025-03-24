SELECT
    id,
    condominium_payer,
    start_date AS dt_start,
    rent_value,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_test_raw.contract
