drop table if exists sauron.dim_session;
create table if not exists sauron.dim_session (
	sk_session bigint primary key,
	source varchar(50),
	attendance varchar(20),
	department_name varchar(100),
	customer_phone varchar(25),
	user_type varchar(25),
	flow_step varchar(25),
	status varchar(20),
	tags array(varchar),
	ts_created timestamp,
	ts_first_message timestamp,
	ts_updated timestamp
)
