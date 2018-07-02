drop table if exists fact_house_status;
create table if not exists fact_house_status (
	sk_house bigint,
	id_house bigint,
	status_history varchar,
	dt_min_status date,
	dt_max_status date,
	sk_min_status_date integer,
	sk_max_status_date integer,
  dt_timestamp timestamp without time zone
)
;