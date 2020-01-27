with raw as(
    select 
        id,
        ativo,
        workcontract_id,
        LAG(workcontract_id) over (partition by id order by rev asc) as previous_workcontract_id,
        LAG(ativo) OVER (PARTITION BY id ORDER BY rev ASC) as previous_ativo,
        CASE WHEN workcontract_id != LAG(workcontract_id) over (partition by id order by rev asc) THEN true END as changed_workcontract,
        CASE WHEN ativo != LAG(ativo) over (partition by id order by rev asc) THEN true END as changed_activated,
        rev
    from datalake_ebdb_raw_prod.DadosAgente_AUD
),

base as(

    select raw.*,
        cwc.contractname as workcontract_name,
        pwc.contractname as previous_workcontract_name,
        agent.nome as agent_name,
        at.tipos as agent_type,
        revision.usuario_id as user_change_id,
        user.nome as user_change_name,
        user.email as user_change_email,
        date_format(from_unixtime(revision.timestamp/1000),'%Y-%m-%dT%H:%i:%sZ') as date,
    
        CASE
            WHEN changed_workcontract = true and workcontract_id=6 THEN 'SUSPENDED'
            WHEN changed_workcontract = true and previous_workcontract_id=6 THEN 'UNSUSPENDED'
            WHEN changed_workcontract = true and workcontract_id!=6 and previous_workcontract_id!=6 THEN 'ALTERED_CONTRACT'
            WHEN changed_activated = true and previous_ativo != true and ativo = true THEN 'ACTIVATED'
            WHEN changed_activated = true and previous_ativo != false and ativo = false  THEN 'DEACTIVATED'
        END as action
    
    from raw
    inner join datalake_ebdb_raw_prod.UsuarioRevisionEntity revision on raw.rev=revision.id
    left join datalake_ebdb_raw_prod.Usuario user on revision.usuario_id=user.id
    left join datalake_ebdb_raw_prod.Usuario agent on raw.id=agent.dadosAgente_id
    left join datalake_ebdb_raw_prod.workcontract cwc on raw.workcontract_id=cwc.id
    left join datalake_ebdb_raw_prod.workcontract pwc on raw.previous_workcontract_id=pwc.id
    left join datalake_ebdb_raw_prod.dadosagente_tipos at on at.dadosagente_id = agent.dadosAgente_id

    where (changed_workcontract = true) or changed_activated=true
),

base_clean as(
    select 
        rev,
        CASE WHEN action = 'ACTIVATED' THEN
            CASE WHEN LAG(rev) over (partition by id,action order by rev asc) IS NOT NULL THEN 'REACTIVATED' ELSE 'ACTIVATED' END
        ELSE action END as action,
        id as agent_id,
        ativo as agent_active,
        agent_name,
        agent_type,
        workcontract_id,
        workcontract_name,
        changed_activated,
        changed_workcontract,
        previous_workcontract_id,
        previous_workcontract_name,
        user_change_id,
        user_change_name,
        user_change_email,
        date 
    from base
)

select * from base_clean order by rev asc
