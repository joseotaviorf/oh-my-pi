DROP PROCEDURE IF EXISTS ebdb.list_potential_listings;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_potential_listings(IN _ref_date DATE)
BEGIN

 SELECT
    r.id,
    r.ref_date,
    r.created_date,
    r.updated_date,
    r.attribution_id,
    r.attribution_uuid,
    coalesce(
        r.contact_date,
        r.lead_and_prospect_date,
        r.qualified_date,
        r.opportunity_date,
        r.listing_publication_date) as contact_date,
    r.lead_date,
    r.prospect_date,
    coalesce(
        r.lead_and_prospect_date,
        r.qualified_date,
        r.opportunity_date,
        r.listing_publication_date) as lead_and_prospect_date,
    r.first_inside_sales_contact_date,
    coalesce(
        r.qualified_date,
        r.opportunity_date,
        r.listing_publication_date) as qualified_date,
    coalesce(
        r.opportunity_date,
        r.listing_publication_date) as opportunity_date,
    r.listing_publication_date,
    r.contract_date,
    r.lead_id,
    r.property_id,
    r.contract_id,
    r.renting_value,
    r.current_property_status,
    r.dados_fotografo_id,
    r.owner_id,
    r.rep_id,
    r.manager_id,
    r.vendedor_id,
    r.tipo_admin,
    r.imovel_attribution,
    r.lead_tipo,
    r.affiliate_listing_value,
    r.affiliate_renting_value,

    affiliate_listing_value + affiliate_renting_value as cac_affiliate,
    0.0000 as cac_marketing,
    0.0000 as cac_photo,
    0.0000 as cac_inside_sales,

    TIMESTAMPDIFF(MINUTE, r.contact_date, r.lead_and_prospect_date) as contact_to_lead_diff_minutes,
    TIMESTAMPDIFF(MINUTE, r.lead_and_prospect_date, r.qualified_date) as lead_and_prospect_to_qualified_diff_minutes,
    TIMESTAMPDIFF(MINUTE, r.qualified_date, r.opportunity_date) as qualified_to_opportunity_diff_minutes,
    TIMESTAMPDIFF(MINUTE, r.opportunity_date, r.listing_publication_date) as opportunity_to_listing_diff_minutes,
    TIMESTAMPDIFF(MINUTE, r.listing_publication_date, r.contract_date) as listing_to_1stcontract_diff_minutes,
    TIMESTAMPDIFF(MINUTE, r.contact_date, r.listing_publication_date) as contact_to_listing_diff_minutes,
    TIMESTAMPDIFF(MINUTE, r.contact_date, r.contract_date) as contact_to_1stcontract_diff_minutes

  FROM
  (
    SELECT
      CAST((@cnt := @cnt + 1) AS UNSIGNED) AS id, -- creates the fact ID (key)
      coalesce(o.updated_date, o.created_date) as ref_date,
      o.created_date,
      o.updated_date,
      coalesce(ai.id, au.id) as attribution_id,
      coalesce(ai.uuid, au.uuid) as attribution_uuid,
      coalesce(o.lead_criadoEm, o.lead_timestamp, o.dataConversao, o.lead_captadoEm, o.lead_anuncioCriadoEm) as contact_date,

      coalesce(o.lead_timestamp, o.dataConversao) as lead_date,

      o.prospect_date as prospect_date,
      coalesce(o.prospect_date, o.lead_timestamp, o.dataConversao, o.lead_criadoEm) as lead_and_prospect_date,  -- coalesce prospect and lead date
      o.first_inside_sales_contact_date,

      o.qualified_date as qualified_date,

      case
        when coalesce(f.dataAgendamento, f.dataAceitoFotografo, f.dataUploadFotos)  <='1900-01-01'
          then NULL
        ELSE coalesce(f.dataAgendamento, f.dataAceitoFotografo, f.dataUploadFotos)
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
        lead_captadoEm,
        lead_anuncioCriadoEm,
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
        n.conversao_tipo,
        n.lead_origem,
        case
        	when lead_flow=0 then min(n.prospect_date)
        	else NULL
        end as prospect_date,
        case
        	when lead_flow=1 then min(n.first_inside_sales_contact_date)
        	else NULL
        end as first_inside_sales_contact_date,
        case
        	when lead_flow=1 then min(n.qualified_date)
        	else NULL
        end as qualified_date,
        max(n.created_date) as created_date,
        max(n.updated_date) as updated_date
      FROM
      (
        SELECT
          l.id as lead_id,
          l.proprietarioLead_id,
          l.tipo as lead_tipo,
          l.criadoEm as lead_criadoEm,
          l.captadoEm as lead_captadoEm,
          l.anuncioCriadoEm as lead_anuncioCriadoEm,
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
          l.atualizadoEm as updated_date,
          1 as lead_flow

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
                   (a.processado = 1 and processado_MOD = 1 and coalesce(l.automaticallyDiscarded, false) = false)
                    or (a.status_MOD = 1 and a.status != 'Descartado')
                  )
              and a.status != 'Novo'

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
          l.captadoEm as lead_captadoEm,
          l.anuncioCriadoEm as lead_anuncioCriadoEm,
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
          i.dataCriacao as prospect_date, -- previously : dt_etapa_endereco
          cl.tipo as conversao_tipo,
          l.origem as lead_origem ,
          FROM_UNIXTIME(ure.`timestamp`/1000) as qualified_date, -- corrected above when we know the source of the lead (self service or organic inside sales)
          coalesce(l.criadoEm, l.anuncioCriadoEm, l.captadoEm, i.dataCriacao) as created_date,
          coalesce(l.atualizadoEm, i.atualizadoEm)  as updated_date,
          0 as lead_flow
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
          -- and cl.status = 'Concluido'
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
                   (a.processado = 1 and processado_MOD = 1 and coalesce(l.automaticallyDiscarded, false) = false)
                    or (a.status_MOD = 1 and a.status != 'Descartado')
                  )
              and a.status != 'Novo'
            order by
              rev asc
            limit 1
        )
        LEFT JOIN
          UsuarioRevisionEntity lu
          on lu.id = lre.REV
        left join Usuario u
          on u.id = i.usuario_id
        left join
         	(select
                max(REV) as REV,
                garantias,
                Imovel_id
                from Imovel_garantias_AUD
                where garantias = 'SeguroFiancaCardiff'
                group by Imovel_id) ig
            on i.id = ig.Imovel_id
            and ig.garantias = 'SeguroFiancaCardiff'
        left join
            UsuarioRevisionEntity ure
            on ig.REV = ure.id
      ) n
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
    ) o

    LEFT JOIN (
      SELECT id, min(REV) as REV, datePublication
      FROM v_ImovelStatusHistory
      WHERE published = 1
      group by id
      ) ip
      on ip.id = o.imovel_id

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
        (CASE
          WHEN ((`ipd`.`usuario_id` = `ipd`.`usuarioQueCadastrou_id`) AND (`u2`.`tipoAdmin` = 'Normal'))
            THEN 'Self-Service'
          WHEN ((COALESCE(`dv`.`ativo`, `ipd`.`usuarioQueCadastrou_ativo`, `ipd`.`usuarioQuePublicou_ativo`) = 1) AND (`ipd`.`usuarioQueCadastrou_id` = 11))
            THEN COALESCE(`u`.`nome`, `ipd`.`nome`, `u2`.`nome`)
          WHEN ((COALESCE(`dv`.`ativo`, `ipd`.`usuarioQueCadastrou_ativo`, `ipd`.`usuarioQuePublicou_ativo`) = 1) AND (`ipd`.`usuarioQueCadastrou_id` <> 11))
            THEN COALESCE(`u`.`nome`, `u2`.`nome`, `ipd`.`nome`)
          WHEN  (COALESCE(`dv`.`ativo`, `ipd`.`usuarioQueCadastrou_ativo`, `ipd`.`usuarioQuePublicou_ativo`) = 0)
            THEN 'Inactive'
          WHEN (ISNULL(COALESCE(`u`.`nome`, `u2`.`nome`, `ipd`.`nome`)) AND (`ipd`.`dataPublicado` IS NOT NULL))
            THEN 'Undetermined'
          WHEN (COALESCE(`u`.`nome`, `u2`.`nome`, `ipd`.`nome`) IS NOT NULL)
            THEN 'Recaptured'
          ELSE NULL
        END) AS `imovelAttribution`
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
        FROM ((((((`v_FirstImovelFromAUD` `fip` -- gives for each imovel id the corresponding min(rev)
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
        max(id) -- min id
      from
        JobFotografo j
      where
        j.imovel_id = o.imovel_id
        and (j.dataCriacao <= ip.datePublication or ip.datePublication is null) -- datacriacao < (if exists(datepublication) ((max(datepublication), tomorrow))
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

      -- where o.imovel_id in (892793760)--, 892763276,892791756 )
      -- year(o.ref_date)= 2016
      -- and month(o.ref_date) >= 11
      -- and  l.id = 319376
      -- and l.id = 261579
      -- and l.id = 331494
      -- l.id = 43106

    CROSS JOIN (SELECT @cnt := 0) AS dummy
  )r


WHERE
  cast(r.ref_date as date) >= coalesce(_ref_date, '2012-12-01')

-- call list_potential_listings(null)
;

END

