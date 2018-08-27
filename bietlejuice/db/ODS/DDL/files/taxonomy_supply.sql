drop table if exists files.taxonomy_supply;
create table files.taxonomy_supply (
    lead_type varchar(255),
    lead_origin varchar(255),
    lead_utm_medium varchar(255),
    lead_utm_source varchar(255),
    flg_branded numeric(2,1),
    flg_doorman numeric(2,1),
    flg_isales_direct_register numeric(2,1),
    flg_cx_direct_register numeric(2,1),
    flg_isales_intervention numeric(2,1),
    flg_b2b numeric(2,1),
    flg_callcenter numeric(2,1),
    mkt_category varchar(255),
    mkt_flow varchar(255),
    mkt_completion varchar(255),
    mkt_channel_type varchar(255),
    mkt_channel varchar(255),
    mkt_medium varchar(255),
    mkt_source varchar(255),
    mkt_device varchar(255),
    mkt_platform varchar(255)
);