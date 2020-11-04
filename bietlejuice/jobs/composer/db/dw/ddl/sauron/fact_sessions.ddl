drop table if exists sauron.fact_sessions;
create table if not exists sauron.fact_sessions (
	sk_nps_answer bigint primary key,
	sk_session bigint,
	sk_conversation varchar(100),
	sk_user bigint,
	sk_personal_document varchar(50),
	sk_created_date bigint,
	is_retained_by_BOT boolean,
	minutes_duration decimal(38,3)
)
