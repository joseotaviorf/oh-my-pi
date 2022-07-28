drop table if exists payment.dim_occurrence_code;
create table if not exists payment.dim_occurrence_code (
    sk_occurrence_code varchar(10) primary key,
    name varchar(10),
    source_file_type varchar(15),
    description varchar(500),
    last_code varchar(2),
    second_last_code varchar(2),
    third_last_code varchar(2),
    ts_load timestamp
)