SELECT
    id,
    contract_id AS id_contract,
    charge_delay_in_days,
    installment_number,
    CAST(fee AS FLOAT) AS brokerage_fee,
    CAST(premium_fee AS FLOAT) AS premium_fee,
    CAST(down_payment AS FLOAT) AS down_payment,
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
