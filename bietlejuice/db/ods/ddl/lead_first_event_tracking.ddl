drop table if exists lead_first_event_tracking;
create table lead_first_event_tracking (
    id_lead integer,
    tracking_campaign varchar(255),
    tracking_medium varchar(255),
    tracking_source varchar(255),
    tracking_content varchar(255),
    tracking_term varchar(255),
    tracking_platform varchar(255),
    tracking_referring_domain varchar(255),
    tracking_region varchar(255),
    tracking_city varchar(255)
);

create index lead_first_event_tracking_id_lead_idx on lead_first_event_tracking (id_lead);
