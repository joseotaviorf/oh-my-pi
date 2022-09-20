SELECT
    `id` AS id_brokerage_fee_baseline,
    revision,
    bonus_fee AS gross_advance,
    invalidated_at AS ts_invalidated,
    created_at AS ts_created
FROM
    datalake_nazare_raw.brokerage_fee_baseline_revision
