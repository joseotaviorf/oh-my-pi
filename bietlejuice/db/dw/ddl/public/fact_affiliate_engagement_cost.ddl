drop table if exists marketing.fact_affiliate_daily_engagement_cost;

create table marketing.fact_affiliate_daily_engagement_cost (
      sk_date integer,
      sk_user integer,
      sk_region integer,
      sk_user_affiliate integer,
      sk_user_agent integer,
      affiliate_type varchar(64),
      commission_type varchar(64),
      value_brl decimal(10,2),
      ts_load timestamp
);
