SELECT
    BIGINT(`id`) AS id_associate_executive_bonus,
    revision,
    CAST(bonus_fee AS DECIMAL(38,20)) AS gross_advance,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.associate_executive_bonus_revision
