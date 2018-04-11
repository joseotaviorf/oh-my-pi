CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_photo_job()
BEGIN
    select
        f.id,
        f.imovel_id,
        f.status as job_status,
        case
            when jfo.name = 'Admin'
            then 'Admin'
            when jfo.name = 'Owner'
            then 'Owner App'
            when jfo.name = 'System'
            then 'System - Auto'
        end as creation_origin,
        case when hour(f.dataAgendamento) between 8 and 17 or f.dataAgendamento is null
            then 0
            else 1
        end as flexible_schedule,
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
        uc.email as user_cancel_email
    from
        JobFotografo f
    left join
        (select id, max(REV) as REV from JobFotografo_AUD group by id) max_j
        on max_j.id = f.id
        and f.status in ('Cancelado','ComProblema')
    left join
        UsuarioRevisionEntity ure
        on ure.id = max_j.REV
    left join
        Usuario uc
        on uc.id = ure.usuario_id
    left join
        Usuario af
        on af.dadosFotografo_id = f.dadosFotografo_id
    left join
        DadosFotografo df
        on df.id = f.dadosFotografo_id
    left join
        JobFotografoOrigin jfo
        on jfo.id = f.originCreation_id;
END