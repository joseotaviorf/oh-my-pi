SELECT
    CAST(sk_user AS INTEGER) AS sk_user,
    affiliate_volumetry,
    DATE(start_date) AS start_date
FROM
    datalake_gsheets_raw.affiliate_volumetry_cluster
