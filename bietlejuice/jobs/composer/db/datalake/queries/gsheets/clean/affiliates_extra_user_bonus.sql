SELECT
    CAST(sk_user AS INTEGER) AS sk_user,
    business_context,
    city_group,
    CAST(bonus AS INTEGER) AS bonus,
    date
FROM
    datalake_gsheets_raw.affiliates_extra_user_bonus