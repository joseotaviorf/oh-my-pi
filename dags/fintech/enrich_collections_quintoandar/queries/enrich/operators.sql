WITH
union_all_sources AS (
    SELECT
        UPPER(id_operator) AS id_operator,
        NULL AS id_agency,
        NULL AS user_name,
        LOWER(operator_login_code) AS user_email,
        'Interno' AS user_type,
        NULL AS user_department,
        NULL AS agency_type,
        'COBRANÇA_INTERNA_QA' AS agency_name,
        CASE
          WHEN UPPER(id_operator_registration) = "PASCHOAL" THEN "PASCHOALOTTO"
          WHEN UPPER(id_operator_registration) LIKE "%PORTAL%" THEN "PORTAL_QUINTOANDAR"
          WHEN LOWER(operator_login_code) LIKE "%@quintoandar.com.br" THEN "COBRANÇA_INTERNA_QA"
          WHEN UPPER(id_operator_registration) = "QUINTO" THEN "COBRANÇA_INTERNA_QA"
          WHEN LOWER(operator_login_code) LIKE "%@sysopen.com.br" THEN "SYSOPEN"
          WHEN UPPER(id_operator_registration) LIKE "SERASA%" THEN "SERASA"
          ELSE UPPER(id_operator_registration)
        END AS company_name,
        'Recupera' source,
        2 AS priority,
        ts_operator_inclusion AS ts_user_created
    FROM
        datalake_recupera_clean.operators

    UNION ALL

    SELECT DISTINCT
        CONCAT('PASC_',UPPER(login_name)) AS id_operator,
        '010' AS id_agency,
        UPPER(full_name) AS user_name,
        LOWER(email) AS user_email,
        'Externo'  AS user_type,
        'Assessoria' AS user_department,
        'Assessoria Convencional' AS agency_type,
        'PASCHOALOTTO' AS agency_name,
        'PASCHOALOTTO' AS company_name,
        'Paschoalotto' source,
        3 AS priority,
        NULL AS ts_user_created
    FROM datalake_paschoalotto_clean.user

    UNION ALL

    SELECT
        id_login AS id_operator,
        '011' AS id_agency,
        UPPER(person_name) AS user_name,
        LOWER(email) AS user_email,
        'Externo'  AS user_type,
        'Assessoria' AS user_department,
        'Assessoria Convencional' AS agency_type,
        'WEBHELP' AS agency_name,
        'WEBHELP' AS company_name,
        'Webhelp' source,
        3 AS priority,
        NULL AS ts_user_created
    FROM
        datalake_webhelp_clean.login
    WHERE
        context = "COBRANCA"

    UNION ALL

    SELECT DISTINCT
        id_user AS id_operator,
        CAST(id_agency AS STRING) AS id_agency,
        user_name,
        user_email,
        user_type,
        user_department,
        agency_type,
        agency_name,
        company_name,
        'Cyber' source,
        1 AS priority,
        ts_user_created
    FROM datalake_cyber.users

    UNION ALL

    SELECT DISTINCT
        UPPER(id_operator_cyber) AS id_operator,
        '018' AS id_agency,
        UPPER(name) AS user_name,
        LOWER(email) AS user_email,
        'Externo'  AS user_type,
        'Assessoria' AS user_department,
        'Assessoria Convencional' AS agency_type,
        'GRB' AS agency_name,
        'GRB' AS company_name,
        'GRB' source,
        3 AS priority,
        TIMESTAMP(dt_admission) AS ts_user_created
    FROM datalake_grb_clean.operators

    UNION ALL

    SELECT DISTINCT
        CASE
            WHEN TRY_CAST(id_operator_cyber AS INT) IS NOT NULL
                THEN CONCAT('MTC_', LPAD(CAST(id_operator_cyber AS STRING), 4, '0'))
            ELSE UPPER(id_operator_cyber)
        END AS id_operator,
        '019' AS id_agency,
        UPPER(name) AS user_name,
        LOWER(email) AS user_email,
        'Externo'  AS user_type,
        'Assessoria' AS user_department,
        'Assessoria Convencional' AS agency_type,
        'MEETCALL' AS agency_name,
        'MEETCALL' AS company_name,
        'MeetCall' source,
        3 AS priority,
        TIMESTAMP(dt_admission) AS ts_user_created
    FROM datalake_meetcall_clean.operators
)
SELECT DISTINCT
    id_operator,
    id_agency,
    user_name,
    user_email,
    user_type,
    user_department,
    agency_type,
    agency_name,
    company_name,
    source,
    ts_user_created,
    NOW() AS ts_load
FROM union_all_sources
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_operator, company_name ORDER BY priority, ts_user_created DESC) = 1
