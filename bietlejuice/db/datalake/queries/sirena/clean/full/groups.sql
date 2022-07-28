SELECT
    id,
    parent,
    descendants,
    ancestors,
    name AS group_name,
    displayName AS display_name,
    type AS group_type,
    timezone,
    countryCode AS country_code
FROM
    datalake_sirena_raw.groups