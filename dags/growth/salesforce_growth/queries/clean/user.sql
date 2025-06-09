SELECT
    Email AS email,
    Name AS name,
    Id AS id_user_salesforce,
    Title AS role,
    Department AS team,
    Division AS leadership,
    CreatedDate AS creation_date,
    LastLoginDate AS last_login_date,
    Pais__c AS country,
    Organizacion_de_venta__c AS operation,
    dt_updated,
    year,
    month,
    day
FROM
    datalake_salesforce_growth_raw.user
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')