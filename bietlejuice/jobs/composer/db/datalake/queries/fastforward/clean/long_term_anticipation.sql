SELECT
    id,
    contract_id AS id_contract,
    installment_option_id AS id_installment_option,
    months_anticipated_number AS months_anticipated,
    status,
    installment_value,
    partner_commission,
    total_amount,
    total_rent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    paid_at AS ts_paid
FROM
    datalake_fastforward_raw.long_term_anticipation
