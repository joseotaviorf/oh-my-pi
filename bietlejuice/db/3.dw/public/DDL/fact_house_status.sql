drop table if exists fact_house_status;
create table if not exists fact_house_status (
	sk_house bigint,
	sk_region bigint,
	status_history varchar,
	sk_min_version_status_date integer,
	sk_min_status_date integer,
	sk_max_status_date integer,
  dt_timestamp timestamp without time zone
)
;