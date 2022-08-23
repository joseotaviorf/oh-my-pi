drop table if exists tracksale.fact_nps_customer_metrics;
create table if not exists tracksale.fact_nps_customer_metrics (
    sk_nps_customer varchar(400) primary key,
	sk_user bigint,
	sk_personal_document varchar(25),
	last_shift_type varchar(50),
	total_dispatches bigint,
	total_answers bigint,
    total_answers_forsale bigint,
    total_answers_forrent bigint,
	answers_as_promoter bigint,
    answers_as_detractor bigint,
	answer_rate decimal(38,3),
	comment_rate decimal(38,3),
	avg_score float,
	avg_score_forsale float,
    avg_score_forrent float,
	last_score bigint,
	overall_nps decimal(38,0),
	overall_nps_forsale decimal(38,0),
	overall_nps_forrent decimal(38,0),
	avg_minutes_response_time decimal(31,6),
	has_pending_survey boolean,
	dt_last_dispatched date,
	dt_last_answer date,
    dt_first_answer date,
	ts_load timestamp
);
CALL grant_all_permissions_on_schema('tracksale');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA tracksale TO GROUP etl;
GRANT ALL ON SCHEMA tracksale TO GROUP ETL;
ALTER TABLE tracksale.fact_nps_customer_metrics owner TO airflow;