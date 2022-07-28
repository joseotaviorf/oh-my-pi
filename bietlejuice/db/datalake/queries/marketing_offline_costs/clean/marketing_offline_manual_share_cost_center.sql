SELECT
    NULLIF(id_rule_cost_center, '') AS id_rule_cost_center,
    NULLIF(cost_center, '') AS cost_center,
    FLOAT(NULLIF(share, '')) AS share
FROM
    datalake_marketing_offline_costs_raw.marketing_offline_manual_share_cost_center