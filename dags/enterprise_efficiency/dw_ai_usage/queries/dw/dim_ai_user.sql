WITH ai_users AS (
    SELECT DISTINCT
        tool,
        id_user,
        email_user
    FROM
        datalake_ai_usage.usage_daily
    UNION
    SELECT DISTINCT
        tool,
        id_user,
        email_user
    FROM
        datalake_ai_usage.spend_daily
),
identifier_mapping_ranked AS (
    SELECT
        LOWER(TRIM(im.work_email)) AS work_email,
        im.id_person,
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(TRIM(im.work_email))
            ORDER BY
                im.is_active DESC,
                im.dt_started DESC
        ) AS rn_email
    FROM
        datalake_people.identifier_mapping AS im
    WHERE
        im.is_valid_assignment
),
identifier_mapping_by_email AS (
    SELECT
        work_email,
        id_person
    FROM
        identifier_mapping_ranked
    WHERE
        rn_email = 1
)
SELECT
    MD5(CONCAT_WS(',', ai_users.tool, ai_users.id_user)) AS sk_ai_user,
    ai_users.tool,
    ai_users.id_user,
    ai_users.email_user,
    im.id_person AS sk_employee
FROM
    ai_users
LEFT JOIN
    identifier_mapping_by_email AS im
        ON LOWER(TRIM(ai_users.email_user)) = im.work_email
