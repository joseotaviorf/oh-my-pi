SELECT
    id AS id_house_brokerage_fee,
    house_id AS id_house,
    contract_id AS id_contract,
    charge_delay_in_days,
    installment_number,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    CAST(brokerage_fee AS DECIMAL(10,2)) AS brokerage_fee,
    CAST(premium_fee AS DECIMAL(10,2)) AS premium_fee,
    CAST(down_payment AS DECIMAL(10,2)) AS down_payment,
    installment_number_mod AS mod_installment_number,
    premium_fee_mod AS mod_premium_fee,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_owner_fees_raw.house_brokerage_fee_aud
