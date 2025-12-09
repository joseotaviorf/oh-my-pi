SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    region_id AS id_region,
    ticket_model,
    valid_from AS ts_valid_from,
    valid_to AS ts_valid_to,
    fee,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.listing_fee_aud

