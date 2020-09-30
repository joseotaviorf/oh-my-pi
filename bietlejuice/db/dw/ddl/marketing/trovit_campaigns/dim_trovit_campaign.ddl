DROP TABLE if EXISTS marketing.dim_trovit_campaign;
CREATE TABLE if NOT EXISTS marketing.dim_trovit_campaign(
  sk_trovit_campaign INTEGER primary key,
  id_campaign        INTEGER,
  campaign_name      VARCHAR(100),
  account_name       VARCHAR(100),
  ts_load            timestamp
);