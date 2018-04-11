drop table if exists datalake_raw.campaignmonitor_opens;
create external table datalake_raw.campaignmonitor_opens (
  EmailAddress string,
  ListID string,
  `Date` timestamp,
  IPAddress string,
  Latitude double,
  Longitude double,
  City string,
  Region string,
  CountryCode string,
  CountryName string
)
partitioned by (
  campaign_id string,
  dt string
)
row format serde 'org.apache.hive.hcatalog.data.JsonSerDe'
location 's3://5a-datalake-forno/raw/campaign_monitor/opens/'
;
