SELECT
    id,
    company_id AS id_company,
    requirements,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    requirements_mod AS mod_requirements,
    company_id_mod AS mod_id_company,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.user_requirements_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}