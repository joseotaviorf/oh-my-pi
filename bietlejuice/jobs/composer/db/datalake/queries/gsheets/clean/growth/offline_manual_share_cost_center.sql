SELECT
    NULLIF(id_rule_cost_center, '') AS id_rule_cost_center,
    NULLIF(cost_center, '') AS cost_center,
    CAST(NULLIF(REPLACE(share, ',', ''), '') AS DECIMAL(12,10)) AS share
FROM
    datalake_gsheets_raw.offline_manual_share_cost_center;
