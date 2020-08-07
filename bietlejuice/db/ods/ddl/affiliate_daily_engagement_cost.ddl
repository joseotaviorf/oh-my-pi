drop table if exists public.affiliate_daily_engagement_cost;

create table public.affiliate_daily_engagement_cost (
      dt_cost date,
      sk_user integer,
      sk_region integer,
      sk_user_affiliate integer,
      sk_user_agent integer,
      affiliate_type varchar(64),
      commission_type varchar(64),
      value_brl decimal(10,2),
      ts_load timestamp
);