SELECT
  _id AS id,
  flags,
  taskTypes AS task_types,
  title,
  automaticReassign AS automatic_reassign,
  __v AS version
FROM
  datalake_crm_raw.workgroups