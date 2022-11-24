SELECT
    NULLIF(cluster, '') AS cluster,
    NULLIF(microregion, '') AS microregion,
    NULLIF(state, '') AS state_uf,
    NULLIF(macroregion, '') AS macroregion,
    NULLIF(city_group, '') AS city_group,
    CAST(NULLIF(vacant_residential_units, '') AS FLOAT) AS vacant_residential_units,
    CAST(NULLIF(available_tenants, '') AS FLOAT) AS available_tenants,
    NULLIF(year, '') AS dt_year
FROM
    datalake_gsheets_raw.marketshare_units_and_tenants
