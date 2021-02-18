drop table if exists public.amplitude_partner_taxonomy;
create external table if not exists public.amplitude_partner_taxonomy (
    id_device varchar,
    utm_campaign varchar,
    utm_medium varchar,
    utm_source varchar,
    year integer,
    month integer,
    day integer
)