SELECT
    NULLIF(id, '') AS id_employee,
    NULLIF(name, '') AS employee_name,
    NULLIF(email, '') AS email,
    NULLIF(company, '') AS company,
    NULLIF(band, '') AS band,
    NULLIF(job, '') AS job,
    NULLIF(job_classification, '') AS job_classification,
    NULLIF(subdirectorate, '') AS subdirectorate,
    NULLIF(CAST(cost_center AS STRING), '') AS cost_center,
    NULLIF(CAST(vertical AS STRING), '') AS vertical,
    NULLIF(CAST(vp AS STRING), '') AS vp,
    NULLIF(CAST(directorate AS STRING), '') AS directorate,
    NULLIF(CAST(line AS STRING), '') AS line,
    NULLIF(chapter, '') AS chapter,
    NULLIF(l1, '') AS l1,
    NULLIF(l2, '') AS l2,
    NULLIF(l3, '') AS l3,
    NULLIF(manager, '') AS manager,
    NULLIF(talent_renewal, '') AS talent_renewal,
    NULLIF(CAST(category AS STRING), '') AS category,
    NULLIF(CAST(matrix_quadrant AS STRING), '') AS matrix_quadrant,
    NULLIF(CAST(quadrant_description AS STRING), '') AS quadrant_description,
    NULLIF(CAST(suggested_action_plan AS STRING), '') AS suggested_action_plan,
    NULLIF(impact, '') AS impact,
    NULLIF(behavior, '') AS behavior,
    NULLIF(leadership, '') AS leadership,
    NULLIF(potential, '') AS potential,
    NULLIF(criticality, '') AS criticality,
    NULLIF(readinesse_for_promotion, '') AS readiness_for_promotion,
    NULLIF(risk_of_loss, '') AS risk_of_loss,
    NULLIF(regrettable_loss, '') AS regrettable_loss,
    NULLIF(CAST(motivation_on_compensation AS STRING), '') AS motivation_on_compensation,
    NULLIF(CAST(motiovation_on_challenges_of_the_current_position AS STRING), '') AS motivation_on_challenges_of_current_position,
    NULLIF(CAST(motivation_on_relationship_with_direct_leadership AS STRING), '') AS motivation_on_relationship_with_leadership,
    NULLIF(CAST(type_of_plan AS STRING), '') AS type_of_plan,
    NULLIF(CAST(plan_description AS STRING), '') AS plan_description,
    NULLIF(CAST(status_of_plan AS STRING), '') AS status_of_plan,
    NULLIF(CAST(to_which_position_person AS STRING), '') AS successor_target_position,
    NULLIF(CAST(notes_of_this_person_what_action_plan_will_we_have_to_prepare_this_person AS STRING), '') AS person_action_plan_notes,
    NULLIF(CAST(who AS STRING), '') AS successor_candidate,
    NULLIF(CAST(notes_of_this_persons_successor_what_action_plan_will_prepare_this_person AS STRING), '') AS successor_action_plan_notes,
    NULLIF(CAST(bp_general_notes AS STRING), '') AS bp_general_notes,
    NULLIF(CAST(hr_bp_responsible AS STRING), '') AS hr_bp_responsible,
    NULLIF(status, '') AS status,
    NULLIF(CAST(final_evaluation AS STRING), '') AS final_evaluation,
    NULLIF(CAST(no_oficial___on_going_performa_updates_ AS STRING), '') AS informal_performance_updates,
    NULLIF(CAST(last_editor AS STRING), '') AS last_editor,
    NULLIF(type_of_last_movement_recognition, '') AS last_movement_recognition_type,
    CAST(NULLIF(salary, '') AS DECIMAL(18, 2)) AS salary,
    NULLIF(salary_range_position, '') AS salary_range_position,
    CASE
        WHEN LOWER(NULLIF(is_a_leader, '')) = 'yes'
            THEN TRUE
        WHEN LOWER(NULLIF(is_a_leader, '')) = 'no'
            THEN FALSE
        ELSE NULL
    END AS is_a_leader,
    CASE
        WHEN LOWER(NULLIF(CAST(does_this_person_need_to_be_replaced AS STRING), '')) = 'yes'
            THEN TRUE
        WHEN LOWER(NULLIF(CAST(does_this_person_need_to_be_replaced AS STRING), '')) = 'no'
            THEN FALSE
        ELSE NULL
    END AS needs_replacement,
    CASE
        WHEN LOWER(NULLIF(CAST(is_this_person_a_potential_successor AS STRING), '')) = 'yes'
            THEN TRUE
        WHEN LOWER(NULLIF(CAST(is_this_person_a_potential_successor AS STRING), '')) = 'no'
            THEN FALSE
        ELSE NULL
    END AS is_potential_successor,
    CASE
        WHEN LOWER(NULLIF(CAST(does_this_person_have_a_possible_successor AS STRING), '')) = 'yes'
            THEN TRUE
        WHEN LOWER(NULLIF(CAST(does_this_person_have_a_possible_successor AS STRING), '')) = 'no'
            THEN FALSE
        ELSE NULL
    END AS has_possible_successor,
    TO_DATE(NULLIF(CAST(deadline_mm_dd_yyyy AS STRING), ''), 'MM/dd/yyyy') AS dt_plan_deadline,
    TO_DATE(NULLIF(CAST(last_edit_date AS STRING), ''), 'dd/MM/yyyy') AS dt_last_edited,
    TO_DATE(NULLIF(admission_date, ''), 'dd/MM/yyyy') AS dt_admitted,
    TO_DATE(NULLIF(termination_date, ''), 'dd/MM/yyyy') AS dt_terminated,
    TO_DATE(NULLIF(date_of_last_movement_recognition, ''), 'dd/MM/yyyy') AS dt_last_movement_recognition,
    NOW() AS ts_load
FROM
    datalake_gsheets_people_raw.talent_mapping_base
WHERE
    id IS NOT NULL
    AND id <> ''
