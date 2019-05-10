drop table if exists lead_conversion;
create table if not exists lead_conversion (
  id bigint,
  id_house bigint,
  id_lead bigint,
  id_seller bigint,
  id_account_manager bigint,
  ts_updated timestamp,
  ts_created timestamp,
  is_valid integer,
  status varchar(255),
  "type" varchar(31)
);