SELECT
    id_rent_flow_type AS sk_rent_flow_type,
    country_code,
    first_touchpoint,
    status,
    is_step_rejected,
    has_visit_flow,
    has_offer_flow,
    has_tta_flow,
    had_contract_signed,
    NOW() AS ts_load
FROM
    datalake_rent_flows.rent_flows_types
