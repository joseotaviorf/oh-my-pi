SELECT
   p.id,
   p.name,
   p.phone,
   p.email,
   p.cnpj,
   p.creci,
   p.partnershipStartsAt AS ts_joined_partnership,
   p.atualizadoEm AS ts_updated,
   p.criadoEm AS ts_created
FROM
   Partner AS p;