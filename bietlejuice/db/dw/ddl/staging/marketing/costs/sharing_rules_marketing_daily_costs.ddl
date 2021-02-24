DROP TABLE IF EXISTS staging.sharing_rules_marketing_daily_costs;
CREATE TABLE IF NOT EXISTS staging.sharing_rules_marketing_daily_costs
(
    rule_id VARCHAR(6),
    sk_date INTEGER,
    city_group VARCHAR(50),
    funnel_side VARCHAR(15),
    "share" DOUBLE PRECISION
);
