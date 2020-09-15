drop table if exists tracksale.fact_nps_customer_metrics;
create table if not exists tracksale.fact_nps_customer_metrics (
    sk_nps_customer varchar(300) primary key,
	sk_user bigint,
	sk_personal_document varchar(25),
	last_shift_type varchar(50),
	total_dispatches bigint,
	total_answers bigint,
	answer_rate decimal(38,3),
	comment_rate decimal(38,3),
	avg_score float,
	last_score bigint,
	overall_nps decimal(38,0),
	avg_minutes_response_time decimal(31,6),
	has_pending_survey boolean,
	dt_last_dispatched date,
	ts_load timestamp
)
