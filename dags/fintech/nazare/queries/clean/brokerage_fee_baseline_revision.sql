SELECT
    BIGINT(`id`) AS id_brokerage_fee_baseline,
    revision,
    CAST(bonus_fee AS DECIMAL(38,20)) AS gross_advance,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.brokerage_fee_baseline_revision
