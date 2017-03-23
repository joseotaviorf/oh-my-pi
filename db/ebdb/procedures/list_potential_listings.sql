DROP PROCEDURE IF EXISTS ebdb.list_potential_listings;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_potential_listings(IN _ref_date DATE)
BEGIN

 SELECT
    r.*,
    CASE   
        WHEN r.lead_id is not null and r.lead_tipo = 'Afiliado' THEN 'Affiliates' 
        
        WHEN r.lead_id is not null and r.lead_tipo <> 'Afiliado' THEN 'Other Lead (Marketing, Crawler...)' 
       
        WHEN r.lead_id is null and r.imovel_attribution = 'Self-Service' THEN 'Self-Service'       
       
        WHEN r.lead_id is null and (r.vendedor_id IS NOT NULL OR r.tipo_admin <> 'Normal' or r.attribution_type = 'Organic/Duplicate/Referred Leads') THEN 'Inside Sales - Organic'       
        
        ELSE 'Unknown' 
    END AS funnel_source,
  
    affiliate_listing_value + affiliate_renting_value as cac_affiliate,
    0.0000 as cac_marketing,
    0.0000 as cac_photo,
    0.0000 as cac_inside_sales,

    TIMESTAMPDIFF(MINUTE, r.contact_date, r.lead_date) as contact_to_lead_diff_minutes,  
    TIMESTAMPDIFF(MINUTE, r.lead_date, r.qualified_date) as lead_to_qualified_diff_minutes,
    TIMESTAMPDIFF(MINUTE, r.qualified_date, r.opportunity_date) as qualified_to_opportunity_diff_minutes,
    TIMESTAMPDIFF(MINUTE, r.opportunity_date, r.listing_publication_date) as opportunity_to_listing_diff_minutes,
    TIMESTAMPDIFF(MINUTE, r.listing_publication_date, r.contract_date) as listing_to_1stcontract_diff_minutes,  
    TIMESTAMPDIFF(MINUTE, r.contact_date, r.listing_publication_date) as contact_to_listing_diff_minutes,  
    TIMESTAMPDIFF(MINUTE, r.contact_date, r.contract_date) as contact_to_1stcontract_diff_minutes
  
  FROM
  (
    SELECT
      coalesce(o.updated_date, o.created_date) as ref_date,
      o.created_date,
      o.updated_date,
      coalesce(ai.id, au.id) as attribution_id,
      coalesce(ai.uuid, au.uuid) as attribution_uuid,
      
      coalesce(o.lead_criadoEm, o.lead_timestamp, o.dataConversao) as contact_date,
      coalesce(o.lead_timestamp, o.dataConversao, o.lead_criadoEm) as lead_date,  
      o.prospect_date,
      
      o.first_inside_sales_contact_date,
      
      case when ia.imovelAttribution='Self-Service'
        then f.dataCriacao 
        else o.qualified_date
      end as qualified_date,

      case 
        when coalesce(f.dataInicioSessao, f.dataAgendamento, f.dataCriacao)  <='1900-01-01' then NULL 
        ELSE coalesce(f.dataInicioSessao, f.dataAgendamento, f.dataCriacao)
      END as opportunity_date,

      ip.datePublication AS listing_publication_date,
      cast(c.dataInicio as datetime) as contract_date,
    
      o.lead_id AS lead_id,
      
      o.imovel_id AS property_id,
      c.id as contract_id,
      o.aluguel as renting_value,    
      o.status as current_property_status,
      
      f.dadosFotografo_id as dados_fotografo_id,
      coalesce(o.usuario_id, o.proprietarioLead_id) AS owner_id,
      o.usuarioQueCadastrou_id AS rep_id,
      g.id as manager_id,
      o.vendedor_id,
      u.tipoAdmin AS tipo_admin ,
  
      ia.imovelAttribution as imovel_attribution,
      o.lead_tipo as lead_tipo,
      
      CASE 
        WHEN ia.imovelAttribution='Self-Service' THEN 'Self-Service'
      	WHEN ia.lead_tipo='Afiliado' AND ia.lead_origem='App' THEN 'Affiliate App'
      	WHEN ia.lead_tipo='Afiliado' AND ia.lead_origem='Form' THEN 'Affiliate Form'
      	WHEN ia.lead_tipo='Afiliado' AND ia.lead_origem='Planilha' THEN 'Affiliate Spreadsheet'
      	WHEN ia.conversao_tipo='Lead' AND ia.lead_tipo='Marketing' AND ia.lead_origem='Landing' THEN 'Landing Page Leads'
      	WHEN ia.conversao_tipo='Lead' AND ia.lead_tipo='Marketing' AND ia.lead_origem<>'Landing' THEN 'Marketing Leads'
       	WHEN ia.conversao_tipo='InsideSales' THEN 'Organic/Duplicate/Referred Leads'
      	WHEN ia.lead_tipo='Afiliado' AND ia.lead_origem='Desconhecida' THEN 'Affiliate Unknown'
      	WHEN ia.conversao_tipo='Lead' THEN 'Other Lead Source'
      	WHEN ia.imovelAttribution NOT IN ('Self-Service','Undetermined') THEN 'Organic/Duplicate/Referred Leads'
      	ELSE 'Unknown' 
      END AS attribution_type,
    	CASE 
        WHEN ia.imovelAttribution='Self-Service' THEN 'Self-Service'
      	WHEN ia.lead_tipo='Afiliado' THEN 'Affiliate Lead'
      	WHEN ia.conversao_tipo='Lead' AND ia.lead_tipo='Marketing' AND ia.lead_origem='Landing' THEN 'Landing Page Lead'
      	WHEN ia.conversao_tipo='Lead' AND ia.lead_tipo='Marketing' AND ia.lead_origem<>'Landing' THEN 'Marketing Lead'
     	  WHEN ia.conversao_tipo='InsideSales' THEN 'Organic/Duplicate/Referred Lead'
    	  WHEN ia.conversao_tipo='Lead' THEN 'Other Lead Source'
    	  WHEN ia.imovelAttribution NOT IN ('Self-Service','Undetermined') THEN 'Organic/Duplicate/Referred Lead'
    	  ELSE 'Unknown' 
      END AS attribution_category,
  
      case 
        when o.lead_tipo = 'Afiliado' and ip.datePublication is not null then 25 else 0 
      end as affiliate_listing_value,
    
      case 
        when o.lead_tipo = 'Afiliado' and cast(c.dataInicio as datetime) is not null then o.aluguel*.1 else 0 
      end as affiliate_renting_value
  
    FROM 
    (
      SELECT
        lead_id,
        proprietarioLead_id,
        lead_tipo,
        lead_criadoEm,
        lead_timestamp,
        dataConversao,
        cl_criadoEm,
        imovel_id,
        aluguel,
        status,
        recaptadoEm,
        usuario_id,
        usuarioQueCadastrou_id,
        vendedor_id,
        tipoAdmin,
        min(o.prospect_date) as prospect_date,
        min(o.first_inside_sales_contact_date) as first_inside_sales_contact_date,
        min(o.qualified_date) as qualified_date,   --  sera q nao serviria f.dataCriacao ??
        max(o.created_date) as created_date,
        max(o.updated_date) as updated_date
      FROM
      (
        SELECT
          l.id as lead_id,
          l.proprietarioLead_id,
          l.tipo as lead_tipo,
          l.criadoEm as lead_criadoEm,
          from_unixtime(lu.timestamp/1000) as lead_timestamp,
          cl.dataConversao,
          cl.criadoEm as cl_criadoEm,
          i.id as imovel_id,
          i.aluguel,
          i.status,
          i.recaptadoEm,
          i.usuario_id,
          i.usuarioQueCadastrou_id,
          cl.vendedor_id,
          u.tipoAdmin,
          lfu.firstUpdateDate as first_inside_sales_contact_date,
          null as prospect_date,
          -- coalesce(cl.dataConversao, cl.criadoEm, from_unixtime(lu.timestamp/1000)) as qualified_date,
          CASE WHEN cl.leadConvertido_id IS NOT NULL
            THEN coalesce(cl.dataConversao, cl.criadoEm, from_unixtime(lu.timestamp/1000)) -- if there is a match with the table conversaolead, we can substitute the dataconversao by criadoEm in case dataconversao is missing
          END as qualified_date,
          coalesce(l.criadoEm, l.anuncioCriadoEm, l.captadoEm) as created_date,
          l.atualizadoEm as updated_date
        FROM
          Lead l
         
        LEFT JOIN v_LeadFirstUpdate lfu
          on lfu.id = l.id

        LEFT JOIN 
          Lead_AUD lre
          ON l.id = lre.id
          and lre.REV = (
            SELECT
              a.REV            
            from
              Lead_AUD a  
            where
              a.id = l.id
              and (
                   (a.processado = 1 and processado_MOD = 1 and coalesce(a.automaticallyDiscarded, false) = false)
                    or (a.status_MOD = 1 and a.status != 'Descartado')
                  )
        
            order by 
              rev asc
            limit 1
          ) 
      
        LEFT JOIN
          UsuarioRevisionEntity lu
          on lu.id = lre.REV    
        
        LEFT JOIN 
          ConversaoLead cl
          ON cl.leadConvertido_id = l.id
          -- and cl.status = 'Concluido'
          and cl.tipo = 'Lead'
      
        LEFT JOIN
          Imovel i
          on i.id = cl.imovel_id
      
        LEFT JOIN
          Usuario u
          on u.id = i.usuario_id

        UNION
      
        SELECT
          l.id as lead_id,
          l.proprietarioLead_id,
          l.tipo as lead_tipo,
          l.criadoEm as lead_criadoEm,
          from_unixtime(lu.timestamp/1000) as lead_timestamp,
          cl.dataConversao,
          cl.criadoEm as cl_criadoEm,
          i.id as imovel_id,
          i.aluguel,
          i.status,
          i.recaptadoEm,
          i.usuario_id,
          i.usuarioQueCadastrou_id,
          cl.vendedor_id,
          u.tipoAdmin,
          null as first_inside_sales_contact_date,
          dt_etapa_endereco as prospect_date,
          null  as qualified_date,
          coalesce(l.criadoEm, l.anuncioCriadoEm, l.captadoEm, i.dataCriacao) as created_date,
          coalesce(l.atualizadoEm, i.atualizadoEm)  as updated_date
        FROM
          Imovel i
        LEFT JOIN 
        (
          select
            ie.imovel_id,
            min(ie.data) as dt_etapa_endereco
          from
            Imovel_Etapas ie
          where 
            ie.etapa = 'MOB_ENDERECO'            
          group BY
            ie.imovel_id
        ) ie
          on ie.imovel_id = i.id 
                   
        LEFT JOIN ConversaoLead cl
          on cl.imovel_id = i.id
          
        left join Lead l
          on l.id = cl.leadConvertido_id
        LEFT JOIN 
          Lead_AUD lre
          ON l.id = lre.id
          and lre.REV = (
            SELECT
              a.REV            
            from
              Lead_AUD a  
            where
              a.id = l.id
              and (
                   (a.processado = 1 and processado_MOD = 1 and coalesce(a.automaticallyDiscarded, false) = false)
                    or (a.status_MOD = 1 and a.status != 'Descartado')
                  )
        
            order by 
              rev asc
            limit 1
        ) 
        LEFT JOIN
          UsuarioRevisionEntity lu
          on lu.id = lre.REV  
        left join Usuario u
          on u.id = i.usuario_id 
      ) o
      GROUP BY
        lead_id,
        proprietarioLead_id,
        lead_tipo,
        lead_criadoEm,
        lead_timestamp,
        dataConversao,
        cl_criadoEm,
        imovel_id,
        aluguel,
        status,
        recaptadoEm,
        usuario_id,
        usuarioQueCadastrou_id,
        vendedor_id,
        tipoAdmin
    ) o
  
    LEFT JOIN 
      v_ImovelStatusHistory ip
      on ip.id = o.imovel_id
      and ip.published = 1
  
    left join  -- v_imovel_attribution modified to get properties without first_publication
    (
      SELECT
        `ipd`.`id` AS `id`,
        `ipd`.`status` AS `status`,
        `ipd`.`firstPublication` AS `firstPublication`,
        `ipd`.`usuario_id` AS `usuario_id`,
        `ipd`.`usuarioQueCadastrou_id` AS `usuarioQueCadastrou_id`,
        `ipd`.`usuarioQueCadastrou_ativo` AS `usuarioQueCadastrou_ativo`,
        `u2`.`nome` AS `quemCadastrou`,
        `ipd`.`dataPublicado` AS `dataPublicado`,
        `ipd`.`usuarioQuePublicou_id` AS `usuarioQuePublicou_id`,
        `ipd`.`usuarioQuePublicou_ativo` AS `usuarioQuePublicou_ativo`,
        `ipd`.`nome` AS `quemPublicou`,
        `cl`.`id` AS `ConversaoLead_id`,
        `cl`.`dataConversao` AS `dataConversao`,
        `cl`.`tipo` AS `conversao_tipo`,
        `cl`.`leadConvertido_id` AS `Lead_id`,
        `l`.`tipo` AS `lead_tipo`,
        `l`.`origem` AS `lead_origem`,
        `cl`.`vendedor_id` AS `vendedor_id`,
        `u`.`nome` AS `quemConverteu`,
        `u`.`id` AS `quemConverteu_id`,
        `dv`.`ativo` AS `quemConverteu_ativo`,
        `l`.`captadoEm` AS `lead_captadoEm`,
        `l`.`anuncioCriadoEm` AS `lead_anuncioCriadoEm`,
        `l`.`criadoEm` AS `lead_criadoEm`,
        `l`.`atualizadoEm` AS `lead_atualizadoEm`,
        (CASE WHEN ((`ipd`.`usuario_id` = `ipd`.`usuarioQueCadastrou_id`) AND
            (`u2`.`tipoAdmin` = 'Normal')) THEN 'Self-Service' WHEN ((COALESCE(`dv`.`ativo`, `ipd`.`usuarioQueCadastrou_ativo`, `ipd`.`usuarioQuePublicou_ativo`) = 1) AND
            (`ipd`.`usuarioQueCadastrou_id` = 11)) THEN COALESCE(`u`.`nome`, `ipd`.`nome`, `u2`.`nome`) WHEN ((COALESCE(`dv`.`ativo`, `ipd`.`usuarioQueCadastrou_ativo`, `ipd`.`usuarioQuePublicou_ativo`) = 1) AND
            (`ipd`.`usuarioQueCadastrou_id` <> 11)) THEN COALESCE(`u`.`nome`, `u2`.`nome`, `ipd`.`nome`) WHEN (COALESCE(`dv`.`ativo`, `ipd`.`usuarioQueCadastrou_ativo`, `ipd`.`usuarioQuePublicou_ativo`) = 1) THEN COALESCE(`u`.`nome`, `u2`.`nome`, `ipd`.`nome`) WHEN (COALESCE(`dv`.`ativo`, `ipd`.`usuarioQueCadastrou_ativo`, `ipd`.`usuarioQuePublicou_ativo`) = 0) THEN 'Inactive' WHEN (ISNULL(COALESCE(`u`.`nome`, `u2`.`nome`, `ipd`.`nome`)) AND
            (`ipd`.`dataPublicado` IS NOT NULL)) THEN 'Undetermined' WHEN (COALESCE(`u`.`nome`, `u2`.`nome`, `ipd`.`nome`) IS NOT NULL) THEN 'Recaptured' ELSE NULL END) AS `imovelAttribution`
      FROM
      (
        SELECT
          `fip`.`id` AS `id`,
          `i`.`firstPublication` AS `firstPublication`,
          `i`.`status` AS `status`,
          `fip`.`REV` AS `REV`,
          (CAST('1970-01-01' AS date) + INTERVAL ROUND((`ure`.`timestamp` / 1000), 0) SECOND) AS `dataPublicado`,
          `u`.`nome` AS `nome`,
          `u`.`id` AS `usuarioQuePublicou_id`,
          `dv`.`ativo` AS `usuarioQuePublicou_ativo`,
          `df`.`id` AS `DadosFotografo_id`,
          `dv`.`id` AS `DadosVendedor_id`,
          `i`.`usuario_id` AS `usuario_id`,
          `i`.`usuarioQueCadastrou_id` AS `usuarioQueCadastrou_id`,
          `dv2`.`id` AS `usuarioQueCadastrouVendedor_id`,
          `dv2`.`ativo` AS `usuarioQueCadastrou_ativo`
        FROM ((((((`v_FirstImovelFromAUD` `fip`
          JOIN `Imovel` `i`
            ON ((`fip`.`id` = `i`.`id`)))
          LEFT JOIN `UsuarioRevisionEntity` `ure`
            ON ((`fip`.`REV` = `ure`.`id`)))
          LEFT JOIN `Usuario` `u`
            ON ((`ure`.`usuario_id` = `u`.`id`)))
          LEFT JOIN `DadosFotografo` `df`
            ON ((`u`.`dadosFotografo_id` = `df`.`id`)))
          LEFT JOIN `DadosVendedor` `dv`
            ON ((`ure`.`usuario_id` = `dv`.`usuario_id`)))
          LEFT JOIN `DadosVendedor` `dv2`
            ON ((`i`.`usuarioQueCadastrou_id` = `dv2`.`usuario_id`)))
        
        -- WHERE fip.id = 892791756
        
        ORDER BY `fip`.`id`
        
      )`ipd`
    
      LEFT JOIN `ConversaoLead` `cl`
        ON `ipd`.`id` = `cl`.`imovel_id`
      LEFT JOIN `Lead` `l`
        ON `cl`.`leadConvertido_id` = `l`.`id`
      LEFT JOIN `DadosVendedor` `dv`
        ON `cl`.`vendedor_id` = `dv`.`id`
      LEFT JOIN `Usuario` `u`
        ON `dv`.`usuario_id` = `u`.`id`
      LEFT JOIN `Usuario` `u2`
        ON `ipd`.`usuarioQueCadastrou_id` = `u2`.`id`
      WHERE `ipd`.`usuarioQueCadastrou_id` <> 11   
      ORDER BY `ipd`.`id`    
    ) ia
    on ia.id = o.imovel_id
  
    left join JobFotografo f
      on f.id = (
      select
        max(id)
      from
        JobFotografo j
      where
        j.imovel_id = o.imovel_id
        and (j.dataCriacao <= ip.datePublication or ip.datePublication is null)
        and j.status != 'Cancelado'
    )
  
    LEFT JOIN 
      DadosVendedor dv
      ON o.vendedor_id = dv.id
  
    LEFT JOIN 
      Usuario u
      ON dv.usuario_id = u.id
    
    left join
      Usuario g
      on dv.gerente_id = g.id
    
    left join 
      v_Aquisicao ai
      on ai.imovel_id = o.imovel_id
      and ai.tipo = 'Imovel'
    
    left join
      v_Aquisicao au
      on au.usuario_id = u.id
      and au.tipo = 'Usuario'
    
    left JOIN
      Contrato c
      on c.id = (select c2.id from Contrato c2 where c2.imovel_id = o.imovel_id and c2.dataInicio >= ip.datePublication order BY c2.id limit 1)
  
      -- where o.imovel_id in (892784681, 892763276,892791756 )
      -- year(o.ref_date)= 2016
      -- and month(o.ref_date) >= 11
      -- and  l.id = 319376
      -- and l.id = 261579
      -- and l.id = 331494
      -- l.id = 43106
  )r

WHERE
  cast(r.ref_date as date) >= coalesce(_ref_date, '2012-12-01')
-- order BY
--  1

-- call list_potential_listings(null)
;

END