SELECT
    canceled_contracts AS id_canceled_contract,
    finished_contracts AS id_finished_contract,
    ongoing_contracts AS id_ongoing_contract
FROM 
    datalake_gsheets_raw.offboarding_customer_portfolio_contract