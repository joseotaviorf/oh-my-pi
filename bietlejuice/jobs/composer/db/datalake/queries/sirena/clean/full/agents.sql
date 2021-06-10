SELECT
    id,
    group AS id_group,
    firstName AS first_name,
    lastName AS last_name,
    phone,
    email,
    appFields AS app_fields
FROM
    datalake_sirena_raw.agents