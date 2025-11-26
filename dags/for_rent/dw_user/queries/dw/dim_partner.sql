-- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
WITH amplitude_partner_taxonomy AS (
  SELECT
    id_device,
    utm_campaign,
    utm_medium,
    utm_source,
    year,
    month,
    day
  FROM 
    datalake_amplitude_clean.283048_register_form_completed_events
)
SELECT DISTINCT
  p.id as sk_partner,
  p.id as id_partner,
  p.id_amplitude_device,
  COALESCE(u.country_code, 'Undefined') AS country_code,
  p.name,
  p.trade_name,
  p.phone,
  p.email,
  p.cnpj,
  p.creci,
  p.type,
  p.city,
  st.abbreviation AS state_abbreviation,
  st.name AS state_name,
  CASE WHEN p.city = 'Campinas' THEN 'L009'
       WHEN p.city = 'Santos' THEN 'L012'
             WHEN st.abbreviation = 'SP' OR p.city IN ('São Paulo', 'Guarulhos','Cotia','Taboão da Serra','São Bernardo do Campo','Santo André','Mauá','Osasco',"Santa Bárbara D'Oeste",'Poá','Santana de Parnaíba','Boituva','Jundiaí','Grande São Paulo','São Caetano do Sul','Barueri','Praia Grande') THEN 'L001'
       WHEN st.abbreviation = 'RJ' OR p.city IN ('Rio de Janeiro','São Gonçalo','Itaboraí','Niterói','Duque de Caxias') THEN 'L002'
       WHEN st.abbreviation = 'MG' THEN 'L003'
       WHEN st.abbreviation = 'DF' OR p.city = 'Brasília' THEN 'L004'
       WHEN st.abbreviation = 'GO' OR p.city = 'Goiânia' THEN 'L005'
       WHEN st.abbreviation = 'PR' OR p.city IN ('Fazenda Rio Grande','Curitiba') THEN 'L006'
       WHEN st.abbreviation = 'RS' OR p.city IN ('Viamão','Porto Alegre','Esteio','Canoas') THEN 'L007'
       WHEN st.abbreviation = 'SC' OR p.city = 'Florianópolis' THEN 'L008'
       WHEN st.abbreviation = 'PE' THEN 'L010'
       WHEN st.abbreviation = 'BA' THEN 'L011'
       ELSE p.city
  END AS internal_locality_code,
  LAST_VALUE(apt.utm_campaign) OVER w AS utm_campaign,
  LAST_VALUE(apt.utm_medium) OVER w AS utm_medium,
  LAST_VALUE(apt.utm_source) OVER w AS utm_source,
  p.ts_partnership_started AS ts_joined_partnership,
  p.ts_created,
  p.ts_updated,
  NOW() AS ts_load
FROM
  datalake_ebdb_clean.partner AS p
LEFT JOIN
  amplitude_partner_taxonomy AS apt
    ON p.id_amplitude_device = apt.id_device
LEFT JOIN
  datalake_ebdb_clean.partner_agent AS pa
    ON pa.id_partner = p.id
LEFT JOIN 
  datalake_ebdb_country.user AS u
    ON pa.id_user = u.id_user
LEFT JOIN
  datalake_ebdb_clean.state AS st
    ON p.id_state = st.id
WINDOW w AS (PARTITION BY apt.id_device ORDER BY apt.year, apt.month, apt.DAY ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)