drop table if exists datalake_raw.campaignmonitor_bounces;
create external table datalake_raw.campaignmonitor_bounces (
  EmailAddress string,
  ListID string,
  BounceType string,
  `Date` timestamp,
  Reason string
)
partitioned by (
  campaign_id string,
  dt string
)
row format serde 'org.apache.hive.hcatalog.data.JsonSerDe'
location 's3://5a-datalake-forno/raw/campaign_monitor/bounces/'
;
