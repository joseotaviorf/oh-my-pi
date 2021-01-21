--drop view if exists vw_acquisitions;
--create or replace view vw_acquisitions as
with legacy_doorman AS (
  SELECT
    porteiros_legado."Status" AS status,
    892700000 + porteiros_legado."Cod Imóvel"::double precision::BIGINT AS imovel_id
  FROM gsheets.porteiros_legado
  WHERE (porteiros_legado."Status" IN ('Listing', 'Alugado', 'Foto', 'Foto com problema', 'Lead'))
    AND porteiros_legado."Cod Imóvel" IS NOT NULL
)
SELECT
    f.id,
    CASE
      WHEN d.imovel_id IS NOT NULL AND f.is_not_reprocessed THEN 'Lead Flow'
      ELSE f.flow
    END AS flow,
    CASE
      WHEN d.imovel_id IS NOT NULL AND f.is_not_reprocessed THEN 'Non-Self Service'
      ELSE f.acquisition_method
    END AS acquisition_method,
    CASE
      WHEN d.imovel_id IS NOT NULL AND f.is_not_reprocessed THEN 'Doorman'
      ELSE f.acquisition_channel_rep
    END AS acquisition_channel,
    CASE
      WHEN d.imovel_id IS NOT NULL AND f.is_not_reprocessed THEN 'Doorman'
      ELSE f.acquisition_source
    END AS acquisition_source,
    CASE
      WHEN d.imovel_id IS NOT NULL AND f.is_not_reprocessed THEN true
      ELSE f.acquisition_source = 'Doorman'
    END AS is_doorman
FROM listing_flows_with_reprocessed_leads AS f
LEFT JOIN legacy_doorman AS d
  ON f.imovel_id = d.imovel_id
