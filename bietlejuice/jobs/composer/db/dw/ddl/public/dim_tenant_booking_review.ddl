drop table if exists public.dim_tenant_booking_review;
create table public.dim_tenant_booking_review (
    sk_tenant_booking_review bigint primary key,
    id_tenant_booking_review bigint,
    review_status varchar,
    visit_not_happened_reason varchar,
    is_listing_accurate boolean,
    wrong_listing_info varchar,
    is_offer_intent boolean,
    no_offer_intent_reason varchar,
    painting smallint,
    cost_benefit smallint,
    conservation smallint,
    cleaning smallint,
    furniture smallint,
    natural_light smallint,
    indoor_silence smallint,
    agent_performance smallint,
    does_want_same_agent boolean,
    visit_type varchar(50),
    comment varchar(510)
);

ALTER TABLE public.dim_tenant_booking_review OWNER TO databricks;