SELECT
    id_rule_cost_center,
    cost_center,
    FLOAT(share) AS share
FROM
    datalake_gsheets_raw.marketing_offline_manual_share_cost_center