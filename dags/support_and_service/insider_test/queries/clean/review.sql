SELECT
  id,
  reviewed_id AS id_reviewed,
  reviewer_id AS id_reviewer,
  labels,
  status,
  type,
  comment,
  creation_date AS dt_creation
FROM
  datalake_insider_test_raw.review
