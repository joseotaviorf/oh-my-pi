CREATE EXTERNAL TABLE stitch.`adwords_click_performance_report`(
  `campaignid` string,
  `citylocationofinterest` string,
  `device` string,
  `adid` string,
  `adgroupid` string,
  `_sdc_report_datetime` string,
  `countryterritorylocationofinterest` string,
  `campaignstate` string,
  `adgroupstate` string,
  `networkwithsearchpartners` string,
  `clicks` string,
  `regionphysicallocation` string,
  `mostspecificlocationtargetlocationofinterest` string,
  `monthofyear` string,
  `matchtype` string,
  `_sdc_table_version` string,
  `network` string,
  `topvsother` string,
  `campaign` string,
  `keywordid` string,
  `campaignlocationtarget` string,
  `clicktype` string,
  `account` string,
  `countryterritoryphysicallocation` string,
  `_sdc_received_at` string,
  `userlistid` string,
  `_sdc_sequence` string,
  `customerid` string,
  `__sdc_primary_key` string,
  `adtype` string,
  `googleclickid` string,
  `cityphysicallocation` string,
  `regionlocationofinterest` string,
  `metroareaphysicallocation` string,
  `keywordplacement` string,
  `_sdc_customer_id` string,
  `day` string,
  `page` string,
  `_sdc_batched_at` string,
  `mostspecificlocationtargetphysicallocation` string,
  `adgroup` string,
  `_sdc_extracted_at` string,
  `metroarealocationofinterest` string)
PARTITIONED BY (
  `dt` string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
    'ignore.malformed.json'='true')
STORED AS INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://5a-datalake/stitch_data/adwords/CLICK_PERFORMANCE_REPORT/'