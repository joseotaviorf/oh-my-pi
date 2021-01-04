DROP TABLE IF EXISTS marketing_costs.fact_facebook_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS marketing_costs.fact_facebook_daily_cost_attributions (
    sk_ad VARCHAR,
    id_ad BIGINT,
    id_account BIGINT,
    id_campaign BIGINT,
    id_adset BIGINT,
    impressions VARCHAR(512),
    reach VARCHAR(512),
    inline_link_clicks VARCHAR(512),
    spend VARCHAR(512),
    spend_mobile DOUBLE,
    spend_desktop DOUBLE,
    spend_other DOUBLE,
    dt_start DATE,
    dt_stop DATE
);