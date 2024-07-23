SELECT
    id,
    rev,
    revtype as rev_type,
    revend as rev_end,
    value,
    started_at as ts_started,
    finished_at as ts_finished
FROM
    datalake_fastforward_homolog_raw.anticipation_fee_aud
