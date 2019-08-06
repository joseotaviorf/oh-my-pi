drop table if exists files.taxonomy_supply;
create table files.taxonomy_supply (
    lead_type varchar(255),
    lead_origin varchar(255),
    lead_tracking_medium varchar(255),
    lead_tracking_source varchar(255),
    affiliate_type varchar(255),
    lead_referring_domain varchar(512),
    subscription_source varchar(512),
    is_branded numeric(2,1),
    is_isales_direct_register numeric(2,1),
    is_cx_direct_register numeric(2,1),
    has_isales_intervention numeric(2,1),
    is_b2b numeric(2,1),
    is_call_center numeric(2,1),
    mkt_origin varchar(255),
    mkt_channel varchar(255),
    mkt_medium varchar(255),
    mkt_source varchar(255)
);