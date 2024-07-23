SELECT
    id,
    value,
    created_at as ts_created,
    updated_at as ts_updated,
    started_at as ts_started,
    finished_at as ts_finished
FROM
    datalake_fastforward_homolog_raw.anticipation_fee
