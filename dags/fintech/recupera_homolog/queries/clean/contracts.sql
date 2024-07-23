SELECT
    id_creditor,
    id_customer,
    id_product,
    id_contract,
    branch_code,
    branch_name,
    network_code,
    network_name,
    store_code,
    store_name,
    currency_code,
    sale_type,
    property_description,
    CASE
        WHEN contract_block = "S" THEN "Blocked"
        WHEN contract_block = "N" THEN "Not blocked"
        WHEN contract_block = "D" THEN "Unblocked"
        WHEN contract_block IS NULL THEN "Not blocked"
        ELSE contract_block
    END AS contract_block,
    address,
    neighborhood,
    city,
    state,
    zip_code,
    phone_number,
    contract_number,
    address_add_on,
    address_observation,
    billing_rule_code,
    CAST(installments_amount AS INT) AS installments_amount,
    CAST(purchase_total_amount AS FLOAT) AS purchase_total_amount,
    CAST(entry_amount AS FLOAT) AS entry_amount,
    CAST(contract_fee_amount AS FLOAT) AS contract_fee_amount,
    DATE(dt_contract_start) AS dt_contract_start,
    DATE(dt_oldest_contract_expiration) AS dt_oldest_contract_expiration,
    ts_load
FROM
    datalake_recupera_homolog_raw.contracts
