SELECT
    NULLIF(qualifies, '') AS qualifies,
    NULLIF(amount, '') AS amount,
    NULLIF(alo, '') AS alo,
    NULLIF(cpc, '') AS cpc
FROM
    datalake_gsheets_raw.quintocred_iaf_qualifies_calls
