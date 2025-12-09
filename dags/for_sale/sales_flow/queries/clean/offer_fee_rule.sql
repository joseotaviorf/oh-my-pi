SELECT
    id,
    listing_fee_id AS id_listing_fee,
    business_model,
    payment_model,
    valid_from AS ts_valid_from,
    valid_to AS ts_valid_to,
    min_fee,
    max_fee,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.offer_fee_rule

