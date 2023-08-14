WITH types AS (
    SELECT DISTINCT
        country_code,
        first_touchpoint,
        status,
        is_step_rejected,
        has_visit_flow,
        has_offer_flow,
        has_tta_flow,
        IF(ts_contract_signed IS NOT NULL, TRUE, FALSE) AS had_contract_signed
    FROM
        datalake_rent_flows.rent_flows
)
SELECT
    MONOTONICALLY_INCREASING_ID() AS id_rent_flow_type,
    country_code,
    first_touchpoint,
    status,
    is_step_rejected,
    has_visit_flow,
    has_offer_flow,
    has_tta_flow,
    had_contract_signed
FROM
    types
