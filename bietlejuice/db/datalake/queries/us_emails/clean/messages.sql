SELECT
    _id AS id,
    emailid AS id_email,
    messageid AS id_message,
    messagedetails AS message_details,
    status,
    __v AS version,
    created AS created_date_object,
    year,
    month,
    day
FROM
    datalake_us_emails_raw.messages
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
