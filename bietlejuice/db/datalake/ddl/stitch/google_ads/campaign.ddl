CREATE EXTERNAL TABLE stitch.`adwords_campaigns`(
  `startdate` string,
  `servingstatus` string,
  `settings` array<
    struct<
      `setting.type`:string,
      positivegeotargettype:string,
      negativegeotargettype:string,
      details:array<
        struct<
          targetall:string,
          criteriontypegroup:string
        >
      >
    >
  >,
  `id` string,
  `campaigntrialtype` string,
  `name` string,
  `_sdc_table_version` string,
  `labels` array<
    struct<
      id:string,
      `status`:string,
      name:string,
      attribute:struct<
        `labelattribute.type`:string,
        backgroundcolor:string,
        description:string
      >,
      `label.type`:string
    >
  >,
  `status` string,
  `_sdc_received_at` string,
  `_sdc_sequence` string,
  `conversionoptimizereligibility` string,
  `frequencycap` string,
  `basecampaignid` string,
  `adservingoptimizationstatus` string,
  `_sdc_customer_id` string,
  `_sdc_batched_at` string,
  `networksetting` string,
  `enddate` string,
  `_sdc_extracted_at` string,
  `advertisingchanneltype` string
)
PARTITIONED BY (
  `dt` string
)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'ignore.malformed.json'='true'
)
LOCATION
  's3://5a-datalake/stitch_data/adwords/campaigns/';