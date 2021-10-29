SELECT
    NULLIF(cities, '') AS cities,
    NULLIF(state_UF, '') AS state_UF,
    NULLIF(state_name, '') AS state_name,
    NULLIF(microregion_name, '') AS microregion_name,
    CAST(households AS INTEGER) AS households
FROM
    datalake_gsheets_raw.households_per_city_ibge
