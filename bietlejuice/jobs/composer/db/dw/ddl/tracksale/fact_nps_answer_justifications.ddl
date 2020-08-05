drop table if exists tracksale.fact_nps_answer_justifications;
create table if not exists tracksale.fact_nps_answer_justifications (
    sk_nps_answer bigint,
    level varchar(10),
    justification varchar(200)
)
