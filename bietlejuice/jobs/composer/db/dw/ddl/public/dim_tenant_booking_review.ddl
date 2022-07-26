DROP TABLE IF EXISTS public.dim_tenant_booking_review;
CREATE TABLE public.dim_tenant_booking_review (
    sk_tenant_booking_review BIGINT PRIMARY KEY,
    id_tenant_booking_review BIGINT,
    review_status VARCHAR,
    visit_not_happened_reason VARCHAR,
    wrong_listing_info VARCHAR,
    no_offer_intent_reason VARCHAR,
    painting SMALLINT,
    cost_benefit SMALLINT,
    conservation SMALLINT,
    cleaning SMALLINT,
    furniture SMALLINT,
    natural_light SMALLINT,
    indoor_silence SMALLINT,
    agent_performance SMALLINT,
    visit_type VARCHAR(50),
    comment VARCHAR(510),
    is_listing_accurate BOOLEAN,
    is_offer_intent BOOLEAN,
    does_want_same_agent BOOLEAN,
    ts_load TIMESTAMP
);

ALTER TABLE public.dim_tenant_booking_review OWNER TO databricks;