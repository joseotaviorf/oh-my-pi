drop table if exists gsheets.taxonomy_affiliates;
create table gsheets.taxonomy_affiliates (
    affiliate_type varchar(255),
    tracking_source varchar(255),
    tracking_medium varchar(255),
    tracking_campaign varchar(255),
    mkt_origin varchar(255),
    mkt_channel varchar(255),
    mkt_medium varchar(255),
    mkt_source varchar(255)
);