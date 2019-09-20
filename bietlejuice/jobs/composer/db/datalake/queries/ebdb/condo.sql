SELECT
  c.id,
  c.criadoEm AS ts_created,
  c.atualizadoEm AS ts_updated,
  c.bairro AS neighborhood,
  c.cep AS zipcode,
  c.cidade AS city,
  c.endereco AS address,
  c.lat,
  c.lng,
  c.nome AS name,
  c.numero AS number,
  c.condoManager_id AS condo_manager_id,
  c.rules
FROM datalake_ebdb_raw.Condominio c
