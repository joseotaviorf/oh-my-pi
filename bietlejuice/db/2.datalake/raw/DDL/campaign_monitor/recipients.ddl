drop table if exists datalake_raw.campaignmonitor_campaign_recipients;
create external table datalake_raw.campaignmonitor_campaign_recipients (
  email_address string,
  list_id string
)
partitioned by (
  campaign_id string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
	'ignore.malformed.json' = 'true',
	'mapping.email_address' = 'EmailAddress',
	'mapping.list_id' = 'ListID'
)
location 's3://5a-datalake/raw/campaign_monitor/test_ribs/campaigns/recipients/'
;