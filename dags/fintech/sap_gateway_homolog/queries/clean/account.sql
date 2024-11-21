SELECT
    id                          AS id_account,
    code                        AS account_code,
    `description`               AS account_description,
    cfop_code,
    managerial_center,
    created_at                  AS ts_created,
    updated_at                  AS ts_updated
FROM
    datalake_sap_gateway_homolog_raw.account
