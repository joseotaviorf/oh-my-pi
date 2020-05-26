drop table if exists offer_submitted_events;
create table offer_submitted_events (
    dt_event date,
    ts_event TIMESTAMP WITHOUT TIME ZONE,
    id_app integer,
    app_type VARCHAR(255) DEFAULT NULL::character varying,
    id_user VARCHAR(255) DEFAULT NULL::character varying,
    id_house VARCHAR(255) DEFAULT NULL::character varying,
    id_firestore VARCHAR(255) DEFAULT NULL::character varying,
    utm_source VARCHAR(255) DEFAULT NULL::character varying,
    utm_medium VARCHAR(255) DEFAULT NULL::character varying,
    utm_campaign VARCHAR(2000) DEFAULT NULL::character varying,
    utm_content VARCHAR(255) DEFAULT NULL::character varying,
    utm_term VARCHAR(255) DEFAULT NULL::character varying,
    branded VARCHAR(255) DEFAULT NULL::character varying
);