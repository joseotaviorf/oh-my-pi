drop table if exists public.fact_market_index;
create table public.fact_market_index (
  sk_property bigint,
  sk_external_property bigint,
  sk_snapshot_date integer,
  sk_updated_on_date integer,
  business varchar(200),
  advertiser_name varchar(255),
  advertiser_type varchar(255)
);
