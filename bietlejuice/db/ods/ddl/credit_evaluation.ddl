drop table if exists credit_evaluation;
create table credit_evaluation (
    id bigint,
    id_proposal bigint,
    id_house bigint,
    id_user bigint,
    reason varchar(255),
    result varchar(255),
    status varchar(255),
    ts_created TIMESTAMP,
    ts_updated TIMESTAMP
);