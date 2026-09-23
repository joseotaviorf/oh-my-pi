-- X-Ray General Information roster for external recruiters: bands 9 and below, Corp or Ops.
-- Excludes structure People and anyone in Deborah Abi Saber's reporting line. DBP-2109.
-- Same columns as reverse_reports.xray_general_info; same DAG inner_dependency.
SELECT
    gi.empresa,
    gi.id_colaborador,
    gi.matricula,
    gi.nome,
    gi.email,
    gi.status,
    gi.banda,
    gi.gestor,
    gi.cargo,
    gi.classe_cargo,
    gi.centro_de_custo,
    gi.vertical,
    gi.structure,
    gi.team,
    gi.business,
    gi.product,
    gi.chapter,
    gi.primary_team_tech_exclusive,
    gi.tempo_na_banda_em_meses,
    gi.L1,
    gi.L2,
    gi.L3,
    gi.L4,
    gi.L5,
    gi.L6,
    gi.L7,
    gi.hrbp,
    gi.diretos,
    gi.diretos_e_indiretos,
    gi.is_leader,
    gi.dt_inicio,
    gi.dt_desligamento,
    gi.motivo_desligamento,
    gi.sexo,
    gi.dt_nascimento,
    gi.disability_status,
    gi.documented_subclassification,
    gi.work_restriction,
    gi.tabela_salarial,
    gi.salario,
    gi.pct_ultimo_movimento,
    gi.tipo_ultimo_movimento,
    gi.dt_ultimo_movimento,
    gi.address,
    gi.address_city_state_zip,
    gi.numero_celular,
    gi.tenure,
    gi.pos_faixa,
    gi.referencia,
    gi.potencial,
    gi.criticidade,
    gi.dt_last_update,
    gi.pais,
    gi.target_rv,
    gi.impacto,
    gi.comportamento,
    gi.lideranca_pr,
    gi.faixa_pr,
    gi.prontidao,
    gi.risco_de_perda,
    gi.access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    reverse_reports.xray_general_info AS gi
WHERE
    gi.year = YEAR(DATE('{load_start_date}'))
    AND gi.month = MONTH(DATE('{load_start_date}'))
    AND gi.day = DAY(DATE('{load_start_date}'))
    AND TRY_CAST(gi.banda AS INT) <= 9
    AND LOWER(gi.vertical) IN ('corp', 'ops')
    AND COALESCE(LOWER(gi.structure), '') <> 'people'
    AND LOWER(REPLACE(COALESCE(gi.gestor, ''), ' ', '')) NOT LIKE '%abisaber%'
    AND LOWER(REPLACE(COALESCE(gi.L1, ''), ' ', '')) NOT LIKE '%abisaber%'
    AND LOWER(REPLACE(COALESCE(gi.L2, ''), ' ', '')) NOT LIKE '%abisaber%'
    AND LOWER(REPLACE(COALESCE(gi.L3, ''), ' ', '')) NOT LIKE '%abisaber%'
    AND LOWER(REPLACE(COALESCE(gi.L4, ''), ' ', '')) NOT LIKE '%abisaber%'
    AND LOWER(REPLACE(COALESCE(gi.L5, ''), ' ', '')) NOT LIKE '%abisaber%'
    AND LOWER(REPLACE(COALESCE(gi.L6, ''), ' ', '')) NOT LIKE '%abisaber%'
    AND LOWER(REPLACE(COALESCE(gi.L7, ''), ' ', '')) NOT LIKE '%abisaber%'
    AND LOWER(REPLACE(COALESCE(gi.nome, ''), ' ', '')) NOT LIKE '%abisaber%'
    AND LOWER(COALESCE(gi.email, '')) <> 'deborah.abisaber@quintoandar.com.br'
