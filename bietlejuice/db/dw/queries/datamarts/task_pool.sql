with t_range as (
select
    distinct
    fhl.sk_lead,
    sk_task_created_date as dt_inicio_pros,
    case when sk_task_closed_date > 0 then cast(to_char(cast(d.date as date) - interval '1' day, 'yyyyMMdd') as integer)
         when cast(task.sk_first_realized_date as integer) > 0 then task.sk_first_realized_date
         when cast(task.sk_first_resolved_date as integer) > 0 then task.sk_first_resolved_date
        else 20991231 end as dt_fim_pros,
     dr.city_group
from fact_house_listing_flows fhl
left join dim_region dr
  on fhl.sk_region = dr.sk_region
left join dim_date d
  on d.sk_date = fhl.sk_task_closed_date
left join crm.fact_lead_tasks task
  on task.sk_lead = fhl.sk_lead
where sk_task_created_date > '0'
order by 1,2
),
max_dt as (
select
    id,
    max(dt) as max_dt
from datalake_clean.crm_tasks
where type in ('ConverterLead','ConverterLeadPrioritario')
group by 1
),
tasks_updated as (
select
    ct.id,
    ct.id_origin
from datalake_clean.crm_tasks ct
join max_dt m
  on m.id = ct.id AND dt = max_dt
where type in ('ConverterLead','ConverterLeadPrioritario')
),
max_id_hosanna as (
select
    m.codigo,
    max(id) as max_id
from datalake_raw.autodialer_mailing_list m
group by 1
),
mailing_list_updated as (
select
    m.codigo,
    m.active, m.id
from datalake_raw.autodialer_mailing_list m
join max_id_hosanna mh
  on mh.codigo = m.codigo AND mh.max_id = m.id
)
select
    dt.date,
    case when m.active = 'N' then 'Inactive in mailing list'
        when m.id is null then 'Not in mailing list'
        else 'Active in mailing list' end as mailing_list_status,
    count(distinct t_range.sk_lead) as tasks_open,
    city_group
from dim_date dt
join t_range
  on dt.sk_date between t_range.dt_inicio_pros and t_range.dt_fim_pros
     and dt.sk_date > 20190301
     and dt.date = dt.week_end
join public.dim_lead l
  on l.sk_lead = t_range.sk_lead
left join tasks_updated t
  on t.id_origin = t_range.sk_lead
left join datalake_clean.autodialer_task_references r
  on r.task_id = t.id
left join mailing_list_updated m
  on m.codigo = r.task_id
where dt.sk_date > 20180101 and dt.date < getdate()
      and trim(coalesce(l.cidade,'')) <> 'Outra cidade'
      and trim(coalesce(l.bairro,'')) <> 'Outro bairro'
group by 1,2,4