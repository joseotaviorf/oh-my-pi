drop table if exists special_condition;
create table if not exists special_condition (
  id bigint,
  ts_updated timestamp,
  ts_created timestamp,
  ts_opted_id timestamp,
  ts_opted_out timestamp,
  id_house bigint,
  special_condition_type varchar(255),
  ts_expired timestamp,
  special_condition_status varchar(255),
  id_partner bigint
);