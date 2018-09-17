drop table if exists staging.bdg_crmvisit_demand;
create table if not exists staging.bdg_crmvisit_demand (
  sk_visit_task varchar,
  sk_demand bigint,
  dt_timestamp timestamp
)
;