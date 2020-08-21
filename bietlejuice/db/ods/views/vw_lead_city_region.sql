--drop view if exists vw_lead_city_region;
--create or replace view vw_lead_city_region as
with city_region as (
  select
    region.id as id_region,
    regexp_replace(remove_accentuation(lower(region.nome)), '[^a-z]+', '', 'g') as formatted_city
  from region
  where region.nivel = 'Cidade'
)
  select
    l.id as id_lead,
    r.id_region
  from lead l
  join city_region r
    on r.formatted_city = regexp_replace(remove_accentuation(lower(l.cidade)), '[^a-z]+', '', 'g')
