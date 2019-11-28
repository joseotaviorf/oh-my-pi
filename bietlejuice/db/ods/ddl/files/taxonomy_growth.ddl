drop table if exists files.taxonomy_growth;
create table files.taxonomy_growth (
    lead_type varchar(255),
    lead_origin varchar(255),
    lead_tracking_medium varchar(255),
    lead_tracking_source varchar(255),
    affiliate_type varchar(255),
    lead_referring_category varchar(512),
    is_branded numeric(2,1),
    is_ops_direct_register numeric(2,1),
    mkt_origin varchar(255),
    mkt_channel varchar(255),
    mkt_medium varchar(255),
    mkt_source varchar(255)
);