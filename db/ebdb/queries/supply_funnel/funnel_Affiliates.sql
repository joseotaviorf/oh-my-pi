SELECT -- count(1)
  r.*,

  affiliate_listing_value + affiliate_renting_value as CAC_Affiliate,
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
    (CASE   
        WHEN l.tipo = 'Afiliado' THEN 'Affiliates' 
        
        WHEN l.tipo <> 'Afiliado' THEN 'Other Lead (Marketing, Crawler...)' 
        
        ELSE 'Unknown' 
    END) AS funnel_source,
    coalesce(ai.id, au.id) as attribution_id,
    coalesce(ai.uuid, au.uuid) as attribution_uuid,
    
    l.criadoEm as contact_date,
    coalesce(from_unixtime(lu.timestamp/1000), cl.dataConversao, cl.criadoEm) as lead_date,  
    coalesce(cl.dataConversao, cl.criadoEm) AS qualified_date,  
    f.dataCriacao as opportunity_date,
    ip.datePublication AS listing_publication_date,
    cast(c.dataInicio as datetime) as contract_date,
  
    l.id AS lead_id,
    
    i.id AS property_id,
    i.aluguel as renting_value,    
    i.status as current_property_status,
    
    f.dadosFotografo_id,
    coalesce(i.usuario_id, l.proprietarioLead_id) AS owner_id,
    i.usuarioQueCadastrou_id AS rep_id,
    g.id as manager_id,
    u.tipoAdmin AS tipoAdmin ,

    case 
      when l.tipo = 'Afiliado' and ip.datePublication is not null then 25 else 0 
    end as affiliate_listing_value,
  
    case 
      when l.tipo = 'Afiliado' and cast(c.dataInicio as datetime) is not null then i.aluguel*.1 else 0 
    end as affiliate_renting_value

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

  left join
    UsuarioRevisionEntity lu
    on lu.id = lre.REV    
  
  LEFT JOIN 
    ConversaoLead cl
    ON cl.leadConvertido_id = l.id
    and cl.status = 'Concluido'
    and cl.tipo = 'Lead'
  
  left join
    JobFotografo f
    on f.imovel_id = cl.imovel_id
    and f.status != 'Cancelado'

  LEFT JOIN
    Imovel i
    on i.id = cl.imovel_id

  LEFT JOIN 
    v_ImovelStatusHistory ip
    on ip.id = i.id
    and ip.published = 1
--     and ip.REV =  
--     ( -- it's trying to get the first status 'publicado' after the 'JobFotografo.revisionImovel' date.
--       SELECT
--         r.REV
--       from
--         v_ImovelStatusHistory r
--       where r.id = i.id
--       and r.published = 1
--       AND (r.REV >= f.revisionImovel or f.revisionImovel is null)
--       limit 1
--     )

  LEFT JOIN 
    DadosVendedor dv
    ON cl.vendedor_id = dv.usuario_id

  LEFT JOIN 
    Usuario u
    ON dv.usuario_id = u.id
  
  left join
    Usuario g
    on dv.gerente_id = g.id
  
  left join 
    v_Aquisicao ai
    on ai.imovel_id = i.id
    and ai.tipo = 'Imovel'
  
  left join
    v_Aquisicao au
    on au.usuario_id = u.id
    and au.tipo = 'Usuario'
  
  left JOIN
    Contrato c
    on c.id = (select 
                c2.id
              from
                Contrato c2
              where
                c2.imovel_id = f.imovel_id
                and c2.dataInicio >= coalesce(f.dataCriacao, ip.datePublication)
              order BY
                c2.id
              limit 1
            )
      -- on c.id = (SELECT min(c.id) from Contrato c WHERE c.imovel_id = f.imovel_id and c.criadoEm >= ip.datePublication) 
      

  where 
     year(l.criadoEm)= 2016
    -- and month(l.criadoEm)= 11
    -- and  l.id = 319376
    -- and l.id = 261579
    -- and l.id = 331494
    -- l.id = 43106
    -- f.imovel_id = 892769803
  order BY
    1
) r
