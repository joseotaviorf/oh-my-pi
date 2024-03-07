SELECT
    `id` AS id_offer,
    external_id AS id_external,
    business_unit_id AS id_business_unit,
    house_id AS id_house,
    category,
    house_address,
    house_city,
    house_complement,
    house_neighborhood,
    house_number,
    house_zipcode,
    price_agreed,
    cancellation_reason,
    brokerage,
    signature_date AS dt_signature,
    payment_allowed_date AS dt_payment_allowed,
    cancellation_date AS dt_cancellation,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_nazare_raw.offer
