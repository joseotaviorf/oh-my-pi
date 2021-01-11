SELECT
    id,
    contract_id AS id_contract,
    charge_delay_in_days,
    installment_number,
    CAST(fee AS DECIMAL(10,2)) AS brokerage_fee,
    CAST(premium_fee AS DECIMAL(10,2)) AS premium_fee,
    CAST(down_payment AS DECIMAL(10,2)) AS down_payment,
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
