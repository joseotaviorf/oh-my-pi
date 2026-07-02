-- Tab Link arquivo — datalake_gsheets_raw.qproposta_link_generator (headers normalized to snake_case).

SELECT
    TRIM(sk_offer) AS sk_offer,
    TRY_CAST(LOWER(TRIM(has_idactum)) AS BOOLEAN) AS has_idactum,
    TRIM(number) AS number,
    TRIM(link_pdf) AS link_pdf,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.qproposta_link_generator

-- redeploy trigger
