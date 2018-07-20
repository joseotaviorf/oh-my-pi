drop table if exists datalake_raw.campaignmonitor_campaign_bounces;
create external table datalake_raw.campaignmonitor_campaign_bounces (
  dt string,
  email_address string,
  list_id string,
  bounce_type string,
  reason string
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
	'mapping.bounce_type' = 'BounceType',
	'mapping.reason' = 'Reason'
)
location 's3://5a-datalake/raw/campaign_monitor/test_ribs/campaigns/bounces/'
;
