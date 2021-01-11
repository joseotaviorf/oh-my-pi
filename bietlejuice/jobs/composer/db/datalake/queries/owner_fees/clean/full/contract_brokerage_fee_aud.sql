SELECT
    id AS id_contract_brokeragee_fee,
    contract_id,
    charge_delay_in_days,
    installment_number,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    CAST(fee AS FLOAT) AS brokerage_fee,
    CAST(premium_fee AS FLOAT) AS premium_fee,
    CAST(down_payment AS FLOAT) AS down_payment,
    installment_number_mod AS mod_installment_number,
    premium_fee_mod AS mod_premium_fee
FROM 
    datalake_owner_fees_raw.contract_brokerage_fee_aud
