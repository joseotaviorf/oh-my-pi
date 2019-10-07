drop table if exists public.fact_affiliate_engagement_cost;

create table public.fact_affiliate_engagement_cost (
      sk_date integer,
      sk_user integer,
      sk_region integer,
      dadosafiliado_id integer,
      sk_user_agent integer,
      is_affiliate_active smallint,
      affiliate_type varchar(64),
      commission_type varchar(64),
      value_brl decimal(10,2),
      ts_load timestamp
);
