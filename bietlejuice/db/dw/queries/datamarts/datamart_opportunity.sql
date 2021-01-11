with opportunities_base as(
    select distinct
        fhlf.sk_house_listing,
        left(fhlf.sk_house_listing,9) as imovel_id,
        fhlf.days_opportunity_to_listing,
        fhlf.sk_first_listing_date,
        fhlf.sk_opportunity_date,
        dd.date as opportunity_date,
        fhlf.sk_region,
        fhlf.sk_first_photo_job as sk_last_photo_job,
        fhlf.sk_lead,
        case 
          when fhlf.mkt_completion = 'Full Self-Service' then 'FSS'
          when fhlf.mkt_origin = 'B2B' then 'B2B'
          WHEN dl.sales_company IN('ACTION_LINE', 'ALGAR', 'ATENTO') AND fhlf.has_isales_intervention IS TRUE THEN 'OUT'
          when fhlf.has_isales_intervention is true then 'ISS' 
          else 'UNK' 
        end as opp_origin
    from fact_house_listing_flows fhlf
        join dim_lead dl
            on dl.sk_lead = fhlf.sk_lead
        join dim_date dd
            on dd.sk_date = fhlf.sk_opportunity_date
    where sk_opportunity_date > 0
),

photo_jobs_base as (
    select 
      imovel_id,
      sk_photo_job,
      dt_job_created,
      coalesce(dt_problem_reported, user_cancel_dt) as dt_canceled,
      lead(dt_job_created,1) over (partition by imovel_id order by sk_photo_job) as dt_next_photo_job,
      min(sk_photo_job) over (partition by imovel_id) as "sk_first_photo_job"
    from dim_photo_job
    group by 1,2,3, dt_problem_reported, user_cancel_dt
),

-- informations about first photo_job for each imovel_id
first_photo_job_base as (
    select distinct
      pjb.sk_first_photo_job,
      dpj.imovel_id,
      dpj.creation_origin,
      dpj.dt_job_scheduled as dt_first_job_scheduled
    from photo_jobs_base pjb
    left join dim_photo_job dpj
      on dpj.sk_photo_job = pjb.sk_first_photo_job
    
),

photo_jobs_metrics as (
    select 
      imovel_id,
      avg(datediff(day,dt_canceled, dt_next_photo_job)) as avg_days_photo_job_created_after_cancel,
      count(dt_next_photo_job) as photo_jobs_reschedules,
      count(*) as photo_jobs_number
    from photo_jobs_base
    group by 1
),
          
opportunity_photo_info as (
    select 
        fb.sk_house_listing,
        fb.imovel_id,
        fb.days_opportunity_to_listing,
        fb.sk_first_listing_date,
        fb.sk_opportunity_date,
        fb.opportunity_date,
        fb.sk_region,
        fb.sk_last_photo_job,
        fb.sk_lead,	
        fb.opp_origin,
        lb.sk_first_photo_job,
        lb.creation_origin,
        lb.dt_first_job_scheduled,
        datediff(day, opportunity_date, dt_first_job_scheduled) as days_first_photo_job_scheduled
    from opportunities_base fb
    left join first_photo_job_base lb
      on lb.imovel_id = fb.imovel_id
)

select 
    o.sk_house_listing,
    o.sk_opportunity_date,
    o.sk_first_listing_date,    
    o.sk_region,    
    o.sk_lead,   
    o.sk_first_photo_job,
    o.sk_last_photo_job,
    o.opp_origin,
    o.creation_origin,
    m.photo_jobs_number,
    m.photo_jobs_reschedules,
    o.days_opportunity_to_listing,
    o.days_first_photo_job_scheduled,
    m.avg_days_photo_job_created_after_cancel
from opportunity_photo_info o
left join photo_jobs_metrics m
  on m.imovel_id = o.imovel_id
