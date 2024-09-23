WITH
  opportunity_info_source AS (
    SELECT
      id_candidate,
      answer
    FROM
      datalake_workable_redshift_clean.answers
    WHERE
      question LIKE '%Por onde você ficou sabendo dessa oportunidade?%'
  ),
  employee_consolidations AS (
    SELECT DISTINCT
      ei.id_person,
      ei.id_assignment,
      ei.id_period_of_service,
      hi.sk_hierarchy,
      ei.assignment_number,
      m.id AS id_member_workable,
      c.id AS id_candidate_workable,
      ei.work_email,
      ei.personal_email,
      NOW() AS ts_load
    FROM
      datalake_hr_system.employee_ids AS ei
    LEFT JOIN 
      datalake_workable_redshift_clean.members AS m 
        ON ei.work_email = m.email
    LEFT JOIN 
      datalake_workable_redshift_clean.candidates AS c 
        ON ei.personal_email = c.email
    LEFT JOIN 
      datalake_hr_system.hierarchy_ids AS hi
        ON ei.id_period_of_service = hi.sk_assignment
  ),
  requisitions_details_step1 AS (
    SELECT DISTINCT
      r.id,
      r.id_candidate,
      r.id_job,
      eec_hiring_manager.sk_hierarchy,
      eec_owner.id_person AS sk_owner,
      COALESCE(eec_hiring_manager_cf.id_person, eec_hiring_manager.id_person) AS sk_hiring_manager,
      eec_business_partner.id_person AS sk_business_partner,
      r.code,
      r.state,
      CASE
        WHEN r.state = 0 THEN 'draft'
        WHEN r.state = 1 THEN 'pending'
        WHEN r.state = 2 THEN 'approved'
        WHEN r.state = 3 THEN 'open'
        WHEN r.state = 4 THEN 'filled'
        WHEN r.state = 5 THEN 'rejected'
        WHEN r.state = 6 THEN 'cancelled'
        WHEN r.state = 7 THEN 'reserved'
        ELSE 'on hold'
      END AS status,
      j.title AS job_title,
      ecf_requisitions.position_name,
      ecf_requisitions.opening_reason,
      ecf_requisitions.salary_band,
      ecf_requisitions.capacity_overhead,
      ecf_requisitions.affirmative_position,
      ecf_requisitions.career_track,
      ecf_requisitions.how_closed,
      ecf_requisitions.cost_center,
      ecf_requisitions.is_confidential,
      rd.days_on_hold,
      rd.days_open,
      rd.days_queue,
      rd.dt_created,
      rd.dt_opened,
      rd.dt_filled,
      rd.dt_cancelled,
      rd.dt_last_on_hold,
      CASE
        WHEN ecf_requisitions.company IN ('Benvi - Portugal', 'Benvi PT') THEN 'PT'
        WHEN ecf_requisitions.company IN (
          'Benvi - México',
          'Benvi MX',
          'Classifields',
          'Corporative - Argentina',
          'Corporative - Ecuador',
          'Corporative - Mexico',
          'Inmuebles 24 Full',
          'Navent',
          'Tokko Broker (ARG)'
        ) THEN 'LATAM'
        ELSE 'BR'
      END AS company_country,
      CASE
        WHEN rd.dt_opened < DATE('2024-01-01') THEN 'Old SLA'
        ELSE 'New SLA'
      END AS sla_type,
      CASE
        WHEN j.title LIKE 'Execut%'
        AND j.title LIKE '%contas'
        AND ecf_requisitions.salary_band = 3 THEN 'Exec Contas 3 30 dias'
        WHEN ecf_requisitions.salary_band IN ('JA', 'Estag', 'Estag2', 'Estag1', 'Estag3') THEN 'JA/Intern SLA'
        WHEN ecf_requisitions.salary_band IN ('Assist', '1', '2', '3', 'Aux')
        AND ecf_requisitions.capacity_overhead = 'Capacity' THEN 'Bandas 1-3 Capacity SLA'
        WHEN ecf_requisitions.salary_band IN ('Assist', '1', '2', '3', 'Aux')
        AND ecf_requisitions.capacity_overhead = 'Overhead' THEN 'Bandas 1-3 Overhead SLA'
        WHEN ecf_requisitions.salary_band IN ('4', '5', '6')
        AND (
          (
            ecf_requisitions.capacity_overhead = 'Capacity'
            AND ecf_requisitions.career_track = 'Líder'
          )
          OR ecf_requisitions.capacity_overhead = 'Overhead'
        ) THEN 'Bandas 4-6 Overhead SLA'
        WHEN ecf_requisitions.salary_band IN ('4', '5', '6')
        AND ecf_requisitions.capacity_overhead = 'Capacity' THEN 'Bandas 4-6 Capacity SLA'
        WHEN ecf_requisitions.salary_band IN ('7', '8', '9')
        AND company_country <> 'LATAM' THEN 'Bandas 7-9 Overhead BR e PT SLA'
        WHEN ecf_requisitions.salary_band IN ('7', '8', '9')
        AND company_country = 'LATAM' THEN 'Bandas 7-9 Overhead LATAM SLA'
        WHEN ecf_requisitions.salary_band IN ('10', '11') THEN 'Bandas 10-11 SLA'
        WHEN ecf_requisitions.salary_band IN ('12', '13', '14') THEN 'Bandas 12+ SLA'
        ELSE NULL
      END AS new_sla_type,
      CASE
        WHEN new_sla_type = 'Bandas 1-3 Capacity SLA' THEN 20
        WHEN new_sla_type = 'Bandas 1-3 Overhead SLA' THEN 25
        WHEN new_sla_type = 'Bandas 4-6 Overhead SLA' THEN 35
        WHEN new_sla_type = 'Bandas 7-9 Overhead BR e PT SLA' THEN 40
        WHEN new_sla_type = 'Bandas 10-11 SLA' THEN 75
        WHEN new_sla_type = 'Bandas 12+ SLA' THEN 90
        WHEN new_sla_type = 'Bandas 7-9 Capacity SLA' THEN 40
        WHEN new_sla_type = 'Bandas 4-6 Capacity SLA' THEN 20
        WHEN new_sla_type = 'Bandas 7-9 Overhead LATAM SLA' THEN 60
        WHEN new_sla_type = 'JA/Intern SLA' THEN 30
        WHEN new_sla_type = 'Exec Contas 3 30 dias' THEN 30
        ELSE NULL
      END AS days_sla,
      CASE
        WHEN sla_type = 'Old SLA'
        AND COALESCE(rd.dt_filled, CURRENT_DATE) > rd.dt_closing_old_sla THEN DATEDIFF(COALESCE(rd.dt_filled, CURRENT_DATE), rd.dt_closing_old_sla)
        WHEN rd.days_open > days_sla THEN rd.days_open - days_sla
        ELSE 0
      END AS days_delay,
      CASE
        WHEN rd.dt_closing_old_sla IS NULL
        OR r.state IN (6, 2)
        OR rd.dt_opened IS NULL THEN NULL
        WHEN days_delay = 0 THEN 'On time'
        ELSE 'Delayed'
      END AS old_sla,
      CASE
        WHEN sla_type = 'Old SLA' THEN old_sla
        WHEN r.state IN (6, 2)
        OR rd.dt_opened IS NULL THEN NULL
        WHEN days_delay = 0 THEN 'On time'
        ELSE 'Delayed'
      END AS sla
    FROM
      datalake_workable_redshift_clean.requisitions AS r
    INNER JOIN 
      datalake_workable.requisition_dates AS rd
        ON r.id = rd.id
    LEFT JOIN 
      datalake_workable.custom_fields AS ecf_requisitions 
        ON r.id = ecf_requisitions.id_resource
    LEFT JOIN 
      datalake_workable_redshift_clean.jobs AS j 
        ON r.id_job = j.id
    LEFT JOIN 
      employee_consolidations AS eec_owner 
        ON r.id_owner = eec_owner.id_member_workable
    LEFT JOIN 
      employee_consolidations AS eec_hiring_manager 
        ON r.id_hiring_manager = eec_hiring_manager.id_member_workable
    LEFT JOIN 
      employee_consolidations AS eec_hiring_manager_cf 
        ON ecf_requisitions.hiring_manager_email = eec_hiring_manager_cf.work_email
    LEFT JOIN 
      employee_consolidations AS eec_business_partner 
        ON ecf_requisitions.business_partner = eec_business_partner.work_email
  )
SELECT
  MD5(CAST(id AS BINARY)) AS sk_requisition,
  sk_owner,
  sk_hiring_manager,
  sk_business_partner,
  id AS id_requisition,
  id_candidate,
  id_job,
  sk_hierarchy,
  code AS requisition_code,
  state AS requisition_state,
  status AS requisition_status,
  job_title,
  position_name,
  opening_reason,
  salary_band,
  capacity_overhead,
  affirmative_position,
  career_track,
  how_closed,
  cost_center,
  company_country,
  sla_type,
  sla,
  days_sla,
  days_on_hold,
  days_open,
  days_queue,
  days_delay,
  COALESCE(is_confidential, FALSE) AS is_confidential,
  dt_created,
  dt_opened,
  dt_filled,
  dt_cancelled,
  dt_last_on_hold,
  NOW() AS ts_load
FROM
  requisitions_details_step1