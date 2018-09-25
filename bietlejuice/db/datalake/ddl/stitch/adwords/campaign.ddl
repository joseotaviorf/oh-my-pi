CREATE EXTERNAL TABLE stitch.adwords_campaigns (
  startdate string,
  servingstatus string,
  settings array<
     struct<
      `setting.type`: string,
      positivegeotargettype: string,
      negativegeotargettype: string,
      details:array<
        struct<
          targetall: boolean,
          criteriontypegroup: string
        >
      >
    >
  >,
  id int,
  campaigntrialtype string,
  name string,
  `_sdc_table_version` int,
  labels array<
    struct<
      id:int,
      status:string,
      name:string,
      attribute: struct<
        `labelattribute.type`:string,
        backgroundcolor:string,
        description:string
      >,
      `label.type`:string
    >
  >,
  status string,
  `_sdc_received_at` string,
  `_sdc_sequence` bigint,
  conversionoptimizereligibility string,
  frequencycap string,
  basecampaignid int,
  adservingoptimizationstatus string,
  `_sdc_customer_id` string,
  `_sdc_batched_at` string,
  networksetting string,
  enddate string,
  `_sdc_extracted_at` string,
  advertisingchanneltype string
)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'ignore.malformed.json'='true'
)
LOCATION
  's3://5a-datalake/stitch_data/adwords/campaigns.ddl/';