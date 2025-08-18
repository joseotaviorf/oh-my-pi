SELECT
    BIGINT(`id`) AS id,
    BIGINT(`offer_id`) AS id_offer,
    output,
    errors,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(exported_at) AS ts_exported
FROM
    datalake_nazare_raw.revenue_share_by_offer
