SELECT
    _id AS id,
    emailaddress AS email,
    reason,
    __v AS version,
    BOOLEAN(isactive) AS is_active,
    created AS created_date_object,
    updated AS updated_date_object,
    year,
    month,
    day
FROM
    datalake_us_emails_raw.unsubscriptions
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}