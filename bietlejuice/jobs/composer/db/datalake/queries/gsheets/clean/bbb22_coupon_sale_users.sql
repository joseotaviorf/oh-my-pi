SELECT
    CAST(sk_user AS INTEGER) AS id_user,
    CAST(ts_coupon_expired AS TIMESTAMP) AS ts_coupon_expired
FROM
    datalake_gsheets_raw.bbb22_coupon_for_sale