SELECT
    id                  AS id_rule,
    `name`              AS rule_name,
    `type`,
    person_type,
    cost_center,
    business_place,
    sequence_code,
    active              AS is_active,
    credit_person       AS is_credit_person,
    debit_person        AS is_debit_person,
    send_invoice        AS has_send_invoice,
    created_at          AS ts_created,
    updated_at          AS ts_updated
FROM
    datalake_sap_gateway_homolog_raw.rule
