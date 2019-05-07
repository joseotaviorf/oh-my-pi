drop table if exists fact_inspection_bookings;
create table if not exists fact_inspection_bookings (
  sk_inspection bigint,
  sk_booking bigint,
  sk_house_listing bigint,
  sk_inspector bigint,
  sk_contract bigint,
  sk_booking_inspected_date bigint,
  sk_expired_date bigint,
  sk_tenant_approved_date bigint,
  sk_owner_approved_date bigint,
  booking_retries smallint,
  has_inspector_comment boolean,
  has_tenant_comment boolean,
  has_owner_comment boolean,
  ts_load timestamp
);