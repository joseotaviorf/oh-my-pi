drop table if exists teravoz.dim_call;
create table if not exists teravoz.dim_call (
    sk_call varchar(30),
    external_phone_type varchar(10),
    direction varchar(10),
    called_phone_number varchar(20),
    caller_phone_number varchar(20),
    external_phone_number varchar(20),
    user_dialed_phone_number varchar(20),
    recording_url varchar(255),
    ts_load timestamp
)


