, photo_jobs as (
  select
    t.*,
    cast(coalesce(fpj.id_photo_job, '-1') as bigint) as sk_photo_job,
    cast(coalesce(fpj.sk_user_rep, '-1') as bigint) as sk_user_sales_rep,
    cast(coalesce(dhl.sk_house_listing, fpj.sk_house_listing, '-1') as bigint) as sk_house_listing,
    cast(coalesce(fhl.sk_owner, '-1') as bigint) as sk_house_owner
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_clean.ods_fact_photo_job fpj
    on trim(ct.origin) = 'JobFotografo'
      and cast(ct.id_origin as bigint) = try(cast(fpj.id_photo_job as bigint))
  left join datalake_clean.ods_dim_house_listing dhl
    on trim(ct.origin) = 'Imovel'
      and cast(ct.id_origin as bigint) = try(cast(dhl.id_house as bigint))
      and cast(regexp_extract(ct.ts_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
        between cast(regexp_extract(dhl.ts_listing_version_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
          and (case
                 when dhl.ts_listing_version_end = ''
                   then now()
                 else cast(regexp_extract(dhl.ts_listing_version_end, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
               end)
  left join datalake_clean.ods_fact_house_listings fhl
    on fhl.sk_house_listing = dhl.sk_house_listing
),
photo_job_house_listing as (
  select
    cast(dhl.sk_house_listing as bigint) as sk_house_listing,
    cast(fhl.sk_owner as bigint) as sk_house_owner,
    cast(coalesce(fpj.id_photo_job, '-1') as bigint) as sk_photo_job,
    cast(coalesce(fpj.sk_user_rep, '-1') as bigint) as sk_user_sales_rep
  from datalake_clean.ods_dim_house_listing dhl
  join datalake_clean.ods_fact_photo_job fpj
    on dhl.sk_house_listing = fpj.sk_house_listing
  join datalake_clean.ods_fact_house_listings fhl
    on fhl.sk_house_listing = dhl.sk_house_listing
  where dhl.sk_house_listing != '-1'
  group by 1, 2, 3, 4
)
select distinct
  pj.sk_task,
  pj.sk_receiver,
  pj.sk_start_date,
  pj.sk_completed_date,
  pj.sk_origin,
  pj.sk_assignee,
  pj.action_user_name,
  pj.sk_user_action,
  pj.sk_action_date,
  pj.ts_action,
  pj.action_type,
  pj.sk_task_user_start_date,
  pj.ts_task_user_start,
  pj.sk_task_user_end_date,
  pj.ts_task_user_end,
  pj.task_user_type,
  pj.task_user_resolve_hours,
  pj.sk_house_listing,
  coalesce(pjhl.sk_house_owner, pj.sk_house_owner) as sk_house_owner,
  coalesce(pjhl.sk_photo_job, pj.sk_photo_job) as sk_photo_job,
  coalesce(pjhl.sk_user_sales_rep, pj.sk_user_sales_rep) as sk_user_sales_rep,
  pj.dt_partition
from photo_jobs pj
left join photo_job_house_listing pjhl
 on pj.sk_house_listing = pjhl.sk_house_listing
   and pj.sk_photo_job != -1
;

