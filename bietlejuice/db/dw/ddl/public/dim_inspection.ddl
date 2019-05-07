drop table if exists dim_inspection;
create table if not exists dim_inspection (
  sk_inspection bigint,
  id_inspection bigint,
  type varchar,
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