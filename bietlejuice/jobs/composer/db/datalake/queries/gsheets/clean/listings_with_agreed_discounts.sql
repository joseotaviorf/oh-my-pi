SELECT
    CAST(house_id AS INTEGER) AS id_house,
    discounted_fee,
    discount_mode,
    discount_reason,
    responsible_team,
    user_email,
    comments,
    CAST(fee_value AS FLOAT) AS fee_value,
    TO_DATE(dt_discount_registered, 'dd/MM/yyyy') AS dt_discount_registered
FROM
    datalake_gsheets_raw.listings_with_agreed_discounts