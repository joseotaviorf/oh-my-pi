-----------------
-- Sale Flow

SELECT
    id_buyer AS id_user,
    id_house,
    MIN(ts_first_visit_completed) AS ts_visit_completed,
    MIN(ts_first_offer_submitted) AS ts_offer,
    MIN(dt_sale_agreement_signed) AS ts_contract_signed
FROM datalake_sale_flows.sale_flow
WHERE
    ts_first_event BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    AND id_buyer IS NOT NULL
    AND id_house IS NOT NULL
GROUP BY
    id_buyer,
    id_house

