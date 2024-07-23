SELECT
    id_creditor,
    id_customer,
    id_product,
    id_contract,
    id_contact,
    name,
    document,
    brazilian_identity_card,
    brazilian_identity_card_issuing_federal_unit,
    father_name,
    mother_name,
    address,
    address_number,
    neighborhood,
    city,
    state,
    zip_code,
    address_add_on,
    comments,
    spouse_name,
    contact_type_code,
    CASE
        WHEN is_contact_active = "S" THEN True
        ELSE False
    END AS is_contact_active,
    DATE(dt_contact_birth) AS dt_contact_birth,
    ts_load
FROM
    datalake_recupera_homolog_raw.guarantor_contracts
