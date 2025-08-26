SELECT 
    id,
    uuid,
    external_segment_id AS id_external_segment,
    external_product_id AS id_external_product,
    external_sale_plan_id AS id_external_sale_plan,
    external_group_id AS id_external_group,
    name,
    administrative_fee,
    reserve_fund_fee,
    installment_value,
    sale_plan_contemplation,
    good_value,
    deadline_term,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_consorcio_raw.product 