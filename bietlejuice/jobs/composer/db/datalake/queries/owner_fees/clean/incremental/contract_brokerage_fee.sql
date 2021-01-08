SELECT
    id,
    contract_id AS id_contract,
    charge_delay_in_days,
    installment_number,
    premium_fee,
    fee AS brokerage_fee,
    down_payment,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_owner_fees_raw.contract_brokerage_fee
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
