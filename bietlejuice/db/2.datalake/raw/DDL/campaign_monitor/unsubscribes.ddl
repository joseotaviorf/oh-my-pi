drop table if exists datalake_raw.campaignmonitor_unsubscribes;
create external table datalake_raw.campaignmonitor_unsubscribes (
  EmailAddress string,
  ListID string,
  `Date` timestamp,
  IPAddress string
)
partitioned by (
  campaign_id string,
  dt string 
)
row format serde 'org.apache.hive.hcatalog.data.JsonSerDe'
location 's3://5a-datalake-forno/raw/campaign_monitor/unsubscribes/'
;