CREATE TABLE IF NOT EXISTS temp_listings (

SELECT
    r.*,
    CASE   
        WHEN r.lead_id is not null and r.lead_tipo = 'Afiliado' THEN 'Affiliates' 
        
        WHEN r.lead_id is not null and r.lead_tipo <> 'Afiliado' THEN 'Other Lead (Marketing, Crawler...)' 
       
        WHEN r.lead_id is null and r.imovelAttribution = 'Self-Service' THEN 'Self-Service'       
       
        WHEN r.lead_id is null and (r.vendedor_id IS NOT NULL OR r.tipoAdmin <> 'Normal' or r.attribution_type = 'Organic/Duplicate/Referred Leads') THEN 'Inside Sales - Organic'       
        
        ELSE 'Unknown' 
    END AS funnel_source,
  
    affiliate_listing_value + affiliate_renting_value as CAC_affiliate,
    0.0000 as CAC_marketing,
    0.0000 as CAC_photo,
    0.0000 as CAC_inside_sales
    ,
    TIMEDIFF(r.lead_date, r.contact_date) as contact_to_lead_diff_datetime,
    TIMESTAMPDIFF(MINUTE, r.contact_date, r.lead_date) as contact_to_lead_diff_minutes,
  
    TIMEDIFF(r.qualified_date, r.lead_date) as lead_to_qualified_diff_datetime,
    TIMESTAMPDIFF(MINUTE, r.lead_date, r.qualified_date) as lead_to_qualified_diff_minutes,
  
    TIMEDIFF(r.opportunity_date, r.qualified_date) as qualified_to_opportunity_diff_datetime,
    TIMESTAMPDIFF(MINUTE, r.qualified_date, r.opportunity_date) as qualified_to_opportunity_diff_minutes,
  
    TIMEDIFF(r.listing_publication_date, r.opportunity_date) as opportunity_to_listing_diff_datetime,
    TIMESTAMPDIFF(MINUTE, r.opportunity_date, r.listing_publication_date) as opportunity_to_listing_diff_minutes,
  
    TIMEDIFF(r.contract_date, r.listing_publication_date) as listing_to_1stcontract_diff_datetime,
    TIMESTAMPDIFF(MINUTE, r.listing_publication_date, r.contract_date) as listing_to_1stcontract_diff_minutes,
  
    TIMEDIFF(r.listing_publication_date, r.contact_date) as contact_to_listing_diff_datetime,
    TIMESTAMPDIFF(MINUTE, r.contact_date, r.listing_publication_date) as contact_to_listing_diff_minutes,
  
    TIMEDIFF(r.contract_date, r.contact_date) as contact_to_1stcontract_diff_datetime,
    TIMESTAMPDIFF(MINUTE, r.contact_date, r.contract_date) as contact_to_1stcontract_diff_minutes
  
FROM
  (
    SELECT
      coalesce(o.updated_date, o.created_date) as ref_date,
      o.created_date,
      o.updated_date,
      coalesce(ai.id, au.id) as attribution_id,
      coalesce(ai.uuid, au.uuid) as attribution_uuid,
      
      o.lead_criadoEm as contact_date,
      coalesce(from_unixtime(o.lead_timestamp/1000), o.dataConversao, o.lead_criadoEm) as lead_date,  
      coalesce(o.dataConversao, o.cl_criadoEm, f.dataCriacao, ip.datePublication) AS qualified_date,  
      coalesce(f.dataCriacao, ip.datePublication) as opportunity_date,
      ip.datePublication AS listing_publication_date,
      cast(c.dataInicio as datetime) as contract_date,
    
      o.lead_id AS lead_id,
      
      o.imovel_id AS property_id,
      o.aluguel as renting_value,    
      o.status as current_property_status,
      
      f.dadosFotografo_id,
      coalesce(o.usuario_id, o.proprietarioLead_id) AS owner_id,
      o.usuarioQueCadastrou_id AS rep_id,
      g.id as manager_id,
      o.vendedor_id,
      u.tipoAdmin AS tipoAdmin ,
  
      ia.imovelAttribution,
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
        l.id as lead_id,
        l.proprietarioLead_id,
        l.tipo as lead_tipo,
        l.criadoEm as lead_criadoEm,
        lu.timestamp as lead_timestamp,
        cl.dataConversao,
        cl.criadoEm as cl_criadoEm,
        i.id as imovel_id,
        i.aluguel,
        i.status,
        i.usuario_id,
        i.usuarioQueCadastrou_id,
        cl.vendedor_id,
        u.tipoAdmin,
        coalesce(l.criadoEm, l.anuncioCriadoEm, l.captadoEm) as created_date,
        l.atualizadoEm as updated_date
      FROM
        Lead l
       
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
      
      UNION ALL
  
      SELECT
        l.id as lead_id,
        l.proprietarioLead_id,
        l.tipo as lead_tipo,
        l.criadoEm as lead_criadoEm,
        null as lead_timestamp,
        cl.dataConversao,
        cl.criadoEm as cl_criadoEm,
        i.id as imovel_id,
        i.aluguel,
        i.status,
        i.usuario_id,
        i.usuarioQueCadastrou_id,
        cl.vendedor_id,
        u.tipoAdmin,
        i.dataCriacao as created_date,
        i.atualizadoEm  as updated_date
      FROM
        Imovel i
      LEFT JOIN ConversaoLead cl
        on cl.imovel_id = i.id
        -- and cl.status = 'Concluido'
      left join Lead l
        on l.id = cl.leadConvertido_id
      left join Usuario u
        on u.id = i.usuario_id
    ) o
  
    left join
      JobFotografo f
      on f.imovel_id = o.imovel_id
      and f.status != 'Cancelado'
  
    LEFT JOIN 
      v_ImovelStatusHistory ip
      on ip.id = o.imovel_id
      and ip.published = 1
  
    left join v_ImovelAttribution_v2 ia
      on ia.id = o.imovel_id
  
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
      on c.id = (select c2.id from Contrato c2 where c2.imovel_id = f.imovel_id and c2.dataInicio >= coalesce(f.dataCriacao, ip.datePublication) order BY c2.id limit 1)
        
  ) r
-- WHERE
--   cast(r.ref_date as date) >= coalesce(_ref_date, '2012-12-01')
      -- and year(o.ref_date)= 2016
      -- and month(o.ref_date) >= 8
      -- and  l.id = 319376
      -- and l.id = 261579
      -- and l.id = 331494
      -- l.id = 43106
      -- f.imovel_id = 892769803
order BY
  1
);

show create table temp_listings;
