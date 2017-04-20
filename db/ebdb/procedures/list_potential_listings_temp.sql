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
      coalesce(p.updated_date, p.created_date) as ref_date,
      p.created_date,
      p.updated_date,
      coalesce(ai.id, au.id) as attribution_id,
      coalesce(ai.uuid, au.uuid) as attribution_uuid,
      
      coalesce(p.lead_criadoEm, p.lead_timestamp, p.dataConversao) as contact_date,
      coalesce(p.lead_timestamp, p.dataConversao, p.lead_criadoEm) as lead_date,  
      p.prospect_date,
      
      p.first_inside_sales_contact_date,
      
      case 
        when ia.imovelAttribution='Self-Service' -- Self service qualified date is set to null below because we cannot distinguish them from organic growth. here we correct the qualified date.
          then f.dataCriacao -- best value we can get since we miss the exact date.
        when p.qualified_date is null and p.dataConversao is not null -- correcting organic inside sales
          then p.dataConversao --  this is needed because organic inside sales have their qualified date set to null and it needs to be corrected here
        else p.qualified_date -- in all other cases we choose the qualified date
      end as qualified_date,

      case when coalesce(f.dataAgendamento, f.dataAceitoFotografo, f.dataUploadFotos)  <='1900-01-01' 
        then NULL
        ELSE coalesce(f.dataAgendamento, f.dataAceitoFotografo, f.dataUploadFotos)
      END as opportunity_date,

      ip.datePublication AS listing_publication_date,
      cast(c.dataInicio as datetime) as contract_date,
    
      p.lead_id AS lead_id,
      
      p.imovel_id AS property_id,
      c.id as contract_id,
      p.aluguel as renting_value,    
      p.status as current_property_status,
      
      f.dadosFotografo_id as dados_fotografo_id,
      coalesce(p.usuario_id, p.proprietarioLead_id) AS owner_id,
      p.usuarioQueCadastrou_id AS rep_id,
      g.id as manager_id,
      p.vendedor_id,
      u.tipoAdmin AS tipo_admin ,
  
      ia.imovelAttribution as imovel_attribution,
      p.lead_tipo as lead_tipo,
      
      CASE
        WHEN ia.imovelAttribution='Self-Service' THEN 'Self-Service'
      	WHEN p.lead_tipo='Afiliado' AND p.lead_origem='App' THEN 'Affiliate App'
      	WHEN p.lead_tipo='Afiliado' AND p.lead_origem='Form' THEN 'Affiliate Form'
      	WHEN p.lead_tipo='Afiliado' AND p.lead_origem='Planilha' THEN 'Affiliate Spreadsheet'
      	WHEN p.lead_origem='Landing' THEN 'Landing Page Leads'
      	WHEN p.conversao_tipo='Lead' AND p.lead_tipo='Marketing' AND p.lead_origem<>'Landing' THEN 'Marketing Leads'
       	WHEN p.conversao_tipo='InsideSales' THEN 'Organic/Duplicate/Referred Leads'
      	WHEN p.lead_tipo='Afiliado' AND p.lead_origem='Desconhecida' THEN 'Affiliate Unknown'
      	WHEN p.conversao_tipo='Lead' THEN 'Other Lead Source'
      	WHEN ia.imovelAttribution NOT IN ('Self-Service','Undetermined') THEN 'Organic/Duplicate/Referred Leads'
      	ELSE 'Unknown' 
      END AS attribution_type,

    	CASE 
        WHEN ia.imovelAttribution='Self-Service' THEN 'Self-Service'
      	WHEN p.lead_tipo='Afiliado' THEN 'Affiliate Lead'
      	WHEN p.lead_origem='Landing' THEN 'Landing Page Lead'
      	WHEN p.conversao_tipo='Lead' AND p.lead_tipo='Marketing' AND p.lead_origem<>'Landing' THEN 'Marketing Lead'
     	  WHEN p.conversao_tipo='InsideSales' THEN 'Organic/Duplicate/Referred Lead'
    	  WHEN p.conversao_tipo='Lead' THEN 'Other Lead Source'
    	  WHEN ia.imovelAttribution NOT IN ('Self-Service','Undetermined') THEN 'Organic/Duplicate/Referred Lead'
    	  ELSE 'Unknown' 
      END AS attribution_category,
  
      case 
        when p.lead_tipo = 'Afiliado' and ip.datePublication is not null then 25 else 0 
      end as affiliate_listing_value,
    
      case 
        when p.lead_tipo = 'Afiliado' and cast(c.dataInicio as datetime) is not null then p.aluguel*.1 else 0 
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
        o.conversao_tipo, 
        o.lead_origem, 
        min(o.prospect_date) as prospect_date,
        min(o.first_inside_sales_contact_date) as first_inside_sales_contact_date,
        min(o.qualified_date) as qualified_date,   --  sera q nao serviria f.dataCriacao ??
        max(o.created_date) as created_date,
        max(o.updated_date) as updated_date
      FROM
      (
        SELECT
          l.cap_id, -- new
          l.lead_id, -- ok
          l.proprietarioLead_id, -- not currently included in cap
          l.tipo as lead_tipo,-- ok
          l.criadoEm as lead_criadoEm, -- anunciocriadoem?
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
          cl.tipo as conversao_tipo, 
          l.origem as lead_origem, 

          CASE WHEN cl.leadConvertido_id IS NOT NULL
            THEN coalesce(cl.dataConversao, cl.criadoEm, from_unixtime(lu.timestamp/1000)) -- if there is a match with the table conversaolead, we can substitute the dataconversao by criadoEm in case dataconversao is missing
          END as qualified_date,

          coalesce(l.criadoEm, l.anuncioCriadoEm, l.captadoEm) as created_date,
          l.atualizadoEm as updated_date
        FROM
          contacts_and_prospects l
         
        LEFT JOIN lead_first_update lfu
          on lfu.id = l.id

        LEFT JOIN 
          lead_aud lre
          ON l.id = lre.id
          and lre.REV = (
            SELECT
              a.REV            
            from
              lead_aud a  
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
          usuario_revision_entity lu
          on lu.id = lre.REV    
        
        LEFT JOIN 
          conversao_lead cl
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
          l.cap_id, -- new
          l.lead_id, -- ok
          l.proprietarioLead_id, -- not in cap table for now
          l.tipo as lead_tipo,
          l.criadoEm as lead_criadoEm, -- -- anuncio_criado_em?
          from_unixtime(lu.timestamp/1000) as lead_timestamp,
          cl.dataConversao,
          cl.criadoEm as cl_criadoEm, 
          l.id as imovel_id,
          i.aluguel -- or l.valor
          i.status, -- not the status of the cap, but of the imovel
          i.recaptadoEm,
          i.usuario_id,
          i.usuarioQueCadastrou_id,
          cl.vendedor_id,
          u.tipoAdmin,
          null as first_inside_sales_contact_date,
          ie.dt_etapa_endereco as prospect_date, -- to be replaced by something simpler? then delete the join with ie
          cl.tipo as conversao_tipo, 
          l.origem as lead_origem ,
          null  as qualified_date, -- corrected above when we know the source of the lead (self service or organic inside sales)
          coalesce(l.criadoEm, l.anuncioCriadoEm, l.captadoEm, i.dataCriacao) as created_date,
          coalesce(l.atualizadoEm, i.atualizadoEm)  as updated_date
        FROM
          contacts_and_prospects l -- Imovel i
        LEFT JOIN 
        (
          select
            ie.imovel_id,
            min(ie.data) as dt_etapa_endereco -- to be replaced by ?
          from
            Imovel_Etapas ie
          where 
            ie.etapa = 'MOB_ENDERECO'            
          group BY
            ie.imovel_id
        ) ie
          on ie.imovel_id = i.id 
                   
        LEFT JOIN conversao_lead cl
          on cl.imovel_id = i.id
          -- and cl.status = 'Concluido'
        left join Lead l
          on l.id = cl.leadConvertido_id
        LEFT JOIN 
          lead_aud lre
          ON l.id = lre.id
          and lre.REV = (
            SELECT
              a.REV            
            from
              lead_aud a  
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
          usuario_revision_entity lu
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
        tipoAdmin,
        conversao_tipo,  
        lead_origem 
    ) p
  
    LEFT JOIN (
      SELECT id, min(REV) as REV, datePublication
      FROM imovel_status_history
      WHERE published = 1
      group by id
      ) ip
      on ip.id = p.imovel_id
  
    left join imovel_attribution ia -- v_imovel_attribution modified to get properties without first_publication
    on ia.id = p.imovel_id
  
    left join job_fotografo f
      on f.id = (
      select
        max(id) -- min id
      from
        job_fotografo j
      where
        j.imovel_id = p.imovel_id
        and (j.dataCriacao <= ip.datePublication or ip.datePublication is null) -- datacriacao < (if exists(datepublication) ((max(datepublication), tomorrow))
      )
  
    LEFT JOIN 
      DadosVendedor dv
      ON p.vendedor_id = dv.id
  
    LEFT JOIN 
      Usuario u
      ON dv.usuario_id = u.id
    
    left join
      Usuario g
      on dv.gerente_id = g.id
    
    left join 
      aquisicao ai
      on ai.imovel_id = p.imovel_id
      and ai.tipo = 'Imovel'
    
    left join
      aquisicao au
      on au.usuario_id = u.id
      and au.tipo = 'Usuario'
    
    left JOIN
      contrato c
      on c.id = (select c2.id from contrato c2 where c2.imovel_id = p.imovel_id and c2.dataInicio >= ip.datePublication order BY c2.id limit 1)
  
  )r

WHERE
  cast(r.ref_date as date) >= coalesce(_ref_date, '2012-12-01')
;

END