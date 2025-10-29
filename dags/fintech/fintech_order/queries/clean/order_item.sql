SELECT
    id,
    order_id AS id_order,
    amount,
    metadata,
    from_actor_account_name,
    to_actor_account_name,
    accrual_date AS dt_accrual,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
  datalake_fintech_order_raw.order_item
