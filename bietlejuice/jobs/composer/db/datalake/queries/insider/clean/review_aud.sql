select
  id as id_review,
  reviewed_id as id_reviewed,
  reviewer_id as id_reviewer,
  rev,
  labels,
  status,
  status_mod as mod_is_status,
  type,
  revtype as rev_type,
  comment,
  revend,
  creation_date as dt_creation
from datalake_insider_raw.review_aud