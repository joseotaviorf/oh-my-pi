DROP TABLE IF EXISTS datalake_lifull_campaigns_raw.campaigns_report;
CREATE TABLE datalake_lifull_campaigns_raw.campaigns_report (
  id string,
  name string,
  account_name string,
  clicks string,
  desktop_cost string,
  mobile_cost string,
  total_cost string,
  curr_date string,
  group_name string
)
using
  json
location
  's3://5a-datalake/raw/marketing/lifull_campaigns'

/*
 * This table is partitioned but we are not declaring it here. Not declaring it forces spark to check all folders 
 * and files, this is good to this flow because we don't need to schedule a job to add a new partition every day
 */