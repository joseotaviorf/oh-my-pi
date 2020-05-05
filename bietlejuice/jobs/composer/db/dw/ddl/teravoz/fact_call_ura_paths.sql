drop table if exists teravoz.fact_call_ura_paths;
create table if not exists teravoz.fact_call_ura_paths (
    sk_call varchar(30),
    sk_flow_step bigint,
    sk_started date,
    sk_call_date bigint,
    sk_call_date_local bigint,
    flow_step_name varchar(20),
    ura_step_name varchar(40),
    option_answered varchar(10),
    seconds_ura_step_duration int,
    ts_created timestamp,
    ts_created_local timestamp,
    ts_load timestamp
)