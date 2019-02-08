drop table if exists lead_origin;
create table lead_origin (
    id_lead integer,
    firestore_id varchar(255),
    device_id varchar(255),
    rule_num integer,
    rule varchar(50),
    event_time varchar(50),
    u_initial_utm_campaign varchar(255),
    u_initial_utm_medium varchar(255),
    u_initial_utm_source varchar(255),
    u_platform varchar(255),
    region varchar(255),
    city varchar(255),
    uuid varchar(255),
    rn integer
);