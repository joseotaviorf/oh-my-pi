SELECT
  id,
  earning_source_id AS id_earning_source,
  external_receiver_id AS id_external_receiver,
  external_receiver_type,
  incentive_system,
  reason,
  TIMESTAMP(solved_at) AS ts_solved,
  TIMESTAMP(created_at) AS ts_created,
  TIMESTAMP(updated_at) AS ts_updated,
  year,
  month,
  day
FROM
    datalake_big_agent_raw.unresolved_earnings