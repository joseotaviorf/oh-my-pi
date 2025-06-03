SELECT
    BIGINT(`id`) AS id_offer,
    external_id AS id_external,
    BIGINT(business_unit_id) AS id_business_unit,
    BIGINT(house_id) AS id_house,
    category,
    house_address,
    house_city,
    house_complement,
    house_neighborhood,
    house_number,
    house_zipcode,
    price_agreed,
    cancellation_reason,
    CAST(brokerage AS DECIMAL(38,20)) AS brokerage,
    DATE(signature_date) AS dt_signature,
    DATE(payment_allowed_date) AS dt_payment_allowed,
    DATE(cancellation_date) AS dt_cancellation,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_nazare_raw.offer
