SELECT
  id,
  PropostaId AS id_proposal,
  status,
  StartedAt AS ts_started,
  FinishedAt AS ts_finished,
  CreatedAt AS ts_created,
  UpdatedAt AS ts_updated
FROM
  datalake_atta_test_raw.inspections
