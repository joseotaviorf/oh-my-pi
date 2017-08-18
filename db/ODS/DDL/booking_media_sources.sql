drop table if exists booking_media_sources;
create table booking_media_sources (
    app integer,
    app_type VARCHAR(255) DEFAULT NULL::character varying,
    event_time TIMESTAMP WITHOUT TIME ZONE,
    visita_id VARCHAR(255) DEFAULT NULL::character varying,
    media_source VARCHAR(255) DEFAULT NULL::character varying,
    adjust_network VARCHAR(255) DEFAULT NULL::character varying,
    utm_source VARCHAR(255) DEFAULT NULL::character varying,
    utm_campaign VARCHAR(255) DEFAULT NULL::character varying,
    utm_medium VARCHAR(255) DEFAULT NULL::character varying
);