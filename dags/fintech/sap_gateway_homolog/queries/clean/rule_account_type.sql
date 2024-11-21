SELECT
    rule_id     AS id_rule,
    account_id  AS id_account,
    `type`
FROM
    datalake_sap_gateway_homolog_raw.rule_account_type
