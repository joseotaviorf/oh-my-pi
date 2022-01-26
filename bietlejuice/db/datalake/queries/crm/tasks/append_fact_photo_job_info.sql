, photo_jobs as (
-- TODO: add B2B owner
  select
    t.*,
    coalesce(fpj.id_photo_job, -1) as sk_photo_job,
    coalesce(fpj.sk_user_rep, -1) as sk_user_sales_rep,
    cast(coalesce(dhl.sk_house_listing, dhl_no_version.sk_house_listing, fhl_photo.sk_house_listing, '-1') as bigint) as sk_house_listing,
    cast(coalesce(fhl_photo.sk_owner, fhl.sk_owner, fhl_no_version.sk_owner, '-1') as bigint) as sk_house_owner
	from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_clean.ods_fact_photo_job fpj
    on trim(ct.origin) = 'JobFotografo'
      and try_cast(try_cast(ct.id_origin as decimal) as bigint) = fpj.id_photo_job
  left join datalake_clean.ods_fact_house_listings fhl_photo
  	on fhl_photo.sk_house_listing = fpj.sk_house_listing
  	  and fhl_photo.sk_house_listing != '-1'
  left join datalake_clean.ods_dim_house_listing dhl
    on trim(ct.origin) = 'Imovel'
      and try_cast(try_cast(ct.id_origin as decimal) as bigint) = try_cast(dhl.id_house as bigint)
      and cast(regexp_extract(ct.ts_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
        between (case
                 when dhl.ts_listing_version_start = ''
                   then cast(regexp_extract(ct.ts_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
                 else now()
               end)
          and (case
                 when dhl.ts_listing_version_end = ''
                   then now()
                 else cast(regexp_extract(dhl.ts_listing_version_end, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
               end)
  left join datalake_clean.ods_fact_house_listings fhl
    on fhl.sk_house_listing = dhl.sk_house_listing
    	and fhl.sk_house_listing != '-1'
  left join datalake_clean.ods_dim_house_listing dhl_no_version
    on trim(ct.origin) = 'Imovel'
      and ct.id_origin = dhl_no_version.id_house
      and dhl_no_version.ts_listing_version_start = ''
  left join datalake_clean.ods_fact_house_listings fhl_no_version
    on fhl_no_version.sk_house_listing = dhl_no_version.sk_house_listing
),
photo_job_house_listing as (
  select
    cast(sk_house_listing as bigint) as sk_house_listing,
    cast(sk_owner as bigint) as sk_house_owner
  from datalake_clean.ods_fact_house_listings
  where sk_house_listing != '-1'
  group by 1, 2
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
  pj.sk_photo_job as sk_photo_job,
  pj.sk_user_sales_rep as sk_user_sales_rep,
  pj.dt_partition
from photo_jobs pj
left join photo_job_house_listing pjhl
 on pj.sk_house_listing = pjhl.sk_house_listing
   and pj.sk_photo_job = -1
;