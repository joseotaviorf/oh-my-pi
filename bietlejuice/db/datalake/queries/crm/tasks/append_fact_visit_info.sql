, bookings as (
  select
    t.*,
    cast(coalesce(db.sk_booking, '-1') as bigint) as sk_booking,
    cast(coalesce(dhl.sk_house_listing, '-1') as bigint) as sk_house_listing
  from tasks t
  join datalake_clean.crm_tasks ct
    on t.sk_task = trim(ct.id)
  left join datalake_clean.ods_dim_booking db
    on trim(ct.origin) = 'Agendamento'
      and cast(ct.id_origin as bigint) = try(cast(db.sk_booking as bigint))
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
),
booking_house_listing as (
  select
    cast(sk_house as bigint) as sk_house_listing,
    cast(sk_booking as bigint) as sk_booking
  from datalake_clean.ods_fact_demand
  where sk_booking != '-1'
  group by 1, 2
)
select distinct
  b.sk_task,
  b.sk_receiver,
  b.sk_start_date,
  b.sk_completed_date,
  b.sk_origin,
  b.sk_assignee,
  b.action_user_name,
  b.sk_user_action,
  b.sk_action_date,
  b.ts_action,
  b.action_type,
  b.sk_task_user_start_date,
  b.ts_task_user_start,
  b.sk_task_user_end_date,
  b.ts_task_user_end,
  b.task_user_type,
  b.task_user_resolve_hours,
  b.sk_booking,
  coalesce(bhl.sk_house_listing, b.sk_house_listing) as sk_house_listing,
  b.dt_partition
from bookings b
left join booking_house_listing bhl
 on b.sk_booking = bhl.sk_booking
   and b.sk_booking != -1
;

