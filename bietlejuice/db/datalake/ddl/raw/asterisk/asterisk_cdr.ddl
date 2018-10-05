drop table if exists datalake_raw.asterisk_cdr;
create external table datalake_raw.asterisk_cdr (
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
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/asterisk/cdr/'
;