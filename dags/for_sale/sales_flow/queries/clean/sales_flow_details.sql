SELECT
    id,
    sales_flow_id AS id_sales_flow,
    taskmaster_id AS id_taskmaster,
    buyer_onboarding_taskmaster_id AS id_buyer_onboarding_taskmaster,
    seller_onboarding_taskmaster_id AS id_seller_onboarding_taskmaster,
    buyer_hefesto_portfolio_unit_id AS id_buyer_hefesto_portfolio_unit,
    seller_hefesto_portfolio_unit_id AS id_seller_hefesto_portfolio_unit,
    opportunities_of_the_week,
    isolve_link,
    google_drive_link,
    ticket_complexity_level,
    seller_fup_at AS ts_seller_fup,
    buyer_fup_at AS ts_buyer_fup,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow_details

