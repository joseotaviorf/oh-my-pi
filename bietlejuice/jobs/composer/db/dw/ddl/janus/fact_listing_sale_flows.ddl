DROP TABLE IF EXISTS janus.fact_listing_sale_flows;

CREATE TABLE IF NOT EXISTS janus.fact_listing_sale_flows
(
    ods_id BIGINT,
    sk_house_listing BIGINT,
    sk_region BIGINT,
    sk_sale_flow BIGINT,
    sk_booking BIGINT,
    sk_owner BIGINT,
    sk_user_agent BIGINT,
    sk_client BIGINT,
    sk_visit BIGINT,
    sk_house_first_listing_date BIGINT,
    sk_house_listing_date BIGINT,
    sk_house_listing_de_publication_date BIGINT,
    sk_booking_created_date BIGINT,
    sk_visit_date BIGINT,
    sk_agent_review_rating_date BIGINT,
    visit_created_type VARCHAR,
    funnel_step VARCHAR(255),
    funnel_step_drop_reason VARCHAR(255),
    flg_visit_completed BOOLEAN,
    flg_visit_performed BOOLEAN,
    flg_visit_created_from_app BOOLEAN,
    flg_visit_last_updated_from_app BOOLEAN,
    days_booking_created_to_visit NUMERIC(14,2),
    days_user_created_to_visit NUMERIC(14,2),
    days_house_listing_to_visit NUMERIC(14,2),
    ts_load TIMESTAMP
);

ALTER TABLE janus.fact_listing_sale_flows OWNER TO databricks;