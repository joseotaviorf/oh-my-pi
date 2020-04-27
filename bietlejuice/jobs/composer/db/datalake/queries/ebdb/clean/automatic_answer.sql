SELECT
    id,
    criadoEm as ts_created,
    enviadaEm as ts_sent,
    mensagem as message,
    origem as origin,
    recebidaEm as ts_received,
    atendente_id as id_attendant,
    imovel_id as id_house,
    usuario_id as id_user,
    atualizadoEm as ts_updated,
    origemRedirect as origin_redirect,
    tipoConta as account_type,
    usuarioClassificado_id as id_user_classified,
    tenantLead_id as id_tenant_lead,
    enviadoWhatsappEm as ts_sent_whatsapp
FROM
    datalake_ebdb_raw.respostaautomatica