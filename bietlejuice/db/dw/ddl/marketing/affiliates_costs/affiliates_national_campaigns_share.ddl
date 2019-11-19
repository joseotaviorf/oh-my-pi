DROP TABLE if EXISTS marketing.affiliates_national_campaigns_share;
CREATE TABLE if NOT EXISTS marketing.affiliates_national_campaigns_share (
    year_month INTEGER,
    tracking_source VARCHAR(64),
    city_group VARCHAR(64),
    share numeric(12,4)
)
;