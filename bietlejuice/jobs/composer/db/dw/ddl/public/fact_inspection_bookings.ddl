drop table if exists public.fact_inspection_bookings;
create table if not exists public.fact_inspection_bookings (
  sk_inspection bigint,
  sk_booking bigint,
  sk_house_listing bigint,
  sk_inspector bigint,
  sk_contract bigint,
  sk_booking_inspected_date bigint,
  sk_booking_cancelled_date bigint,
  sk_inspected_date bigint,
  sk_expired_date bigint,
  sk_tenant_approved_date bigint,
  sk_owner_approved_date bigint,
  booking_retry_rank_by_inspection_type smallint,
  ts_load timestamp
);

ALTER TABLE public.fact_inspection_bookings OWNER TO databricks;