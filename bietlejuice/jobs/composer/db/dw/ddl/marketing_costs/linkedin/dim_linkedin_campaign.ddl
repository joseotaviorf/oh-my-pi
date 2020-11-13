DROP TABLE IF EXISTS marketing_costs.dim_linkedin_campaign;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_linkedin_campaign(
  sk_campaign        INTEGER PRIMARY KEY,
  id_campaign        INTEGER,
  campaign_name      VARCHAR(255),
  cost_type          VARCHAR(50),
  type               VARCHAR(50),
  locale_country     VARCHAR(50),
  locale_language    VARCHAR(50),
  ts_load            TIMESTAMP
);