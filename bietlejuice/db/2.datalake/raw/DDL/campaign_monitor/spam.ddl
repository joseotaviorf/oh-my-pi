drop table if exists datalake_raw.campaignmonitor_spam;
create external table datalake_raw.campaignmonitor_spam (
  EmailAddress string,
  ListID string,
  `Date` timestamp
)
partitioned by (
  campaign_id string,
  dt string
)
row format serde 'org.apache.hive.hcatalog.data.JsonSerDe'
location 's3://5a-datalake-forno/raw/campaign_monitor/spam/'
;