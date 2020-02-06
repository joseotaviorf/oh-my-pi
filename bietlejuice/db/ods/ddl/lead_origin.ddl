drop table if exists lead_origin;
create table lead_origin (
    id_lead integer,
    firestore_id varchar(255),
    e_formfield_lead_uuid varchar(255),
    rule_num integer,
    event_time varchar(50),
    up_utm_campaign varchar(255),
    up_utm_medium varchar(255),
    up_utm_source varchar(255),
    up_utm_content varchar(255),
    up_utm_term varchar(255),
    up_platform varchar(255),
    up_referring_domain varchar(255),
    region varchar(255),
    city varchar(255),
    uuid varchar(255)
);