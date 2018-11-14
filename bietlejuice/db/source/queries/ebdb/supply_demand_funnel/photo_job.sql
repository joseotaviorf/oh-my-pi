select
      f.id,
      f.imovel_id,
      case
        when f.status = 'Cancelado' and comp.id is not null
        then 'ComProblema'
        else f.status
      end as job_status,
      case
        when creator.dadosFotografo_id is not null and creator.dadosVendedor_id is not null then 'Teste'
        when creator.dadosFotografo_id is not null then 'Fotografo'
        when creator.dadosVendedor_id is not null then 'InsideSales'
        when creator.email like ('%quintoandar%') then 'Admin'
        else 'Prop'
      end as creation_origin,
      case
        when hour(f.dataAgendamento) between 6 and 23 or f.dataAgendamento is null
        then 0
        else 1
      end as flexible_schedule,
      -- same_day_listing applies to any publishing until 10 AM (7AM - due to UTC diff) of the next day after the photo shoot
      coalesce((first_pub.nxt_pub <= date(coalesce(f.dataInicioSessao, f.dataAgendamento)) + interval '1' day + interval '10' hour), false) as same_day_listing,
      -- job_on_time applies to any publishing until 10 AM (7AM - due to UTC diff) of the next day after the photo shoot scheduled date
      -- OR jobs not published but with photos uploadeds on the same interval
      coalesce((first_pub.nxt_pub <= date(f.dataAgendamento) + interval '1' day + interval '10' hour), false)
      or
      coalesce(first_pub.nxt_pub IS NULL AND (f.dataUploadFotos <= date(f.dataAgendamento) + interval '1' day + interval '10' hour), false) as job_on_time,
      f.dataAceitoFotografo as dt_photographer_accepted,
      f.dataCriacao as dt_job_created,
      f.dataJobPedido as dt_job_issued,
      f.dataInicioSessao as dt_shoot_started,
      f.dataAgendamento as dt_job_scheduled,
      f.dataUploadFotos as dt_photos_uploaded,
      f.atualizadoEm as dt_updated,
      f.instrucoesAgendamento as scheduling_instructions,
      f.nomeContatoSessaoFotos as photo_shoot_contact_name,
      f.emailSessaoFotos as photo_shoot_email,
      f.telefoneSessaoFotos as photo_shoot_phone,
      f.telefoneSessaoFotosSecundario as photo_shoot_second_phone,
      f.aprovado+0 as approved,
      f.confirmado+0 as confirmed,
      f.lockbox+0 as lockbox,
      f.retirarChave as key_withdraw,
      f.outrosChave as key_comments,
      af.id as photographer_id,
      af.nome as photographer_name,
      af.email as photographer_email,
      df.criadoEm as dt_photographer_start,
      f.tipoContrato as photographer_contract_type,
      case
        when f.problema is not null then f.problema
        when ure.motivo like 'Cancelada pelo proprie%' then 'ProprietarioCancelou'
        when ure.motivo like 'Outro' then 'Outros'
        else f.problema
      end as job_problem_reason,
      ure.motivo as cancel_reason,
      FROM_UNIXTIME(ure.timestamp/1000) as user_cancel_dt,
      uc.id as user_cancel_id,
      uc.nome as user_cancel_name,
      uc.email as user_cancel_email,
      case
        when uc.dadosFotografo_id is not null and uc.dadosVendedor_id is not null then 'Teste'
        when uc.dadosFotografo_id is not null then 'Fotografo'
        when uc.dadosVendedor_id is not null then 'InsideSales'
        when uc.email like ('%quintoandar%') then 'Admin'
        else 'Prop'
      end as user_cancel_type,
      case
        when creator.dadosVendedor_id is not null then creator.id
        else null
      end as rep_id,
      h.photoShootSchedulingReason as job_scheduling_reason,
      TIMESTAMPDIFF(
        MINUTE,
        f.dataCriacao,
        case
          when hour(f.dataAgendamento) between 6 and 23 then f.dataAgendamento
          when date(f.dataAgendamento) + interval '12' hour < f.dataCriacao then f.dataCriacao
        else date(f.dataAgendamento) + interval '12' hour end
      ) as creation_to_scheduling_diff_minutes,
      round(TIMESTAMPDIFF(
        MINUTE,
        f.dataCriacao,
        case
          when hour(f.dataAgendamento) between 6 and 23 then f.dataAgendamento
          when date(f.dataAgendamento) + interval '12' hour < f.dataCriacao then f.dataCriacao
        else date(f.dataAgendamento) + interval '12' hour end
      )/60,1) as creation_to_scheduling_diff_hours,
      round(TIMESTAMPDIFF(
        MINUTE,
        f.dataCriacao,
        case
          when hour(f.dataAgendamento) between 6 and 23 then f.dataAgendamento
          when date(f.dataAgendamento) + interval '12' hour < f.dataCriacao then f.dataCriacao
        else date(f.dataAgendamento) + interval '12' hour end
      )/1440,1) as creation_to_scheduling_days
    from JobFotografo f
    left join
        (select id, max(REV) as REV from JobFotografo_AUD group by id) max_j
        on max_j.id = f.id
        and f.status in ('Cancelado','ComProblema')
    left join
        (select id, max(REV) as REV from JobFotografo_AUD where status = 'ComProblema' group by id) comp
        on comp.id = f.id
        and f.status = 'Cancelado'
    left join UsuarioRevisionEntity ure on ure.id = max_j.REV
    left join Usuario uc on uc.id = ure.usuario_id
    left join Usuario af on af.dadosFotografo_id = f.dadosFotografo_id
    left join DadosFotografo df on df.id = f.dadosFotografo_id
    left join
      (select id, min(REV) as REV from JobFotografo_AUD group by id) min_j
      on min_j.id = f.id
    left join UsuarioRevisionEntity ure2 on ure2.id = min_j.REV
    left join Usuario creator on creator.id = ure2.usuario_id
    left join
    (
      SELECT
        jf.id,
        min(msi.data) as nxt_pub
      from
        JobFotografo jf
      left join MudancaStatusImovel msi
        on msi.imovel_id = jf.imovel_id
        and msi.novoStatus = 'publicado'
        and date(msi.`data`) >= date(coalesce(jf.dataInicioSessao, jf.dataCriacao, jf.dataAgendamento))
      group by jf.id
    ) first_pub on first_pub.id = f.id
    left join
    (
      SELECT
        hrs_aud.photoShoot_id,
        MAX(REV) as rev
      FROM HouseRegistrationStatus_AUD hrs_aud
      GROUP BY hrs_aud.photoShoot_id
    ) rev on rev.photoShoot_id = f.id
    left join HouseRegistrationStatus_AUD h on h.REV = rev.rev
where DATE(coalesce(f.dataCriacao, '1900-01-01 00:00:00')) <= DATE('{}')
