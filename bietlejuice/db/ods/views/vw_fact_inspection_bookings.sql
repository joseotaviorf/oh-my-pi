--drop view if exists vw_fact_inspection_bookings;
--create or replace view vw_fact_inspection_bookings as
with inspection_booking_retries as (
  select
    insp.id,
    row_number() over (partition by c.id, insp."type" order by b.id asc) as rn
  from contract c
  join inspection insp
    on c.id = insp.id_contract
  join booking b
	on insp.id_booking = b.id
)
select
  insp.id as sk_inspection,
  coalesce(insp.id_booking, -1) as sk_booking,
  ((insp.id_house || '00') || coalesce(hl.version, 1))::bigint as sk_house_listing,
  coalesce(insp.id_user_inspector, -1) as sk_inspector,
  insp.id_contract as sk_contract,
  coalesce(to_char(b."data", 'YYYYMMDD')::integer, -1) as sk_booking_inspected_date,
  coalesce(to_char(insp.dt_inspected, 'YYYYMMDD')::integer, -1) as sk_inspected_date,
  coalesce(to_char(insp.ts_expired, 'YYYYMMDD')::integer, -1) as sk_expired_date,
  coalesce(to_char(insp.ts_tenant_approved, 'YYYYMMDD')::integer, -1) as sk_tenant_approved_date,
  coalesce(to_char(insp.ts_owner_approved, 'YYYYMMDD')::integer, -1) as sk_owner_approved_date,
  coalesce(ibr.rn, 1) as booking_retry_rank_by_inspection_type,
  now()::timestamp as ts_load
from inspection insp
left join booking b
	on insp.id_booking = b.id
left join house_listing hl
  on insp.id_house = hl.id_house
  	and insp.ts_created::date between hl.ts_listing_version_start::date and coalesce(hl.ts_listing_version_end::date - 1, current_date)
left join inspection_booking_retries ibr
	on ibr.id = insp.id
;