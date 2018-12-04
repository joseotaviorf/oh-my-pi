, photo_jobs as (
  select
    t.*,
    cast(coalesce(fpj.id_photo_job, fpj_hl.id_photo_job, '-1') as bigint) as sk_photo_job,
    cast(coalesce(fpj.sk_user_rep, fpj_hl.sk_user_rep, '-1') as bigint) as sk_user_sales_rep,
    cast(coalesce(dhl.sk_house_listing, fpj.sk_house_listing, '-1') as bigint) as sk_house_listing,
    cast(coalesce(fhl.sk_owner, fpj_fhl.sk_owner, '-1') as bigint) as sk_house_owner
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_clean.ods_fact_photo_job fpj
    on trim(ct.origin) = 'JobFotografo'
      and cast(ct.id_origin as bigint) = try(cast(fpj.id_photo_job as bigint))
  left join datalake_clean.ods_fact_house_listings fpj_fhl
    on fpj_fhl.sk_house_listing = fpj.sk_house_listing
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
  left join datalake_clean.ods_fact_photo_job fpj_hl
    on fpj_hl.sk_house_listing = fhl.sk_house_listing
)
select distinct
  sk_task,
  sk_receiver,
  sk_start_date,
  sk_completed_date,
  sk_origin,
  sk_assignee,
  action_user_name,
  sk_user_action,
  sk_action_date,
  ts_action,
  action_type,
  sk_task_user_start_date,
  ts_task_user_start,
  sk_task_user_end_date,
  ts_task_user_end,
  task_user_type,
  task_user_resolve_hours,
  sk_house_listing,
  sk_house_owner,
  sk_photo_job,
  sk_user_sales_rep,
  dt_partition
from photo_jobs
;

