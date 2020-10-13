drop table if exists dim_inspection;
create table if not exists dim_inspection (
  sk_inspection bigint primary key,
  id_inspection bigint,
  type varchar,
  mode varchar,
  status varchar,
  ts_created timestamp,
  ts_expired timestamp,
  is_tenant_approved boolean,
  is_owner_approved boolean,
  has_inspector_comment boolean,
  has_tenant_comment boolean,
  has_owner_comment boolean,
  ts_load timestamp
);