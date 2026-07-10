SELECT
    id,
    partner_tier_id AS id_partner_tier,
    replaced_by AS id_replaced_by,
    author,
    reason,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.partner_tier_overwritten_info
