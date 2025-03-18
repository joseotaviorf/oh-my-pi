SELECT
    id,
    contract_id AS id_contract,
    action_main_user_id AS id_action_main_user,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    action_type,
    action_main_user_email,
    action_system,
    boleto_user_name AS invoice_user_name,
    boleto_user_document AS invoice_user_document,
    boleto_issuer_name AS invoice_issuer_name,
    boleto_issuer_document AS invoice_issuer_document,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_condominium_payments_test_raw.condo_monitoring_actions_aud
