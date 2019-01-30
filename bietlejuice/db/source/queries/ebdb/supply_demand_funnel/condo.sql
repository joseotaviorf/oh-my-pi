SELECT
  c.id,
  c.atualizadoEm as updated_in,
  c.criadoEm as created_in,
  c.bairro as neighborhood,
  c.cep as zipcode,
  c.cidade as city,
  c.endereco as address,
  c.lat,
  c.lng,
  c.nome as name,
  c.numero as number,
  c.condoManager_id as condo_manager_id,
  c.rules
FROM Condominio c
;