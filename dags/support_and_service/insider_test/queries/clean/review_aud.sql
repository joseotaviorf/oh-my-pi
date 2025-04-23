SELECT
  id AS id_review,
  reviewed_id AS id_reviewed,
  reviewer_id AS id_reviewer,
  rev,
  labels,
  status,
  type,
  revtype AS rev_type,
  comment,
  revend,
  status_mod AS mod_is_status,
  creation_date AS dt_creation
FROM
  datalake_insider_test_raw.review_aud
