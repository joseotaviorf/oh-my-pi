SELECT
  erd.sk_requisition,
  erd.requisition_code,
  erd.requisition_state,
  erd.requisition_status,
  erd.job_title,
  COALESCE(erd.position_name, '-1') AS position_name,
  COALESCE(erd.opening_reason, '-1') AS opening_reason,
  COALESCE(erd.salary_band, '-1') AS salary_band,
  COALESCE(erd.capacity_overhead, '-1') AS capacity_overhead,
  COALESCE(erd.affirmative_position, '-1') AS affirmative_position,
  COALESCE(erd.career_track, '-1') AS career_track,
  COALESCE(erd.how_closed, '-1') AS how_closed,
  COALESCE(erd.sla, '-1') AS sla,
  erd.sla_type,
  NOW() AS ts_load
FROM
  datalake_workable.requisition_details AS erd