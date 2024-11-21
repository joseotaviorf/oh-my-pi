SELECT
    id,
    consolidated_journal_entry_id   AS id_consolidated_journal_entry,
    branch_id                       AS id_branch,
    account_code,
    costing_code,
    location_code,
    operation_type,
    accounting_rule,
    amount,
    created_at                      AS ts_created,
    updated_at                      AS ts_updated
FROM
    datalake_sap_gateway_homolog_raw.consolidated_journal_entry_lines
