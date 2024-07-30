SELECT
    id,
    contract_id AS id_contract,
    charge_delay_in_days,
    installment_number,
    CAST(fee AS FLOAT) AS brokerage_fee,
    CAST(premium_fee AS FLOAT) AS premium_fee,
    CAST(down_payment AS FLOAT) AS down_payment,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_fees_homolog_raw.contract_brokerage_fee
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
