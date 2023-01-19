SELECT
    id,
    user_id AS id_user,
    title,
    summary,
    status,
    user_email
FROM
    datalake_saruman_raw.support_case
