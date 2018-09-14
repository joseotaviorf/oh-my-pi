drop table if exists datalake_raw.zendesk_chats;

create external table datalake_raw.zendesk_chats
(
  id string,
  zendesk_ticket_id int,
  `timestamp` string,
  missed boolean,
  unread boolean,
  end_timestamp string,
  started_by string,
  rating string,
  comment string,
  department_name string,
  type string,
  response_time struct<
  	max:string,
  	avg:string,
  	first:string
  >,
  visitor struct<
  	id:string, 
  	phone:string, 
  	email:string,
  	name:string
	>,
	history array<struct<
		name:string,
		`timestamp`: string,
		department_name:string,
		`type`: string,
		channel:string,
		msg:string
	>>
	-- , tags
)
PARTITIONED BY (extracted_date date)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://5a-datalake/raw/zendesk/chats/';

MSCK REPAIR TABLE datalake_raw.zendesk_chats;
