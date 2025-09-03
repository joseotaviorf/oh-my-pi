SELECT
    id,
    contract_id AS id_contract,
    bar_code,
    beneficiary_name,
    beneficiary_doc,
    beneficiary_doc_type,
    landlord_name,
    landlord_doc,
    landlord_doc_type,
    type,
    status,
    digitable_line,
    version,
    updated_amount,
    original_amount,
    fine,
    interest,
    discount,
    due_date AS dt_due
FROM
    datalake_rental_management_raw.third_party_bills
