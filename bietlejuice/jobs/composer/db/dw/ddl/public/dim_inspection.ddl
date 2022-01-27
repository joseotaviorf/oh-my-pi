drop table if exists public.dim_inspection;
create table if not exists public.dim_inspection (
  sk_inspection bigint primary key,
  id_inspection bigint,
  mode varchar,
  status varchar,
  type varchar,
  is_tenant_approved boolean,
  is_owner_approved boolean,
  has_inspector_comment boolean,
  has_tenant_comment boolean,
  has_owner_comment boolean,
  ts_created timestamp,
  ts_expired timestamp,
  ts_first_synced timestamp,
  ts_last_synced timestamp,
  ts_load timestamp
);

ALTER TABLE public.dim_inspection OWNER TO databricks;
