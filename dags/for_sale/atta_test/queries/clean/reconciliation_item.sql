SELECT
    id AS id_reconciliation,
    proposta_id AS id_proposal,
    closing_id AS id_closing,
    closing_file_id AS id_closing_file,
    proposal_bank_id AS id_bank_proposal,
    buyer_document,
    buyer_name,
    financial_value,
    bank AS bank_code,
    status,
    modality,
    proposal_product AS operation_type,
    term AS operation_term,
    modified_fields,
    validations,
    observation,
    sign_date AS dt_signed
FROM
    datalake_atta_test_raw.reconciliation_item
