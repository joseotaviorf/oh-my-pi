drop table if exists tracksale.dim_nps_answer;
create table if not exists tracksale.dim_nps_answer (
    sk_nps_answer bigint,
    campaign_step varchar(50),
    score_category varchar(20),
    comment varchar(20000),
    ts_answered timestamp,
    ts_load timestamp
)
