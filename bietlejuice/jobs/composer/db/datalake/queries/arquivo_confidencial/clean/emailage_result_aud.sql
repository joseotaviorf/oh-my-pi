SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    email,
    score,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.emailage_result_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}