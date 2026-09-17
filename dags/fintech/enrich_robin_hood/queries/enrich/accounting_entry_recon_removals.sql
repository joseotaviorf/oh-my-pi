-- One row per accounting entry flagged by the Fintech backoffice to be ignored in reconciliation,
-- enriched with the attributes of the excluded accounting entry.
SELECT
    recon_removal.id AS id_recon_removal,
    recon_removal.id_accounting_entry,
    accounting_entry.id_external,
    accounting_entry.id_source,
    accounting_entry.id_payee,
    accounting_entry.id_context,
    recon_removal.reason AS recon_removal_reason,
    accounting_entry.requested_by,
    accounting_entry.description,
    accounting_entry.source_bill_item,
    accounting_entry.locale,
    accounting_entry.type,
    accounting_entry.cost_center_code,
    accounting_entry.accrual_year_month,
    accounting_entry.accounting_year_month,
    recon_removal.op_cdc AS recon_removal_op_cdc,
    accounting_entry.op_cdc AS accounting_entry_op_cdc,
    accounting_entry.due_amount,
    accounting_entry.dt_occurrence,
    recon_removal.ts_created AS ts_recon_removal_created,
    recon_removal.ts_cdc_transaction AS ts_recon_removal_cdc_transaction,
    recon_removal.ts_database_transaction AS ts_recon_removal_database_transaction,
    accounting_entry.ts_synced AS ts_accounting_entry_synced,
    accounting_entry.ts_blocked AS ts_accounting_entry_blocked,
    accounting_entry.ts_created AS ts_accounting_entry_created,
    accounting_entry.ts_cdc_transaction AS ts_accounting_entry_cdc_transaction,
    accounting_entry.ts_database_transaction AS ts_accounting_entry_database_transaction,
    accounting_entry.metadata AS accounting_entry_metadata
FROM
    datalake_robin_hood_clean.accounting_entry_recon_removals AS recon_removal
INNER JOIN
    datalake_robin_hood_clean.accounting_entry AS accounting_entry
        ON recon_removal.id_accounting_entry = accounting_entry.id
