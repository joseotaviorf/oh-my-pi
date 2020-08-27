SELECT
    pa.id,
    pa.status,
    pa.partner_id,
    pa.user_id,
    pa.type,
    pa.atualizadoEm AS ts_updated,
    pa.criadoEm AS ts_created
FROM
PartnerAgent AS pa;
