SELECT
    id,
    company_id AS id_company,
    draft,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    company_id_mod AS mod_id_company,
    draft_mod AS mod_draft,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.company_draft_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}