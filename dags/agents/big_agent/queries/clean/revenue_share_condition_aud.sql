SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    revenue_share_id AS id_revenue_share,
    condition_type,
    value,
    revenue_share_id_mod AS mod_id_revenue_share,
    condition_type_mod AS mod_condition_type,
    value_mod AS mod_value,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.revenue_share_condition_aud
