SELECT
    `id` AS id_hub_bonus,
    revision,
    bonus_fee AS gross_advance,
    invalidated_at AS ts_invalidated,
    created_at AS ts_created
FROM
    datalake_nazare_raw.hub_bonus_revision
