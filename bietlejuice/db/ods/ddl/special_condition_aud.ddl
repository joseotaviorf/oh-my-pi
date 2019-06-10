drop table if exists special_condition_aud;
create table if not exists special_condition_aud (
  id bigint,
  rev integer,
  rev_type smallint,
  ts_opted_in timestamp,
  ts_opted_out timestamp,
  special_condition_type varchar(255),
  id_house bigint,
  ts_expired timestamp,
  special_condition_status varchar(255),
  special_condition_status_mod smallint,
  ts_opted_in_mod smallint,
  ts_opted_out_mod smallint,
  ts_expired_mod smallint,
  id_partner bigint,
  id_partner_mod smallint
);