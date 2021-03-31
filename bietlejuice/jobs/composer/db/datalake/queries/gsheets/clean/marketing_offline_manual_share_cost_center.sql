SELECT
    NULLIF(id_rule_cost_center, '') AS id_rule_cost_center,
    NULLIF(cost_center, '') AS cost_center,
    NULLIF(cost_center_context, '') AS cost_center_context,
    FLOAT(NULLIF(share, '')) AS share
FROM
    datalake_gsheets_raw.marketing_offline_manual_share_cost_center