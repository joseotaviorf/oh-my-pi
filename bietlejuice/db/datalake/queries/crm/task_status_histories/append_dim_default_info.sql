select
  ct.sk_task,
  ct.flg_solved,
  ct.score_factor,
  ct.ts_start,
  ct.ts_completed,
  ct.ts_silenced_until,
  ct.hours_task_start_to_completed,
  ct.version,
  ct.origin,
  ct.type,
  ct.is_task_auto_completed,
  substr(ct.description, 1, 5000) as description,
  ct.subject,
  ct.titles,
  ct.workgroups,
  ct.ts_partition
from tasks ct