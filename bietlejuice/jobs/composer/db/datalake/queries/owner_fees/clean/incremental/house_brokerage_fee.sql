SELECT
    id,
    house_id AS id_house,
    contract_id AS id_contract,
    charge_delay_in_days,
    installment_number,
    premium_fee,
    brokerage_fee,
    down_payment,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_owner_fees_raw.house_brokerage_fee
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
