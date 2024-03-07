SELECT
    `id` AS id_tier_bonus,
    partner_id AS id_partner,
    current_revision,
    DATE(category_start_date) AS dt_category_start,
    DATE(category_end_date) AS dt_category_end,
    created_at AS ts_created
FROM
    datalake_nazare_raw.tier_partner
