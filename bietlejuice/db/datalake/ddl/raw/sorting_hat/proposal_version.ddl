drop table if exists datalake_raw.sortinghat_proposalversion;
create external table datalake_raw.sortinghat_proposalversion (
  id string,
  proposal_id string,
  imovel_id string,
  analysis_date string,
  score_5A string,
  score_5A_best_subset string,
  score_cardif string,
  score_cardif_best_subset string,
  status string,
  `comment` string,
  analyst_name string,
  supervisor_name string,
  rent_value string,
  condo_value string,
  iptu_value string,
  created_at string,
  updated_at string,
  versioned_at string,
  home_area string,
  home_bathrooms string,
  home_bedrooms string,
  home_city string,
  home_garages string,
  home_region string,
  home_suites string,
  home_type string,
  home_zipcode string,
  drive_id string,
  rejection_motive string,
  home_insurance_value string,
  risk_level string,
  risk_level_best_subset string,
  process_date string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/sorting_hat/ProposalVersion/'
tblproperties (
  'skip.header.line.count' = '1'
)
;
