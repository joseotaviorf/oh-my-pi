SELECT
    id,
    contract_id AS id_contract,
    installment_option_id AS id_installment_option,
    quota_id AS id_quota,
    operation_id AS id_operation,
    months_anticipated_number AS months_anticipated,
    investment_source,
    status,
    status_reason,
    installment_value,
    partner_commission,
    total_amount,
    total_rent,
    ccb_code,
    ccb_url,
    iof_amount,
    created_at AS ts_created,
    updated_at AS ts_updated,
    paid_at AS ts_paid,
    signed_at AS ts_signed,
    first_installment_date AS dt_first_installment
FROM
    datalake_fastforward_raw.long_term_anticipation
