SELECT
    `id` AS id_tier_bonus,
    revision,
    baseline_fee,
    name,
    bonus_fee,
    invalidated_at AS ts_invalidated,
    created_at AS ts_created
FROM
    datalake_nazare_raw.tier_bonus_revision
