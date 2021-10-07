SELECT
     CAST(id_user_cm AS BIGINT) AS id_user_cm,
     CAST(id_user_5a AS BIGINT) AS id_user_5a,
     secretariat_name,
     email_5a AS email,
     allocation,
     status,
     manager,
     TO_DATE(dt_started, 'dd/mm/yyyy') AS dt_started
FROM
    datalake_gsheets_raw.secretariat_hierarchy


