-- Monthly turnover dashboard base (former dash_turnover_v2, Daily Pipeline).
-- Turnover flags (ativos/voluntarios/involuntarios/layoffs/new_hires) use the official DW 2.0
-- fields validated for TARS (is_active, is_effective_worker, termination_type,
-- is_reorganization_termination, is_transfer_hire) instead of the legacy sandbox status/modo
-- columns; some cuts diverge from the retired notebook by design (agreed with People Insights).
-- The AI-generated exit summary (resumo_ia) is intentionally out of scope for this migration.
WITH access_list_roles_rollup AS (
    SELECT
        CONCAT('-', ARRAY_JOIN(COLLECT_LIST(email), '-'), '-') AS access_list_roles
    FROM
        datalake_gsheets_people_clean.turnover_user_roles
),
education_level_translation AS (
    -- DW 2.0's highest_education_level is sourced from foundation_lookup_value joined on
    -- language = 'US' (see dim_employee.sql), but that table already carries a canonical
    -- PT-BR translation (language = 'PTB') for every PER_HIGHEST_EDUCATION_LEVEL lookup_code,
    -- including the ones whose 'US' meaning is in English for non-Brazil-authored codes.
    -- Rebuilding that PT-BR value here lets the legacy formacao_escolaridade dictionary below
    -- apply uniformly, instead of best-effort guessing a bucket from the English text.
    SELECT
        us_flv.meaning AS highest_education_level_en,
        ptb_flv.meaning AS highest_education_level_pt
    FROM
        datalake_pin_core_clean.foundation_lookup_value AS us_flv
    JOIN
        datalake_pin_core_clean.foundation_lookup_value AS ptb_flv
            ON ptb_flv.lookup_code = us_flv.lookup_code
            AND ptb_flv.lookup_type = 'PER_HIGHEST_EDUCATION_LEVEL'
            AND ptb_flv.language = 'PTB'
    WHERE
        us_flv.lookup_type = 'PER_HIGHEST_EDUCATION_LEVEL'
        AND us_flv.language = 'US'
),
terminated_employees AS (
    -- Restricts exit-survey and exit-interview answers to employees who are confirmed
    -- terminated as of today, matching the legacy notebook's post-hoc validity filter.
    SELECT DISTINCT
        LOWER(assignment_number) AS assignment_number
    FROM
        metric_people.employee_snapshots
    WHERE
        is_current_for_employee = TRUE
        AND status = 'Terminated'
        AND dt_terminated <= DATE('{load_start_date}')
),
survey_question_answers AS (
    SELECT
        q_response.id_question_response,
        q_response.id_questionnaire_response,
        question.question_text,
        question_b.question_type,
        q_response.free_text_answer,
        q_response.multiple_choice_answer_list,
        atl.long_text AS single_choice_answer,
        q_response.created_by
    FROM
        datalake_pin_questionnaires_clean.question_response AS q_response
    LEFT JOIN
        datalake_pin_questionnaires_clean.questionnaire_question AS qr_question
            ON qr_question.id_questionnaire_question = q_response.id_questionnaire_question
    LEFT JOIN
        datalake_pin_questionnaires_clean.question_base AS question_b
            ON question_b.id_question = qr_question.id_question
    LEFT JOIN
        datalake_pin_questionnaires_clean.question_translation AS question
            ON question.id_question = qr_question.id_question
            AND question.question_version_number = question_b.question_version_number
            AND question.id_business_group = question_b.id_business_group
    LEFT JOIN
        datalake_pin_questionnaires_clean.question_answer_translation AS atl
            ON atl.id_question_answer = q_response.id_question_answer
            AND atl.language = 'PTB'
    WHERE
        question.language = 'PTB'
        AND question_b.is_latest_version
),
survey_exploded_multichoice AS (
    SELECT
        r.id_question_response,
        ua.col AS id_question_answer
    FROM
        datalake_pin_questionnaires_clean.question_response AS r
    LATERAL VIEW EXPLODE(SPLIT(r.multiple_choice_answer_list, ',')) ua
    WHERE
        ua.col <> ''
),
survey_multichoice_answers AS (
    SELECT
        e.id_question_response,
        CONCAT_WS(' | ', COLLECT_LIST(atl.long_text)) AS answer
    FROM
        survey_exploded_multichoice AS e
    LEFT JOIN
        datalake_pin_questionnaires_clean.question_answer_translation AS atl
            ON atl.id_question_answer = e.id_question_answer
    WHERE
        atl.language = 'PTB'
    GROUP BY
        e.id_question_response
),
offboarding_survey_responses AS (
    SELECT
        LOWER(es.assignment_number) AS assignment_number,
        qstnrrsp.ts_created,
        sqa.question_text,
        sqa.question_type,
        CASE sqa.question_type
            WHEN '1CHOICE' THEN sqa.single_choice_answer
            WHEN 'MULTCHOICE' THEN sma.answer
            WHEN 'TEXT' THEN sqa.free_text_answer
            ELSE NULL
        END AS unified_answer
    FROM
        datalake_pin_core_clean.allocated_task_translation AS ttl
    LEFT JOIN
        datalake_pin_questionnaires_clean.questionnaire_participant AS participant
            ON participant.id_participant = ttl.id_allocated_task
            AND participant.id_questionnaire = ttl.id_questionnaire
    LEFT JOIN
        datalake_pin_questionnaires_clean.questionnaire_base AS qstb
            ON qstb.id_questionnaire = ttl.id_questionnaire
    LEFT JOIN
        datalake_pin_questionnaires_clean.questionnaire_translation AS qstl
            ON qstl.id_questionnaire = ttl.id_questionnaire
            AND qstl.questionnaire_version_number = qstb.questionnaire_version_number
    LEFT JOIN
        datalake_pin_questionnaires_clean.questionnaire_response AS qstnrrsp
            ON qstnrrsp.id_questionnaire_participant = participant.id_questionnaire_participant
    LEFT JOIN
        survey_question_answers AS sqa
            ON sqa.id_questionnaire_response = qstnrrsp.id_questionnaire_response
    LEFT JOIN
        survey_multichoice_answers AS sma
            ON sma.id_question_response = sqa.id_question_response
    LEFT JOIN
        metric_people.employee_snapshots AS es
            ON es.sk_employee = ttl.id_performer_orig_sys
            AND es.is_current_for_employee = TRUE
    WHERE
        ttl.language = 'PTB'
        AND qstl.language = 'PTB'
        AND qstb.is_latest_version
        AND qstnrrsp.is_latest_attempt
        AND participant.id_participant IS NOT NULL
        AND ttl.description = 'Pesquisa de Saída'
),
offboarding_survey_latest AS (
    SELECT
        assignment_number,
        MAX(ts_created) AS ts_latest
    FROM
        offboarding_survey_responses
    GROUP BY
        assignment_number
),
offboarding_survey_pivot AS (
    SELECT
        t1.assignment_number,
        MAX(CASE WHEN t1.question_text = 'Você está saindo para uma posição em outra empresa?' THEN t1.unified_answer END) AS saindo_para_outra_empresa,
        MAX(CASE WHEN t1.question_text = 'Se quiser, pode compartilhar com a gente mais detalhes sobre sua decisão de saída?' THEN t1.unified_answer END) AS detalhes_saida,
        MAX(CASE WHEN t1.question_text = 'Você consideraria voltar a trabalhar no Grupo QuintoAndar no futuro?' THEN t1.unified_answer END) AS considera_voltar,
        MAX(CASE WHEN t1.question_text = 'Classifique de acordo com seu nível de concordância:Estou satisfeito(a) com a minha experiência de trabalho com minha liderança direta.' THEN t1.unified_answer END) AS satisfacao_lideranca,
        MAX(CASE WHEN t1.question_text = 'Se estiver confortável em compartilhar, para qual empresa você está indo?' THEN t1.unified_answer END) AS empresa_destino,
        MAX(CASE WHEN t1.question_text = 'Dentre as alternativas abaixo, quais você acredita terem te levado a tomar a decisão de sair? (Até 3 opções)' THEN t1.unified_answer END) AS motivos_saida_alternativas,
        MAX(CASE WHEN t1.question_text = 'O que você acredita que poderia ser feito hoje para melhorar a experiência das pessoas no Grupo QuintoAndar?' THEN t1.unified_answer END) AS melhorias_experiencia_qa,
        MAX(CASE WHEN t1.question_text = 'Em uma escala de 1 a 5, sendo 1 "Muito Insatisfeito(a)" e 5 "Muito Satisfeito(a)", como você avaliaria sua experiência geral trabalhando no Grupo QuintoAndar?' THEN t1.unified_answer END) AS avaliacao_experiencia_geral,
        MAX(CASE WHEN t1.question_text = 'Na sua nova oportunidade, como o salário + PLR (bônus) vai mudar em relação ao que você ganha hoje?' THEN t1.unified_answer END) AS beneficios_destino,
        MAX(CASE WHEN t1.question_text = 'Engajamento e Cultura' THEN t1.unified_answer END) AS engajamento_e_cultura,
        MAX(CASE WHEN t1.question_text = 'Aprendizado e Legado' THEN t1.unified_answer END) AS aprendizado_e_legado,
        MAX(CASE WHEN t1.question_text = 'Encerramento' THEN t1.unified_answer END) AS encerramento,
        MAX(CASE WHEN t1.question_text = 'Experiência com a Liderança' THEN t1.unified_answer END) AS experiencia_com_a_lideranca,
        MAX(CASE WHEN t1.question_text = 'BP, você recontrataria essa pessoa no futuro?' THEN t1.unified_answer END) AS bp_recontrataria
    FROM
        offboarding_survey_responses AS t1
    INNER JOIN
        offboarding_survey_latest AS t2
            ON t1.assignment_number = t2.assignment_number
            AND t1.ts_created = t2.ts_latest
    INNER JOIN
        terminated_employees AS te
            ON te.assignment_number = t1.assignment_number
    GROUP BY
        t1.assignment_number
),
offboarding_surveys AS (
    SELECT
        assignment_number,
        CASE saindo_para_outra_empresa
            WHEN 'Sim' THEN 'Yes'
            WHEN 'Não' THEN 'No'
            WHEN 'Prefiro não responder' THEN 'Rather not answer'
            ELSE saindo_para_outra_empresa
        END AS saindo_para_outra_empresa,
        detalhes_saida,
        CASE considera_voltar
            WHEN 'Sim' THEN 'Yes'
            WHEN 'Não' THEN 'No'
            WHEN 'Não sei' THEN "Doesn't know"
            ELSE considera_voltar
        END AS considera_voltar,
        CASE satisfacao_lideranca
            WHEN 'Concordo Completamente' THEN 'Completely agree'
            WHEN 'Concordo' THEN 'Agree'
            WHEN 'Não Concordo Nem Discordo' THEN 'Neither agree nor disagree'
            WHEN 'Discordo' THEN 'Disagree'
            WHEN 'Discordo Completamente' THEN 'Completely disagree'
            ELSE satisfacao_lideranca
        END AS satisfacao_lideranca,
        CASE beneficios_destino
            WHEN 'Aumento acima de 40%' THEN 'Raise above 40%'
            WHEN 'Aumento acima de 20%' THEN 'Raise above 20%'
            WHEN 'Aumento de até 20%' THEN 'Raise up to 20%'
            WHEN 'Prefiro não responder' THEN 'Rather not answer'
            WHEN 'Tive uma redução de valor' THEN 'Reduction'
            WHEN 'Não tive mudanças' THEN 'No changes'
            ELSE beneficios_destino
        END AS beneficios_destino,
        empresa_destino,
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    REGEXP_REPLACE(
                                        REGEXP_REPLACE(
                                            REGEXP_REPLACE(
                                                REGEXP_REPLACE(
                                                    motivos_saida_alternativas,
                                                    'Motivos Pessoais \\(inclui saúde, bem-estar, aposentadoria\\)', 'Personal Reasons (includes health, well-being, retirement)'
                                                ),
                                                'Escopo do Trabalho \\(produto, projetos, atividades\\)', 'Scope of Work (product, projects, activities)'
                                            ),
                                            'Crescimento Profissional', 'Professional Growth'
                                        ),
                                        'Estratégia e direcionamento do negócio', 'Business Strategy and Direction'
                                    ),
                                    'Carga de Trabalho', 'Workload'
                                ),
                                'Remuneração', 'Compensation'
                            ),
                            'Benefícios', 'Benefits'
                        ),
                        'Liderança', 'Leadership'
                    ),
                    'Cultura', 'Culture'
                ),
                'Empreender', 'Entrepreneurship'
            ),
            'Outro', 'Other'
        ) AS motivos_saida_alternativas,
        melhorias_experiencia_qa,
        avaliacao_experiencia_geral,
        engajamento_e_cultura,
        aprendizado_e_legado,
        encerramento,
        experiencia_com_a_lideranca,
        bp_recontrataria
    FROM
        offboarding_survey_pivot
),
interview_question_answers AS (
    SELECT
        q_response.id_question_response,
        q_response.id_questionnaire_response,
        question.question_text,
        question_b.question_type,
        q_response.free_text_answer,
        q_response.multiple_choice_answer_list,
        atl.long_text AS single_choice_answer
    FROM
        datalake_pin_questionnaires_clean.question_response AS q_response
    LEFT JOIN
        datalake_pin_questionnaires_clean.questionnaire_question AS qr_question
            ON qr_question.id_questionnaire_question = q_response.id_questionnaire_question
    LEFT JOIN
        datalake_pin_questionnaires_clean.question_base AS question_b
            ON question_b.id_question = qr_question.id_question
    LEFT JOIN
        datalake_pin_questionnaires_clean.question_translation AS question
            ON question.id_question = qr_question.id_question
            AND question.question_version_number = question_b.question_version_number
            AND question.id_business_group = question_b.id_business_group
    LEFT JOIN
        datalake_pin_questionnaires_clean.question_answer_translation AS atl
            ON atl.id_question_answer = q_response.id_question_answer
            AND atl.language = 'PTB'
    WHERE
        question.language = 'PTB'
        AND question_b.is_latest_version
),
interview_exploded_multichoice AS (
    SELECT
        r.id_question_response,
        ua.col AS id_question_answer
    FROM
        datalake_pin_questionnaires_clean.question_response AS r
    LATERAL VIEW EXPLODE(SPLIT(r.multiple_choice_answer_list, ',')) ua
    WHERE
        ua.col <> ''
),
interview_multichoice_answers AS (
    SELECT
        e.id_question_response,
        CONCAT_WS(' | ', COLLECT_LIST(atl.long_text)) AS answer
    FROM
        interview_exploded_multichoice AS e
    LEFT JOIN
        datalake_pin_questionnaires_clean.question_answer_translation AS atl
            ON atl.id_question_answer = e.id_question_answer
    WHERE
        atl.language = 'PTB'
    GROUP BY
        e.id_question_response
),
offboarding_interview_responses AS (
    SELECT
        LOWER(es.assignment_number) AS assignment_number,
        qstnrrsp.ts_created,
        iqa.question_text,
        iqa.question_type,
        CASE iqa.question_type
            WHEN '1CHOICE' THEN iqa.single_choice_answer
            WHEN 'MULTCHOICE' THEN ima.answer
            WHEN 'TEXT' THEN iqa.free_text_answer
            ELSE NULL
        END AS unified_answer
    FROM
        datalake_pin_core_clean.allocated_task_translation AS ttl
    LEFT JOIN
        datalake_pin_questionnaires_clean.questionnaire_participant AS participant
            ON participant.id_participant = ttl.id_allocated_task
            AND participant.id_questionnaire = ttl.id_questionnaire
    LEFT JOIN
        datalake_pin_questionnaires_clean.questionnaire_base AS qstb
            ON qstb.id_questionnaire = ttl.id_questionnaire
    LEFT JOIN
        datalake_pin_questionnaires_clean.questionnaire_translation AS qstl
            ON qstl.id_questionnaire = ttl.id_questionnaire
            AND qstl.questionnaire_version_number = qstb.questionnaire_version_number
    LEFT JOIN
        datalake_pin_questionnaires_clean.questionnaire_response AS qstnrrsp
            ON qstnrrsp.id_questionnaire_participant = participant.id_questionnaire_participant
    LEFT JOIN
        interview_question_answers AS iqa
            ON iqa.id_questionnaire_response = qstnrrsp.id_questionnaire_response
    LEFT JOIN
        interview_multichoice_answers AS ima
            ON ima.id_question_response = iqa.id_question_response
    LEFT JOIN
        metric_people.employee_snapshots AS es
            ON es.sk_employee = participant.id_subject
            AND es.is_current_for_employee = TRUE
    WHERE
        ttl.language = 'PTB'
        AND qstl.language = 'PTB'
        AND qstb.is_latest_version
        AND qstnrrsp.is_latest_attempt
        AND participant.id_participant IS NOT NULL
        AND qstl.name = 'Pesquisa BPs'
),
offboarding_interview_latest AS (
    SELECT
        assignment_number,
        MAX(ts_created) AS ts_latest
    FROM
        offboarding_interview_responses
    GROUP BY
        assignment_number
),
offboarding_interviews AS (
    SELECT
        t1.assignment_number,
        MAX(CASE WHEN t1.question_text = 'Engajamento e Cultura' THEN t1.unified_answer END) AS engajamento_e_cultura,
        MAX(CASE WHEN t1.question_text = 'Aprendizado e Legado' THEN t1.unified_answer END) AS aprendizado_e_legado,
        MAX(CASE WHEN t1.question_text = 'Motivos da Saída' THEN t1.unified_answer END) AS motivos_de_saida,
        MAX(CASE WHEN t1.question_text = 'Encerramento' THEN t1.unified_answer END) AS encerramento,
        MAX(CASE WHEN t1.question_text = 'Experiência com a Liderança' THEN t1.unified_answer END) AS experiencia_com_a_lideranca,
        CASE MAX(CASE WHEN t1.question_text = 'BP, você recontrataria essa pessoa no futuro?' THEN t1.unified_answer END)
            WHEN 'Sim' THEN 'Yes'
            WHEN 'Não' THEN 'No'
            WHEN 'Prefiro não responder' THEN 'Rather not answer'
            ELSE MAX(CASE WHEN t1.question_text = 'BP, você recontrataria essa pessoa no futuro?' THEN t1.unified_answer END)
        END AS bp_recontrataria
    FROM
        offboarding_interview_responses AS t1
    INNER JOIN
        offboarding_interview_latest AS t2
            ON t1.assignment_number = t2.assignment_number
            AND t1.ts_created = t2.ts_latest
    INNER JOIN
        terminated_employees AS te
            ON te.assignment_number = t1.assignment_number
    GROUP BY
        t1.assignment_number
),
monthly_base AS (
    SELECT
        es.assignment_number,
        es.dt_month_reference,
        LOWER(es.business_unit_name) AS empresa,
        -- Legacy notebook translated job_family (dw_employee, PT-BR) to English; DW 2.0's
        -- job_family is native PT-BR, so the same PT->EN dictionary is reapplied here.
        -- Job families with no legacy equivalent (Auxiliares, Estagiario, Jovem Aprendiz)
        -- fall into the legacy "other" bucket.
        CASE
            WHEN es.job_family IS NULL THEN NULL
            WHEN es.job_family = 'Analistas' THEN 'analysts'
            WHEN es.job_family IN ('Assistentes', 'Auxiliares') THEN 'assistants'
            WHEN es.job_family = 'C-Level' THEN 'c-level'
            WHEN es.job_family = 'Coordenadores' THEN 'coordinators'
            WHEN es.job_family = 'Diretores' THEN 'directors'
            WHEN es.job_family = 'Especialistas' THEN 'specialists'
            WHEN es.job_family = 'Gerentes' THEN 'managers'
            WHEN es.job_family = 'Supervisores' THEN 'supervisors'
            WHEN es.job_family = 'Vice Presidentes' THEN 'vice presidents'
            ELSE 'other'
        END AS classe_cargo,
        LOWER(es.job_name) AS cargo,
        CASE WHEN es.is_manager THEN 'leader' ELSE 'ic' END AS lideranca,
        NULLIF(LOWER(es.vertical), '-1') AS vertical,
        NULLIF(LOWER(es.structure), '-1') AS structure,
        NULLIF(LOWER(es.team), '-1') AS team,
        -- First bucket matches TARS 3moTO / New Hire Attrition via the canonical
        -- days_employee_tenure column (< 90 days). On closed monthly snapshots this
        -- matches hire→termination (leavers) and hire→month-end (actives). The
        -- in-progress month can drift at the 90-day boundary until month-end close.
        -- Later buckets keep the legacy whole-month cuts; months < 3 with days >= 90
        -- fall into 'b. 3 a 5 meses' so the 90-day boundary does not leave a NULL hole.
        CASE
            WHEN es.days_employee_tenure < 90 THEN 'a. menos de 3 meses'
            WHEN es.months_employee_tenure <= 5 THEN 'b. 3 a 5 meses'
            WHEN es.months_employee_tenure BETWEEN 6 AND 12 THEN 'c. 6 a 12 meses'
            WHEN es.months_employee_tenure BETWEEN 13 AND 18 THEN 'd. 13 a 18 meses'
            WHEN es.months_employee_tenure BETWEEN 19 AND 24 THEN 'e. 19 a 24 meses'
            WHEN es.months_employee_tenure BETWEEN 25 AND 36 THEN 'f. 25 a 36 meses'
            WHEN es.months_employee_tenure > 36 THEN 'g. mais de 36 meses'
            ELSE NULL
        END AS tenure,
        -- Legacy notebook bucketed age in years with letter-prefixed English labels; DW 2.0's own
        -- age_range uses coarser, differently-worded buckets, so the legacy boundaries are
        -- rebuilt here from the numeric age_in_years field.
        CASE
            WHEN es.age_in_years IS NULL THEN NULL
            WHEN es.age_in_years < 21 THEN 'a. Under 21 years'
            WHEN es.age_in_years BETWEEN 21 AND 25 THEN 'b. 21 to 25 years'
            WHEN es.age_in_years BETWEEN 26 AND 30 THEN 'c. 26 to 30 years'
            WHEN es.age_in_years BETWEEN 31 AND 35 THEN 'd. 31 to 35 years'
            WHEN es.age_in_years BETWEEN 36 AND 40 THEN 'e. 36 to 40 years'
            WHEN es.age_in_years BETWEEN 41 AND 45 THEN 'f. 41 to 45 years'
            WHEN es.age_in_years BETWEEN 46 AND 50 THEN 'g. 46 to 50 years'
            WHEN es.age_in_years BETWEEN 51 AND 55 THEN 'h. 51 to 55 years'
            WHEN es.age_in_years > 55 THEN 'i. Over 55 years'
            ELSE NULL
        END AS faixa_etaria,
        -- Legacy notebook prefixed potencial/criticidade for sheet sort order and displayed the
        -- capitalized English label rather than the raw DW 2.0 value.
        CASE
            WHEN es.talent_potential = 'High' THEN 'a. High'
            WHEN es.talent_potential = 'Medium' THEN 'b. Medium'
            WHEN es.talent_potential = 'Low' THEN 'c. Low'
            ELSE NULL
        END AS potencial,
        CASE
            WHEN es.talent_criticality = 'No' THEN 'a. No'
            WHEN es.talent_criticality = 'Yes' THEN 'b. Yes'
            ELSE NULL
        END AS criticidade,
        -- Legacy notebook derived perf_final from the raw perf_nota score with these exact
        -- boundaries (<70/70-90/90-110/110-120/>=121); DW 2.0's perf_final_range already applies
        -- the identical boundaries upstream and exposes the same five labels, so this only
        -- restores the legacy letter prefix for sheet sort order.
        CASE
            WHEN es.perf_final_range = 'Insufficient' THEN 'a. Insufficient'
            WHEN es.perf_final_range = 'Partially misses expectations' THEN 'b. Partially misses expectations'
            WHEN es.perf_final_range = 'Meets expectations' THEN 'c. Meets expectations'
            WHEN es.perf_final_range = 'Above expectations' THEN 'd. Above expectations'
            WHEN es.perf_final_range = 'Outstanding' THEN 'e. Outstanding'
            ELSE NULL
        END AS perf_final,
        -- Legacy notebook translated formacao_escolaridade (PT-BR, Brazil-only taxonomy) into 7
        -- letter-prefixed English buckets. DW 2.0's highest_education_level is canonicalized to
        -- PT-BR via education_level_translation first (see its comment), so this dictionary is a
        -- verified 1:1 remap rather than a best-effort guess from raw English text. Confirmed
        -- against the retired notebook's exported source (dash_turnover_v2), including the
        -- sub-fundamental "Do 6º ao 9º ano" bucket, which maps to "a. Middle school" exactly as
        -- in the notebook. One deliberate deviation: the notebook's own dictionary mapped
        -- "Universitário superior" to "b. High school", which Leonardo Oliveira (People Insights)
        -- confirmed was a bug in the legacy notebook — fixed here to "d. Graduate degree" to
        -- match "Educação Superior completa" instead of replicating the known error.
        -- "Tecnólogo completo/incompleto", "Especialização de pós-graduação", and "Pós Doutorado"
        -- have no notebook precedent (DW 2.0-only values); mapped by analogy to their closest
        -- notebook-equivalent tier (Técnico, Pós-graduação completa, and the ceiling Doctorate
        -- tier, respectively).
        CASE
            WHEN elt_edu.highest_education_level_pt IS NULL THEN NULL
            WHEN elt_edu.highest_education_level_pt = 'Não Informado' THEN NULL
            WHEN elt_edu.highest_education_level_pt = 'Do 6º ao 9º ano do Ensino Fundamental incompleto' THEN 'a. Middle school'
            WHEN elt_edu.highest_education_level_pt = 'Ensino Fundamental completo' THEN 'a. Middle school'
            WHEN elt_edu.highest_education_level_pt = 'Ensino Médio incompleto' THEN 'a. Middle school'
            WHEN elt_edu.highest_education_level_pt = 'Ensino Médio completo' THEN 'b. High school'
            WHEN elt_edu.highest_education_level_pt = 'Técnico incompleto' THEN 'b. High school'
            WHEN elt_edu.highest_education_level_pt = 'Tecnólogo incompleto' THEN 'b. High school'
            WHEN elt_edu.highest_education_level_pt = 'Educação Superior incompleta' THEN 'b. High school'
            WHEN elt_edu.highest_education_level_pt = 'Técnico completo' THEN 'c. Technical degree'
            WHEN elt_edu.highest_education_level_pt = 'Tecnólogo completo' THEN 'c. Technical degree'
            WHEN elt_edu.highest_education_level_pt = 'Educação Superior completa' THEN 'd. Graduate degree'
            WHEN elt_edu.highest_education_level_pt = 'Universitário superior' THEN 'd. Graduate degree'
            WHEN elt_edu.highest_education_level_pt = 'Pós-graduação incompleta' THEN 'd. Graduate degree'
            WHEN elt_edu.highest_education_level_pt = 'Mestrado incompleto' THEN 'd. Graduate degree'
            WHEN elt_edu.highest_education_level_pt = 'Pós-graduação completa' THEN 'e. Postgraduate degree'
            WHEN elt_edu.highest_education_level_pt = 'Especialização de pós-graduação' THEN 'e. Postgraduate degree'
            WHEN elt_edu.highest_education_level_pt = 'Mestrado completo' THEN 'f. Master''s degree'
            WHEN elt_edu.highest_education_level_pt = 'Doutorado incompleto' THEN 'f. Master''s degree'
            WHEN elt_edu.highest_education_level_pt = 'Doutorado completo' THEN 'g. Doctorate degree'
            WHEN elt_edu.highest_education_level_pt = 'Pós Doutorado' THEN 'g. Doctorate degree'
            ELSE NULL
        END AS escolaridade,
        -- Legacy notebook prefixed these buckets ("a."/"b.") for sheet sort order, and kept
        -- unknown self-declaration as its own "N/A" bucket rather than folding it into "non-*".
        CASE
            WHEN es.is_underrepresented_race IS NULL THEN 'N/A'
            WHEN es.is_underrepresented_race THEN 'b. bim'
            ELSE 'a. non-bim'
        END AS bim,
        CASE
            WHEN es.is_woman IS NULL THEN 'N/A'
            WHEN es.is_woman THEN 'b. women'
            ELSE 'a. non-women'
        END AS women,
        CASE
            WHEN es.is_lgbtqia IS NULL THEN 'N/A'
            WHEN es.is_lgbtqia THEN 'b. lgbt+'
            ELSE 'a. non-lgbt+'
        END AS lgbt,
        CASE
            WHEN es.has_self_declared_pwd OR es.has_medical_disability_record THEN 'b. pwd'
            ELSE 'a. non-pwd'
        END AS pcd,
        -- Legacy notebook only computed faixa_salarial for the three Brazil legal entities, with
        -- fixed BRL thresholds over the raw salary amount; DW 2.0's salary_range is a differently
        -- bucketed, all-country field, so the legacy boundaries are rebuilt from amount_salary.
        CASE
            WHEN LOWER(es.business_unit_name) NOT IN ('quintoandar sp', 'quintoandar sc', 'quintoandar mg') THEN NULL
            WHEN es.amount_salary < 2001 THEN '1. Less than 2001 BRL'
            WHEN es.amount_salary < 4001 THEN '2. From 2001 to 4000 BRL'
            WHEN es.amount_salary < 6001 THEN '3. From 4001 to 6000 BRL'
            WHEN es.amount_salary < 10001 THEN '4. From 6001 to 10000 BRL'
            WHEN es.amount_salary < 15001 THEN '5. From 10001 to 15000 BRL'
            WHEN es.amount_salary < 20001 THEN '6. From 15001 to 20000 BRL'
            WHEN es.amount_salary < 30001 THEN '7. From 20001 to 30000 BRL'
            ELSE '8. Over 30000 BRL'
        END AS faixa_salarial,
        es.band AS banda,
        -- Legacy notebook prefixed these buckets ("a."/"b."/...) for sheet sort order.
        CASE
            WHEN TRY_CAST(es.band AS INT) BETWEEN 1 AND 3 THEN 'a. Bands 1-3'
            WHEN TRY_CAST(es.band AS INT) BETWEEN 4 AND 6 THEN 'b. Bands 4-6'
            WHEN TRY_CAST(es.band AS INT) BETWEEN 7 AND 8 THEN 'c. Bands 7-8'
            WHEN TRY_CAST(es.band AS INT) BETWEEN 9 AND 11 THEN 'd. Bands 9-11'
            WHEN TRY_CAST(es.band AS INT) >= 12 THEN 'e. Bands 12+'
            ELSE NULL
        END AS grupo_banda,
        LOWER(es.country) AS pais,
        LOWER(es.manager_name) AS gestor,
        LOWER(es.hrbp_work_email) AS hrbp,
        CASE
            WHEN l1i.employees_in_area <= 30 THEN NULL
            ELSE LOWER(es.email_l1)
        END AS l1_e,
        LOWER(es.email_l2) AS l2_e,
        LOWER(es.email_l3) AS l3_e,
        LOWER(es.email_l4) AS l4_e,
        LOWER(es.email_l5) AS l5_e,
        LOWER(es.email_l6) AS l6_e,
        LOWER(es.email_l7) AS l7_e,
        LOWER(es.owner_l1_name) AS l1_cc,
        LOWER(es.owner_l2_name) AS l2_cc,
        LOWER(es.owner_l3_name) AS l3_cc,
        LOWER(es.cost_center_code) AS cc,
        LOWER(es.headcount_type) AS hc_type,
        CASE
            WHEN es.talent_criticality = 'Yes' AND es.talent_potential = 'High' THEN 'both'
            WHEN COALESCE(es.talent_criticality, '') != 'Yes' AND es.talent_potential = 'High' THEN 'high potential'
            WHEN es.talent_criticality = 'Yes' AND COALESCE(es.talent_potential, '') != 'High' THEN 'critical person'
            ELSE 'not rt'
        END AS rt_modo,
        CASE WHEN es.status = 'Active' THEN NULL ELSE LOWER(es.name) END AS name,
        CASE WHEN es.status = 'Active' THEN NULL ELSE LOWER(es.work_email) END AS email,
        CASE WHEN es.status = 'Active' THEN NULL ELSE es.assignment_number END AS terminated_assignment_number,
        LOWER(es.status) AS status,
        LOWER(es.termination_type) AS modo,
        CASE WHEN es.is_layoff THEN 'yes' ELSE 'no' END AS saida_reorg,
        es.dt_employee_hired AS data_entrada,
        CASE WHEN es.is_active THEN 1 ELSE 0 END AS ativos,
        CASE WHEN es.termination_type = 'voluntary' AND NOT es.is_layoff THEN 1 ELSE 0 END AS voluntarios,
        CASE WHEN es.termination_type = 'involuntary' AND NOT es.is_layoff THEN 1 ELSE 0 END AS involuntarios,
        CASE WHEN es.is_layoff THEN 1 ELSE 0 END AS layoffs,
        CASE
            WHEN NOT es.is_transfer_hire
                AND DATE_TRUNC('MONTH', es.dt_employee_hired) = DATE_TRUNC('MONTH', es.dt_month_reference)
            THEN 1
            ELSE 0
        END AS new_hires,
        -- Preserves the legacy notebook's unpartitioned window: a single company-wide count of
        -- qualifying monthly snapshot rows in the trailing 12 months, broadcast to every row.
        SUM(CASE WHEN es.dt_month_reference >= ADD_MONTHS(DATE('{load_start_date}'), -12) THEN 1 ELSE 0 END) OVER () AS ativos_ult_12_meses,
        es.ts_load
    FROM
        metric_people.employee_snapshots AS es
    LEFT JOIN (
        SELECT
            dt_month_reference,
            email_l1,
            COUNT(*) AS employees_in_area
        FROM
            metric_people.employee_snapshots
        WHERE
            is_primary_assignment_for_snapshot = TRUE
            AND is_effective_worker = TRUE
            AND email_l1 IS NOT NULL
        GROUP BY
            dt_month_reference,
            email_l1
    ) AS l1i
        ON l1i.email_l1 = es.email_l1
        AND l1i.dt_month_reference = es.dt_month_reference
    LEFT JOIN
        education_level_translation AS elt_edu
            ON elt_edu.highest_education_level_en = es.highest_education_level
    WHERE
        es.is_primary_assignment_for_snapshot = TRUE
        AND es.is_effective_worker = TRUE
        AND es.dt_month_reference >= DATE('2024-01-01')
)
SELECT
    mb.dt_month_reference AS fechamento,
    mb.empresa,
    mb.classe_cargo,
    mb.cargo,
    mb.lideranca,
    mb.vertical,
    mb.structure,
    mb.team,
    mb.tenure,
    mb.faixa_etaria,
    mb.potencial,
    mb.criticidade,
    mb.perf_final,
    mb.escolaridade,
    mb.bim,
    mb.women,
    mb.lgbt,
    mb.pcd,
    CASE WHEN mb.lgbt = 'b. lgbt+' OR mb.women = 'b. women' OR mb.bim = 'b. bim' THEN 'b. urg' ELSE 'a. non-urg' END AS urg,
    CASE WHEN mb.criticidade = 'b. Yes' OR mb.potencial = 'a. High' THEN 'yes' ELSE 'no' END AS rl,
    mb.faixa_salarial,
    mb.banda,
    mb.grupo_banda,
    mb.pais,
    mb.gestor,
    mb.hrbp,
    mb.l1_e,
    mb.l2_e,
    mb.l3_e,
    mb.l4_e,
    mb.l5_e,
    mb.l6_e,
    mb.l7_e,
    CONCAT_WS(',', mb.l1_e, mb.l2_e, mb.l3_e, mb.l4_e, mb.l5_e, mb.l6_e, mb.l7_e) AS access_list,
    mb.l1_cc,
    mb.l2_cc,
    mb.l3_cc,
    mb.cc,
    mb.hc_type,
    CAST(FROM_UTC_TIMESTAMP(MAX(mb.ts_load), 'America/Sao_Paulo') AS DATE) AS dt_last_update,
    mb.rt_modo,
    SUM(mb.ativos) AS ativos,
    SUM(mb.voluntarios) AS voluntarios,
    SUM(mb.involuntarios) AS involuntarios,
    SUM(mb.layoffs) AS layoffs,
    SUM(mb.new_hires) AS new_hires,
    mb.name,
    mb.email,
    mb.terminated_assignment_number AS assignment_number,
    COALESCE(s.saindo_para_outra_empresa, '') AS saindo_para_outra_empresa,
    COALESCE(s.detalhes_saida, '') AS detalhes_saida,
    COALESCE(s.considera_voltar, '') AS considera_voltar,
    COALESCE(s.satisfacao_lideranca, '') AS satisfacao_lideranca,
    COALESCE(s.empresa_destino, '') AS empresa_destino,
    COALESCE(s.motivos_saida_alternativas, '') AS motivos_saida_alternativas,
    COALESCE(s.melhorias_experiencia_qa, '') AS melhorias_experiencia_qa,
    COALESCE(s.avaliacao_experiencia_geral, '') AS avaliacao_experiencia_geral,
    COALESCE(s.beneficios_destino, '') AS beneficios_destino,
    COALESCE(i.engajamento_e_cultura, '') AS engajamento_e_cultura,
    COALESCE(i.aprendizado_e_legado, '') AS aprendizado_e_legado,
    COALESCE(i.motivos_de_saida, '') AS motivos_de_saida,
    COALESCE(i.encerramento, '') AS encerramento,
    COALESCE(i.experiencia_com_a_lideranca, '') AS experiencia_com_a_lideranca,
    COALESCE(i.bp_recontrataria, '') AS bp_recontrataria,
    arr.access_list_roles,
    CONCAT(
        '-',
        CONCAT_WS('-', mb.l1_e, mb.l2_e, mb.l3_e, mb.l4_e, mb.l5_e, mb.l6_e, mb.l7_e, mb.hrbp),
        '-',
        arr.access_list_roles
    ) AS access_list_all_leaders,
    AVG(mb.ativos_ult_12_meses) AS ativos_ult_12_meses,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    monthly_base AS mb
