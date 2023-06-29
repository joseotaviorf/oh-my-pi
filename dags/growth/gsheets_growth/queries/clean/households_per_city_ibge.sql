SELECT
    NULLIF(cities, '') AS cities,
    NULLIF(state_UF, '') AS state_UF,
    NULLIF(state_name, '') AS state_name,
    NULLIF(microregion_name, '') AS microregion_name,
    NULLIF(territory_planning, '') AS territory_planning,
    NULLIF(city_group, '') AS city_group,
    CAST(households AS INTEGER) AS households
FROM
    datalake_gsheets_raw.households_per_city_ibge
