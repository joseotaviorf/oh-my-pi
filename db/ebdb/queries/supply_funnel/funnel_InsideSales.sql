SELECT
    DATE_FORMAT(ADDDATE(cl.dataConversao, INTERVAL 1-DAYOFWEEK(cl.dataConversao) DAY), '%Y-%m-%d') as weekDate,
    DATE_FORMAT(cl.dataConversao,'%Y-%m-%d') AS capturedDate,
    cl.leadConvertido_id,
    cl.imovel_id, 
    IF(dataPublicado IS NOT NULL,cl.imovel_id,NULL) AS published,
    IF(dataPublicado IS NULL,cl.imovel_id,NULL) AS notPublished,
    IF(u.nome IS NULL,'Recaptured',u.nome) AS salesRepName,
    i.id AS imovel_id,
    i.dataCriacao AS imovel_dataCriacao,
    i.recaptadoEm as imovel_dataProspectoQualificado,
    coalesce(f.dataAgendamento, f.dataJobPedido) as imovel_dataAgendamento,
    f.dataUploadFotos as imovel_dataFotogrfo,
    i.firstPublication AS imovel_firstPublication
FROM 
    ConversaoLead cl 
LEFT JOIN
    DadosVendedor dv ON cl.vendedor_id=dv.id
LEFT JOIN 
    Usuario u ON dv.usuario_id=u.id
LEFT JOIN 
    v_ImovelAttribution ia ON cl.imovel_id=ia.id
LEFT JOIN
    Imovel i
    on i.id = cl.imovel_id
LEFT JOIN JobFotografo f
    on f.imovel_id = i.id

WHERE
    cl.status='Concluido'
    AND cl.dataConversao >= '2016-01-01'
    AND cl.imovel_id NOT IN
    (
      SELECT
          ipd2.id
      FROM
          v_ImovelPublicationDetailsFromAUD ipd2
      WHERE
          ipd2.firstPublication IS NULL
          AND
          ipd2.usuarioQueCadastrou_id = 11
    )


