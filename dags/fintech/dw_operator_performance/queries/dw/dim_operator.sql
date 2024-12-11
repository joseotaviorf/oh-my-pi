WITH
union_advisories AS (
    SELECT
        id_user AS id_operator,
        UPPER(login_name) login,
        UPPER(full_name) AS full_name,
        LOWER(email) AS email,
        NULL AS is_active,
        "PASCHOALOTTO" AS company,
        ts_load AS ts_updated
    FROM
        datalake_paschoalotto_clean.user
    QUALIFY ROW_NUMBER() OVER(PARTITION BY login_name ORDER BY IF(email IN ("_","-","","N"), NULL, email) DESC) = 1

    UNION ALL

    SELECT
        md5(CONCAT(id_operator, ts_operator_registration_update)) AS id_operator,
        id_operator AS login,
        NULL AS full_name,
        LOWER(operator_login_code) AS email,
        CASE
        WHEN is_active = "N" THEN FALSE
        WHEN is_active = "S" THEN TRUE
        ELSE NULL
        END AS is_active,
        "QUINTOANDAR" AS company,
        ts_operator_registration_update AS ts_updated
    FROM
        datalake_recupera_clean.operators
    WHERE
        UPPER(id_operator_registration) NOT IN ("IAF", "PASCHOAL", "WEBHELP")

    UNION ALL

    SELECT
        id AS id_operator,
        login,
        name AS full_name,
        LOWER(COALESCE(first_email,second_email)) AS email,
        CASE
        WHEN status = "INATIVO" THEN FALSE
        WHEN status = "ATIVO" THEN TRUE
        ELSE NULL
        END AS is_active,
        "IAF" AS company,
        ts_updated
    FROM
        datalake_iaf_clean.employee

    UNION ALL

    SELECT
        id_person AS id_operator,
        id_login AS login,
        person_name AS full_name,
        LOWER(email) AS email,
        NULL AS is_active,
        "WEBHELP" AS company,
        ts_load AS ts_updated
    FROM
        datalake_webhelp_clean.login
    WHERE
        context = "COBRANCA"
)

SELECT
    md5(CONCAT(company, login)) AS sk_operator,
    id_operator,
    company,
    login,
    full_name,
    email,
    is_active,
    ts_updated
FROM
    union_advisories
