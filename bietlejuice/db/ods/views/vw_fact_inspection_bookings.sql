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
),
parties_comments as (
  select
    insp.id,
    count(ii_inspector.id) > 0 as has_inspector_comment,
    count(ii_tenant.id) > 0 as has_tenant_comment,
    count(ii_owner.id) > 0 as has_owner_comment
  from inspection insp
  left join inspection_item ii_inspector
    on insp.id = ii_inspector.id_inspection
      and ii_inspector.comment is not null
  left join inspection_item ii_tenant
    on insp.id = ii_tenant.id_inspection
      and ii_tenant.tenant_comment is not null
  left join inspection_item ii_owner
    on insp.id = ii_owner.id_inspection
      and ii_owner.owner_comment is not null
  group by 1
  having count(ii_inspector.id) + count(ii_tenant.id) + count(ii_owner.id) > 0
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
  coalesce(pc.has_inspector_comment, false) as has_inspector_comment,
  coalesce(pc.has_tenant_comment, false) as has_tenant_comment,
  coalesce(pc.has_owner_comment, false) as has_owner_comment,
  now()::timestamp as ts_load
from inspection insp
left join booking b
	on insp.id_booking = b.id
left join house_listing hl
  on insp.id_house = hl.id
  	and insp.ts_created::date between hl.min_version_time::date and coalesce(hl.max_version_time::date - 1, current_date)
left join inspection_booking_retries ibr
	on ibr.id = insp.id
left join parties_comments pc
	on pc.id = insp.id
;