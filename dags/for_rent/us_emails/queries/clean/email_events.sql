SELECT
    _id AS id,
    emailid AS id_email,
    emailreason AS email_reason,
    description,
    status,
    type,
    __v AS version,
    created AS created_date_object,
    year,
    month,
    day
FROM
    datalake_us_emails_raw.emailevents
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
