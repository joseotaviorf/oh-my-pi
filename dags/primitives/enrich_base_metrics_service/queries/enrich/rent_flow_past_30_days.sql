-----------------
-- Rent Flow

SELECT
    id_tenant_prospect as id_user,
    id_house,
    MIN(ts_visit_completed) AS ts_visit_completed,
    MIN(coalesce(ts_direct_offer_submitted, ts_offer_submitted)) AS ts_offer,
    MIN(ts_contract_signed) AS ts_contract_signed,
    MIN(ts_direct_offer_submitted) AS ts_direct_offer,
    MIN(ts_offer_submitted) AS ts_offer_submitted
FROM
    datalake_rent_flows.rent_flows
WHERE
    ts_rent_flow_event BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    AND id_tenant_prospect IS NOT NULL
    AND id_house IS NOT NULL
GROUP BY
    id_tenant_prospect,
    id_house

