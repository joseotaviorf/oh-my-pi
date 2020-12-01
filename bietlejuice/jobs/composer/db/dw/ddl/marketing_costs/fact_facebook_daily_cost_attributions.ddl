DROP TABLE IF EXISTS marketing_costs.fact_facebook_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS marketing_costs.fact_facebook_daily_cost_attributions (
    sk_ad BIGINT,
    id_ad BIGINT,
    id_account BIGINT,
    id_campaign BIGINT,
    id_adset BIGINT,
    impressions VARCHAR,
    reach VARCHAR,
    inline_link_clicks VARCHAR,
    spend VARCHAR,
    dt_start DATE,
    dt_stop DATE
);