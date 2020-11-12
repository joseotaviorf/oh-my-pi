DROP TABLE IF EXISTS marketing_costs.dim_linkedin_campaign;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_linkedin_campaign(
  sk_campaign        VARCHAR(100) PRIMARY KEY,
  id_campaign        VARCHAR(100),
  campaign_name      VARCHAR(255),
  cost_type          VARCHAR(50),
  type               VARCHAR(50),
  locale_country     VARCHAR(50),
  locale_language    VARCHAR(50),
  year               INTEGER,
  month              INTEGER,
  day                INTEGER,
  ts_load            TIMESTAMP
);