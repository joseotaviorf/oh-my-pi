drop table if exists datalake_raw.asterisk_cdr;
create external table if not exists datalake_raw.asterisk_cdr (
  calldate string,
  clid string,
  src string,
  dst string,
  dcontext string,
  channel string,
  dstchannel string,
  lastapp string,
  lastdata string,
  duration string,
  billsec string,
  disposition string,
  amaflags string,
  accountcode string,
  uniqueid string,
  userfield string,
  did string,
  recordingfile string,
  cnum string,
  cnam string,
  outbound_cnum string,
  outbound_cnam string,
  dst_cnam string
)
partitioned by (
  dt string
)
row format serde 'org.openx.data.jsonserde.JsonSerDe'
with serdeproperties (
  'ignore.malformed.json'='true'
)
location 's3://5a-datalake/raw/asterisk/cdr/'
;