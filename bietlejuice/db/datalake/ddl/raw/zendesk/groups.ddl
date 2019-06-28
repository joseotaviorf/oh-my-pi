drop table if exists datalake_raw.zendesk_groups;
create external table if not exists datalake_raw.zendesk_groups (
    id string,
    updated_at string,
    /* These columns are applicable to all tables and integration types. 
       Unless noted, every column in this list will be present in every integration table created by Stitch. */
    `_sdc_sequence` string,       -- order in which data points were considered for loading.
    `_sdc_received_at` string,,   -- indicating when Stitch received the record for loading.
    `_sdc_batched_at` string,     -- indicating when Stitch loaded the batch the record was a part of into the data warehouse
    `_sdc_table_version` string,  -- Indicates the version of the table.
    url string,
    name string,
    deleted string,
    created_at string
)
partitioned by (
    dt string
)
row format serde
  'org.openx.data.jsonserde.JsonSerDe'
stored as inputformat
  'org.apache.hadoop.mapred.TextInputFormat'
outputformat
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
location
  's3://5a-datalake/raw/zendesk_groups/groups';