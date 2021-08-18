SELECT 
    id,
    house_external_id AS id_house_external,
    installments_quantity,
    sale_price_amount,
    financing_amount,
    entry_amount,
    amortization_type,
    house_uf,
    house_condition,
    house_type,
    fgts_amount,
    itbi_amount,
    valuation_amount,
    include_fees AS has_included_fees,
    include_valuation_fee AS has_included_valuation_fee,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_risk_and_mortgage_raw.financing_options
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
