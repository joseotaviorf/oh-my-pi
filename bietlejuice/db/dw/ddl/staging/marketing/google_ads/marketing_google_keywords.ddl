DROP TABLE staging.marketing_google_keywords;

CREATE TABLE IF NOT EXISTS staging.marketing_google_keywords (
    id bigint identity(0,1),
    account_id varchar(256),
    adgroup_id varchar(256),
    adgroup_name varchar(256),
    campaign_id varchar(256),
    campaign_name varchar(256),
    clicks varchar(256),
    click_type varchar(256),
    cost varchar(256),
    date varchar(256),
    device varchar(256),
    keyword_id varchar(256),
    impressions varchar(256),
    match_type varchar(256),
    labels varchar(256),
    criteria varchar(256),
    account_name varchar(256),
    acc varchar(256),
    dt_created varchar(256)
)