drop table if exists datalake_raw.campaignmonitor_campaign_clicks;
create external table datalake_raw.campaignmonitor_campaign_clicks (
  dt string,
  email_address string,
  list_id string,
  ip_address string,
  url string
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
	'mapping.ip_address' = 'IPAddress',
	'mapping.url' = 'URL'
)
location 's3://5a-datalake/raw/campaign_monitor/campaigns/clicks/'
;