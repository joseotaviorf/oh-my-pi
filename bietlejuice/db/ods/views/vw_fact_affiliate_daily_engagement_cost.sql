--drop view if exists vw_fact_affiliate_daily_engagement_cost;
--create view vw_fact_affiliate_daily_engagement_cost as
    SELECT
        to_char(dt_cost::date::timestamp with time zone, 'YYYYMMDD')::integer as sk_date,
        sk_user,
        sk_region,
        sk_user_affiliate,
        sk_user_agent,
        affiliate_type,
        commission_type,
        value_brl,
        now()::timestamp as ts_load
    FROM
      public.affiliate_daily_engagement_cost
;