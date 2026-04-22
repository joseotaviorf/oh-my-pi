SELECT
    id,
    recurring_expense_id AS id_recurring_expense,
    recurring_expense_external_id AS id_recurring_expense_external,
    entry_external_id AS id_entry_external,
    timestamp(published_at) AS ts_published,
    timestamp(retsuko_created_at) AS ts_retsuko_created,
    timestamp(retsuko_updated_at) AS ts_retsuko_updated
FROM
    datalake_retsuko_raw.recurring_expense_entry
