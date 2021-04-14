SELECT
    NULLIF(id_rule_city_group, '') AS id_rule_city_group,
    NULLIF(city_group, '') AS city_group,
    FLOAT(NULLIF(share, '')) AS share
FROM
    datalake_gsheets_raw.marketing_offline_manual_share_city_group