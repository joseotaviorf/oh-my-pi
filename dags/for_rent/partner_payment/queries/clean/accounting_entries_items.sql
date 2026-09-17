SELECT
    id,
    accounting_entry_id AS id_accounting_entry,
    source_id AS id_source,
    version,
    source,
    amount,
    currency,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.accounting_entries_items
