SELECT
    id_rule_city_group,
    city_group,
    FLOAT(share) AS share
FROM
    datalake_gsheets_raw.marketing_offline_manual_share_city_group