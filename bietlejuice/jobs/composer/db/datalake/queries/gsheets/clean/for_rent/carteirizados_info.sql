SELECT
    CAST(sk_client AS INTEGER) AS id_client,
    CAST(sk_proposal AS INTEGER) AS id_proposal,
    NULLIF(CAST(LEFT(name, 200) AS VARCHAR(255)), '') AS name,
    NULLIF(email, '') AS email,
    NULLIF(phone_number, '') AS phone_number,
    CAST(closing_group AS VARCHAR(255)) AS closing_group,
    TO_DATE(dt_inclusion, 'dd-MM-yyyy') AS dt_accreditation_week
FROM
    datalake_gsheets_raw.carteirizados_info
