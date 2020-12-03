SELECT
    id,
    contract_id AS id_contract,
    installment_option_id AS id_installment_option,
    installment_option_mod AS mod_id_installment_option,
    rev,
    revtype AS rev_type,
    status,
    status_mod AS mod_status,
    months_anticipated_number AS months_anticipated,
    months_anticipated_number_mod AS mod_months_anticipated,
    installment_value,
    partner_commission,
    total_amount,
    total_amount_mod AS mod_total_amount,
    total_rent,
    total_rent_mod AS mod_total_rent,
    paid_at AS ts_paid
FROM
    datalake_fastforward_raw.long_term_anticipation_aud
