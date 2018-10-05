drop table if exists datalake_raw.campaignmonitor_campaign;
create external table datalake_raw.campaignmonitor_campaign (
  id string,
  from_email string,
  from_name string,
  name string,
  reply_to string,
  subject string,
  web_version_text_url string,
  web_version_url string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json' = 'true',
  'mapping.id' = 'CampaignID',
  'mapping.from_email' = 'FromEmail',
  'mapping.from_name' = 'FromName',
  'mapping.name' = 'Name',
  'mapping.reply_to' = 'ReplyTo',
  'mapping.subject' = 'Subject',
  'mapping.web_version_text_url' = 'WebVersionTextURL',
  'mapping.web_version_url' = 'WebVersionURL'
)
location 's3://5a-datalake/raw/campaign_monitor/campaigns/campaigns/'
;
