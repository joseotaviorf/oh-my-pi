SELECT
    id AS id_repair_request_mediation_discount,
    repair_request_mediation_id AS id_repair_request_mediation,
    repair_request_id AS id_repair_request,
    uuid,
    scope,
    reason,
    discount_currency,
    discount_amount,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.repair_request_mediation_discount
