SELECT
    id,
    accounting_entry_id AS id_accounting_entry,
    reason,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_robin_hood_raw.accounting_entry_recon_removals
