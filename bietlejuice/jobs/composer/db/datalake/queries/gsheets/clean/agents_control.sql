SELECT
    assignee_id AS id_assignee,
    matricula AS id_registration,
    nome AS agent_name,
    centro_de_custo AS agent_company,
    departamento AS department,
    gestores AS manager,
    email,
    cpf,
    situacao AS agent_status,
    DATE(data_inicio) AS dt_start
FROM    
    datalake_gsheets_raw.agents_control