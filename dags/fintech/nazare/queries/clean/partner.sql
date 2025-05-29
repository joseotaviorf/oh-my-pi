SELECT
    BIGINT(`id`) AS id_partner,
    full_name,
    short_name,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_nazare_raw.partner
