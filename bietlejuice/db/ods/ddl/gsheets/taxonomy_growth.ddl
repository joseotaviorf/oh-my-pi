drop table if exists gsheets.taxonomy_growth;
create table gsheets.taxonomy_growth (
    affiliate_type varchar(255),
    is_agent_referral varchar(255),
    is_branded varchar(255),
    is_ops_direct_register varchar(255),
    lead_origin varchar(255),
    lead_referring_category varchar(512),
    lead_tracking_medium varchar(255),
    lead_tracking_source varchar(255),
    lead_type varchar(255),
    mkt_channel varchar(255),
    mkt_medium varchar(255),
    mkt_origin varchar(255),
    mkt_source varchar(255)
);