SELECT
    BIGINT(`id`) AS id_hub_bonus,
    revision,
    CAST(bonus_fee AS DECIMAL(38,20)) AS gross_advance,
    invalidated_at AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.hub_bonus_revision
