SELECT 
    id,
    event_info_id AS id_event_info,
    ledger_transaction_id AS id_ledger_transaction,
    from_actor_id AS id_from_actor,
    to_actor_id AS id_to_actor,
    type,
    status,
    currency,
    metadata,
    from_actor_role,
    from_actor_account_name,
    to_actor_role,
    to_actor_account_name,
    due_date AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_fintech_order_raw.order
