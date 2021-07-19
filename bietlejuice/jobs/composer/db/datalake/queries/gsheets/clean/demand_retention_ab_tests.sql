SELECT
    CAST(id_user AS INT) AS id_user,
    media,
    context,
    group,
    CAST(dt_import AS DATE) AS dt_import
FROM
    datalake_gsheets_raw.demand_retention_ab_tests
