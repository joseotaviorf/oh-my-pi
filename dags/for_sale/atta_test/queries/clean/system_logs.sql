SELECT
    Id              AS id,
    UserId          AS id_user,
    ClientId        AS id_client,
    Topic           AS topic,
    Agent           AS agent,
    Content         AS content,
    IP              AS ip_number,
    Request         AS request,
    CreatedAt       AS ts_creation,
    year,
    month,
    day
FROM
    datalake_atta_test_raw.systemlogs
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
