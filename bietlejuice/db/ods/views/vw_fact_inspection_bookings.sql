drop view if exists vw_fact_inspection_bookings;
create or replace view vw_fact_inspection_bookings as
with inspection_booking_retries as (
  select
    insp.id,
    count(1) as retries
  from inspection insp
  join booking b
    on insp.id_booking = b.id
      and b.tipo = 'Vistoria'
      and b."reagendadoDe_id" is not null
  group by 1
)
select
  insp.id as sk_inspection,
  coalesce(insp.id_booking, -1) as sk_booking,
  ((insp.id_house || '00') || coalesce(hl.version, 1))::bigint as sk_house_listing,
  coalesce(insp.id_user_inspector, -1) as sk_inspector,
  insp.id_contract as sk_contract,
  coalesce(to_char(b."data", 'YYYYMMDD')::integer, -1) as sk_booking_inspected_date,
  coalesce(to_char(insp.ts_expired, 'YYYYMMDD')::integer, -1) as sk_expired_date,
  coalesce(to_char(insp.ts_tenant_approved, 'YYYYMMDD')::integer, -1) as sk_tenant_approved_date,
  coalesce(to_char(insp.ts_owner_approved, 'YYYYMMDD')::integer, -1) as sk_owner_approved_date,
  coalesce(retries, 0) as booking_retries,
  now()::timestamp as ts_load
from inspection insp
left join booking b
	on insp.id_booking = b.id
left join house_listing hl
  on insp.id_house = hl.id
  	and insp.ts_created::date between hl.min_version_time::date and coalesce(hl.max_version_time::date - 1, current_date)
left join inspection_booking_retries ibr
	on ibr.id = insp.id
;