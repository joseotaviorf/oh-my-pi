SELECT
   p.id,
   p.amplitudeDeviceId as id_amplitude_device,
   p.name,
   p.phone,
   p.email,
   p.cnpj,
   p.creci,
   p.type,
   p.city,
   p.partnershipStartsAt AS ts_joined_partnership,
   p.atualizadoEm AS ts_updated,
   p.criadoEm AS ts_created,
   p.tradeName as trade_name
FROM
   Partner AS p;
