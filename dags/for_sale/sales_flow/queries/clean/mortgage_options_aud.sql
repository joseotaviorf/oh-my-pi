SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    installments_quantity,
    sale_price_amount,
    financing_amount,
    entry_amount,
    amortization_type,
    include_fees,
    include_valuation_fee,
    house_id AS id_house,
    house_id_mod AS mod_id_house,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.mortgage_options_aud
