SELECT
    _id AS id,
    smartemailid AS id_smart_email,
    reason,
    disabled,
    data_required
FROM
    datalake_us_emails_raw.reasons