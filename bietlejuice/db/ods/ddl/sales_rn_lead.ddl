drop table public.sales_rn_lead;
create table public.sales_rn_lead (
    rep_id integer,
    lead_id integer,
    dt_created timestamp,
    dt_closed timestamp,
    rn_first bigint,
    rn_last bigint
);