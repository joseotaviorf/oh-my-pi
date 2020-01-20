select
  id,
  reviewed_id as id_reviewed,
  reviewer_id as id_reviewer,
  labels,
  status,
  type,
  comment,
  creation_date as dt_creation
from datalake_insider_raw.review