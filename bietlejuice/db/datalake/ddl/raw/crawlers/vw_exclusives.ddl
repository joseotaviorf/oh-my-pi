CREATE OR REPLACE VIEW "vw_exclusives" AS
with dataset as (
  select ce.*,
    sc.criadoem,
    sc.expirationdate,
    max(sc.criadoem) over (partition by sc.imovel_id) last_criadoem
  from crawled_exclusive ce
  join ebdb_specialcondition sc
    on sc.imovel_id = ce.id
  where cast(if(sc.criadoem <> '', sc.criadoem) as timestamp) <= date(ce.match_em)
    and sc.specialconditiontype = 'Exclusivity'
) select * from dataset where criadoem = last_criadoem