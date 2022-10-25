SELECT
    _id AS id,
    templateid AS id_template,
    requestid AS id_request,
    to,
    cc,
    bcc,
    attachments,
    bodyParameters AS body_parameters,
    reason,
    status,
    rawData AS raw_data,
    __v AS version,
    created AS created_date_object,
    updated AS updated_date_object,
    year,
    month,
    day
FROM
    datalake_us_emails_raw.emails
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
