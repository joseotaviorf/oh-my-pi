DROP TABLE staging.marketing_facebook_ads;

CREATE TABLE IF NOT EXISTS staging.marketing_facebook_ads (
    id bigint identity(0,1),
    account_id varchar(65535),
    account_name varchar(65535),
    ad_id varchar(65535),
    ad_name varchar(65535),
    adset_id varchar(65535),
    adset_name varchar(65535),
    campaign_id varchar(65535),
    campaign_name varchar(65535),
    reach varchar(65535),
    impressions varchar(65535),
    clicks varchar(65535),
    spend varchar(65535),
    impression_device varchar(65535),
    date_start varchar(65535),
    date_stop varchar(65535),
    link_clicks varchar(65535),
    acc varchar(256),
    dt_created varchar(256)
)