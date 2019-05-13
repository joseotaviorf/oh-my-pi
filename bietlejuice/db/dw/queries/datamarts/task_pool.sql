with t_range as (
select distinct
        fhl.sk_lead,
        cast(sk_task_created_date as integer) as dt_inicio_pros,
        case when cast(sk_task_closed_date as integer) > 0 then cast(to_char(cast(d.date as date) - interval '1' day, 'yyyyMMdd') as integer)
             when cast(task.sk_first_realized_date as integer) > 0 then task.sk_first_realized_date
             when cast(task.sk_first_resolved_date as integer) > 0 then task.sk_first_resolved_date
        	else 20991231 end as dt_fim_pros
    from datalake_clean.ods_fact_house_listing_flows fhl
    left join datalake_clean.ods_dim_date d on d.sk_date = fhl.sk_task_closed_date
    left join crm.fact_lead_tasks task on task.sk_lead = fhl.sk_lead
    where sk_task_created_date > '0'
    order by 1,2
), t_dates as (
    select
        cast(sk_date as bigint) sk_dateint,
        *
    from
        datalake_raw.dim_date
    where sk_date > '20180101'
),
max_dt as (
SELECT id, max(dt) as max_dt FROM datalake_clean.crm_tasks
WHERE type in ('ConverterLead','ConverterLeadPrioritario')
GROUP BY 1
),
tasks_updated as (
SELECT ct.*
from datalake_clean.crm_tasks ct
JOIN max_dt m on m.id = ct.id AND dt = max_dt
WHERE type in ('ConverterLead','ConverterLeadPrioritario')
),
max_id_hosanna as (
SELECT m.codigo, max(id) as max_id
FROM datalake_raw.autodialer_mailing_list m
GROUP BY 1
),
mailing_list_updated as (
SELECT m.*
FROM datalake_raw.autodialer_mailing_list m
JOIN max_id_hosanna mh on mh.codigo = m.codigo AND mh.max_id = m.id
)
select
    dt.date,
    case when m.active = 'N' then 'Inactive in mailing list'
        when m.id is null then 'Not in mailing list'
        else 'Active in mailing list' end as mailing_list_status
        ,
    count(distinct t_range.sk_lead) as tasks_open
from
    t_dates dt
left join
    t_range
    on dt.sk_dateint between t_range.dt_inicio_pros and t_range.dt_fim_pros
join
    datalake_raw.ebdb_lead l
    on l.id = t_range.sk_lead
join datalake_clean.ods_dim_date d on dt.date  = d.week_end and d.sk_date > '20180101'
left join tasks_updated t on t.id_origin = t_range.sk_lead
left join datalake_clean.autodialer_task_references r on r.task_id = t.id
left join mailing_list_updated m on m.codigo = r.task_id
Where
    trim(coalesce(l.cidade,'')) <> 'Outra cidade'
    and trim(coalesce(l.bairro,'')) <> 'Outro bairro'
    and date(dt.date) between date('2018-01-01') and date(getdate())
group by 1,2
order by 1 ASC