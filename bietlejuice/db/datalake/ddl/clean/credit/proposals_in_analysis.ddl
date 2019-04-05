drop table if exists datalake_clean.credit_proposals_in_analysis;
create external table if not exists datalake_clean.credit_proposals_in_analysis (
  id_proposal string,
  id_proponent string,
  id_house string,
  last_interaction string,
  sort_direction string,
  analyst string
)
stored as parquet
location 's3://5a-datalake/clean/credit/proposals_in_analysis'
;