SELECT
    id,
    journal_entry_id            AS id_journal_entry,
    finance_entity_entry_id     AS id_finance_entity_entry,
    person_id                   AS id_person,
    branch_id                   AS id_branch,
    account_code,
    costing_code,
    location_code,
    accounting_rule,
    operation_type,
    amount,
    created_at                  AS ts_created,
    updated_at                  AS ts_updated
FROM
    datalake_sap_gateway_homolog_raw.journal_entry_lines
