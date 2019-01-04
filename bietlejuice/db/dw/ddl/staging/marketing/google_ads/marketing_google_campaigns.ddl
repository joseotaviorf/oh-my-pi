DROP TABLE staging.marketing_google_campaigns;

CREATE TABLE IF NOT EXISTS staging.marketing_google_campaigns (
    id bigint identity(0,1),
    account_id varchar,
    campaign_id varchar,
    campaign_name varchar,
    clicks varchar,
    click_type varchar,
    cost varchar,
    date varchar,
    device varchar,
    impressions varchar,
    account_name varchar,
    hour_of_day varchar,
    month varchar,
    labels varchar,
    week varchar,
    year varchar,
    acc varchar,
    dt_created varchar
);