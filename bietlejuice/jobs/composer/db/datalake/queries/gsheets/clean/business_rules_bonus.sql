SELECT
    service_line,
    offer_flow,
    partner_type,
    CAST(brokerage_fee_partner AS FLOAT) AS brokerage_fee_partner,
    CAST(dt_started AS DATE) AS dt_started,
    CAST(dt_ended AS DATE) AS  dt_ended
FROM
    datalake_gsheets_raw.business_rules_bonus
