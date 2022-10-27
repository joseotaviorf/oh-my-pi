SELECT
    document_id AS id_document,
    company_id AS id_company,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    document_id_mod AS mod_id_document,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_company_raw.company_document_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}