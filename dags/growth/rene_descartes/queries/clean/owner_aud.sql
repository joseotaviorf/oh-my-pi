SELECT
    id,
    name,
    email,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    year,
    month,
    day
FROM
    datalake_rene_descartes_raw.owner_aud
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id, rev ORDER BY dt DESC) = 1