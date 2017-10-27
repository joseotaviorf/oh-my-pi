drop view if exists vw_mgmt_ops_collection_costs;
create or replace view vw_mgmt_ops_collection_costs as
with rent_delay as (
  select
   contract_id,
   tenant_due_date,
   tenant_paid_date,
   date_part('day', cast(tenant_paid_date as timestamp) - cast(tenant_due_date as timestamp)) as rent_delayed_days
   from invoice
  where trim("from") = 'Inquilino'
   and trim(item) = 'Aluguel'
   and tenant_due_date is not null
   and tenant_paid_date is not null
),
cdre_collection as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Collection'
),
filtered_contracts as (
    select distinct
      c.imovel_id as property_id,
      rd.tenant_due_date as dt,
      rd.tenant_paid_date,
      rd.rent_delayed_days
    from contract c
    join rent_delay rd
      on c.id = rd.contract_id
    where c.tipo = 'FullService'
      and (rd.rent_delayed_days > 0 or tenant_paid_date is null)
),
costs as (
    select
      fc.property_id,
      fc.dt,
      co.dre_date as dt_cash_flow,
      co."value" / (count(fc.property_id) over (partition by co.dre_date))::double precision as vl_collection
    from filtered_contracts fc
    join cdre_collection co
      on co.dre_date = date_trunc('month', fc.dt)
)
select
  vbpc.sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_collection
from costs c
join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.dt between vbpc.min_version_time and vbpc.max_version_time
;