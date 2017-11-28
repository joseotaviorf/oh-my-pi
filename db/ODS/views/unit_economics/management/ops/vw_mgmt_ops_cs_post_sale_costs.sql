drop view if exists vw_mgmt_ops_cs_post_sale_costs;
create or replace view vw_mgmt_ops_cs_post_sale_costs as
with cdre_cs_post_sale as (
    select
      "Value" as "value",
      "Month"::date as dre_date
    from files.costs_dre
    where costs_dre."Category" = 'Customer Support (post-sale)'
),
calculated_qt as (
  select
    tt.property_id,
    tt.dt,
    tt.qt,
    tt.qt::double precision + coalesce((select
                                          count(int_tt.property_id)
                                        from vw_base_ticket_task int_tt
                                        where int_tt.dt = tt.dt
                                              and int_tt.group_name = tt.group_name
                                              and int_tt.property_id = -1
                                        group by int_tt.dt, int_tt.group_name), 0)::double precision /
                                       (select
                                          count(distinct int_tt.property_id)
                                        from vw_base_ticket_task int_tt
                                        where int_tt.dt = tt.dt
                                              and int_tt.group_name = tt.group_name
                                        group by int_tt.dt, int_tt.group_name)::double precision as final_qt
  from vw_base_ticket_task tt
  where tt.group_name = 'Customer Support (post-sale)'
),
costs as (
    select
      cq.property_id,
      cq.dt,
      cps.dre_date as dt_cash_flow,
      cps."value" * cq.final_qt / (sum(cq.final_qt) over (partition by cps.dre_date))::double precision as vl_cs_post_sale
    from calculated_qt cq
    join cdre_cs_post_sale cps
      on cps.dre_date = cq.dt + interval '1 month'
    where cq.property_id != -1
)
select
  coalesce(vbpc.sk_property, (c.property_id || '001')::bigint) as sk_property,
  c.property_id,
  c.dt_cash_flow,
  c.vl_cs_post_sale
from costs c
left join vw_base_property_costs vbpc
  on vbpc.property_id = c.property_id
    and c.dt between vbpc.min_version_time and vbpc.max_version_time
;