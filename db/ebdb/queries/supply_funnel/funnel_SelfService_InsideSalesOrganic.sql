SELECT 
   (CASE   
      WHEN (`i`.`usuario_id` = `i`.`usuarioQueCadastrou_id` AND `u`.`tipoAdmin` = 'Normal') THEN 'Self-Service'       
      WHEN `dv`.`id` IS NOT NULL OR `u`.`tipoAdmin` <> 'Normal' THEN 'Inside Sales Organic'       
      ELSE 'Unknown' 
    END) AS `origin`,
  `i`.`id` AS `imovel_id`,
  `i`.`dataCriacao` AS `imovel_dataCriacao`,
  i.recaptadoEm as imovel_dataProspectoQualificado,
  coalesce(f.dataAgendamento, f.dataJobPedido) as imovel_dataAgendamento,
  f.dataUploadFotos as imovel_dataFotogrfo,
  `i`.`firstPublication` AS `imovel_firstPublication`,
  `i`.`usuario_id` AS `usuario_id`,
  `i`.`usuarioQueCadastrou_id` AS `usuarioQueCadastrou_id`,
  `u`.`tipoAdmin` AS `tipoAdmin`,
  `dv`.`id` AS `DadosVendedor_id`  
FROM 
  Imovel i
  
  LEFT JOIN `Usuario` `u`
    ON `i`.`usuarioQueCadastrou_id` = `u`.`id`
  
  LEFT JOIN `DadosVendedor` `dv`
    ON `u`.`id` = `dv`.`usuario_id`

  LEFT JOIN JobFotografo f
    on f.imovel_id = i.id

  LEFT JOIN ConversaoLead cl
    on cl.imovel_id = i.id

where 
  year(coalesce(i.`firstPublication`, i.dataCriacao)) = 2016  
  and cl.id is null

ORDER BY 
  1