LEFT JOIN
    offboarding_surveys AS s
        ON s.assignment_number = LOWER(mb.terminated_assignment_number)
LEFT JOIN
    offboarding_interviews AS i
        ON i.assignment_number = LOWER(mb.terminated_assignment_number)
CROSS JOIN
    access_list_roles_rollup AS arr
WHERE
    -- Matches the legacy notebook's base_turnover_v2 (full-PII sheet): a rolling 14-month window,
    -- unlike base_turnover_v2_pa which kept full history since 2024-01.
    mb.dt_month_reference >= ADD_MONTHS(DATE('{load_start_date}'), -14)
GROUP BY
    mb.dt_month_reference,
    mb.empresa,
    mb.classe_cargo,
    mb.cargo,
    mb.lideranca,
    mb.vertical,
    mb.structure,
    mb.team,
    mb.tenure,
    mb.faixa_etaria,
    mb.potencial,
    mb.criticidade,
    mb.perf_final,
    mb.escolaridade,
    mb.bim,
    mb.women,
    mb.lgbt,
    mb.pcd,
    mb.faixa_salarial,
    mb.banda,
    mb.grupo_banda,
    mb.pais,
    mb.gestor,
    mb.hrbp,
    mb.l1_e,
    mb.l2_e,
    mb.l3_e,
    mb.l4_e,
    mb.l5_e,
    mb.l6_e,
    mb.l7_e,
    mb.l1_cc,
    mb.l2_cc,
    mb.l3_cc,
    mb.cc,
    mb.hc_type,
    mb.rt_modo,
    mb.name,
    mb.email,
    mb.terminated_assignment_number,
    s.saindo_para_outra_empresa,
    s.detalhes_saida,
    s.considera_voltar,
    s.satisfacao_lideranca,
    s.empresa_destino,
    s.motivos_saida_alternativas,
    s.melhorias_experiencia_qa,
    s.avaliacao_experiencia_geral,
    s.beneficios_destino,
    i.engajamento_e_cultura,
    i.aprendizado_e_legado,
    i.motivos_de_saida,
    i.encerramento,
    i.experiencia_com_a_lideranca,
    i.bp_recontrataria,
    arr.access_list_roles
ORDER BY
    fechamento DESC
