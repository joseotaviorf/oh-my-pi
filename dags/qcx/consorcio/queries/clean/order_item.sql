SELECT 
    id,
    uuid,
    order_id AS id_order,
    external_segment_id AS id_external_segment,
    name,
    external_product_id AS id_external_product,
    external_sale_plan_id AS id_external_sale_plan,
    external_group_id AS id_external_group,
    administrative_fee,
    reserve_fund_fee,
    installment_value,
    sale_plan_contemplation,
    good_value,
    deadline_term,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_consorcio_raw.order_item 