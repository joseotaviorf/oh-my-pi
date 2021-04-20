drop table public.sales_rep_leads;
create table public.sales_rep_leads (
    lead_id bigint,
    lead_type varchar(255),
    lead_origin varchar(255),
    utm_source varchar(255),
    utm_medium varchar(255),
    branded_lead bool,
    b2b_lead bool,
    reprocessed_flg bool
)