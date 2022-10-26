SELECT
    id AS id_onboarding_aud,
    sales_flow_id AS id_sales_flow,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    deposit_buyer,
    documentation_buyer,
    documentation_seller,
    documentation_house,
    deposit_sent,
    status,
    sales_flow_id_mod AS mod_id_sales_flow,
    deposit_buyer_mod AS mod_deposit_buyer,
    documentation_buyer_mod AS mod_documentation_buyer,
    documentation_seller_mod AS mod_documentation_seller,
    documentation_house_mod AS mod_documentation_house,
    deposit_sent_mod AS mod_deposit_sent,
    status_mod AS mod_status,
    end_date_mod AS mod_dt_ended,
    end_date AS dt_ended,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.onboarding_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}