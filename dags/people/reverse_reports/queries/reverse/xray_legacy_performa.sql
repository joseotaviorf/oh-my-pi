-- Exception: legacy Performa cycles live only in datalake_gsheets_people_clean.legacy_performance_review (no DW path for pre-modern HOW/WHAT scores). DBP-1447.
-- Legacy Performa scores for X-Ray / Employee Data Center AppSheet.
-- Org context from reverse_reports.xray_general_info (same DAG; see inner_dependencies in declaration).
WITH employee_context AS (
    SELECT
        gi.email,
        gi.nome,
        gi.gestor,
        gi.empresa,
        gi.vertical,
        gi.structure,
        gi.business,
        gi.product,
        gi.banda,
        gi.primary_team_tech_exclusive,
        gi.L1,
        gi.L2,
        gi.L3,
        gi.L4,
        gi.L5,
        gi.L6,
        gi.access_list
    FROM
        reverse_reports.xray_general_info AS gi
    WHERE
        gi.year = YEAR(DATE('{load_start_date}'))
        AND gi.month = MONTH(DATE('{load_start_date}'))
        AND gi.day = DAY(DATE('{load_start_date}'))
)
SELECT
    LOWER(p.employee_email) AS email,
    ec.nome,
    ec.gestor,
    ec.empresa,
    ec.vertical AS vertical,
    ec.structure AS structure,
    ec.business,
    ec.product,
    ec.banda,
    ec.primary_team_tech_exclusive,
    ec.L1,
    ec.L2,
    ec.L3,
    ec.L4,
    ec.L5,
    ec.L6,
    INITCAP(p.performance_cycle) AS ciclo,
    p.evaluator_email AS email_avaliador,
    p.how_doing_the_right_thing_score AS how_faz_o_certo,
    p.how_customer_pain_resolution_score AS how_resolve_a_dor_do_cliente,
    p.how_embracing_change_score AS how_abraca_o_novo,
    p.how_delivers_on_commitments_score AS how_entrega_o_que_promete,
    p.how_collaborates_to_go_further_score AS how_colabora_para_ir_mais_longe,
    p.how_career_ownership_score AS how_protagoniza_a_propria_carreira,
    p.committee_comments AS comentarios_do_comite,
    p.what_normalized_score AS what_calculado,
    p.how_score AS how,
    ec.access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    datalake_gsheets_people_clean.legacy_performance_review AS p
LEFT JOIN
    employee_context AS ec
        ON LOWER(p.employee_email) = ec.email
WHERE
    ec.access_list IS NOT NULL
