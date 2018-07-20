drop table if exists datalake_raw.campaignmonitor_campaign_unsubscribes;
create external table datalake_raw.campaignmonitor_campaign_unsubscribes (
  dt string,
  email_address string,
  list_id string,
  ip_address string
)
partitioned by (
  campaign_id string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
	'ignore.malformed.json' = 'true',
	'mapping.dt' = 'Date',
	'mapping.email_address' = 'EmailAddress',
	'mapping.list_id' = 'ListID',
	'mapping.ip_address' = 'IPAddress'
)
location 's3://5a-datalake/raw/campaign_monitor/campaigns/unsubscribes/'
;