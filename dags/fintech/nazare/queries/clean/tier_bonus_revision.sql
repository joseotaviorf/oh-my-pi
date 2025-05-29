SELECT
    BIGINT(`id`) AS id_tier_bonus,
    revision,
    name,
    CAST(bonus_fee AS DECIMAL(38,20)) AS bonus_fee,
    CAST(baseline_fee AS DECIMAL(38,20)) AS baseline_fee,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.tier_bonus_revision
