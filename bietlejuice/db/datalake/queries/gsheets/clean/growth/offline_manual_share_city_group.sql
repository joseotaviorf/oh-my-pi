SELECT
    NULLIF(id_rule_city_group, '') AS id_rule_city_group,
    NULLIF(city_group, '') AS city_group,
    CAST(NULLIF(REPLACE(share, ',', ''), '') AS DECIMAL(12,10)) AS share
FROM
    datalake_gsheets_raw.offline_manual_share_city_group;
