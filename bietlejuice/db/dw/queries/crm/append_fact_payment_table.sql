select
  sk_task,
  sk_receiver,
  sk_start_date,
  sk_completed_date,
  sk_origin,
  sk_assignee,
  action_user_name,
  sk_user_action,
  sk_action_date,
  dt_action,
  action_type,
  sk_task_action_start_date,
  dt_task_action_start,
  sk_task_action_end_date,
  dt_task_action_end,
  task_action_type,
  task_user_action_resolve_hours,
  sk_contract,
  sk_house_listing,
  sk_owner,
  getdate() as dt_timestamp
from staging.{table_name}
-- because the query can have another where clause (appended at runtime), a semicolon MUST NOT be added