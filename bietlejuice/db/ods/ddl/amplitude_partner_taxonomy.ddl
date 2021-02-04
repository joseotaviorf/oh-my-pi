drop table if exists public.amplitude_partner_taxonomy;
create external table if not exists public.amplitude_partner_taxonomy (
    id_device integer,
    utm_campaign string,
    utm_medium string,
    utm_source string,
    year integer,
    month integer,
    day integer
)