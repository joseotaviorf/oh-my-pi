SELECT
    id,
    installments_quantity,
    sale_price_amount,
    financing_amount,
    entry_amount,
    amortization_type,
    include_fees,
    include_valuation_fee,
    house_id AS id_house,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.mortgage_options
