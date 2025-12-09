SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    listing_fee_id AS id_listing_fee,
    business_model,
    business_model_mod AS mod_business_model,
    payment_model,
    payment_model_mod AS mod_payment_model,
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
    datalake_sales_flow_raw.offer_fee_rule_aud

