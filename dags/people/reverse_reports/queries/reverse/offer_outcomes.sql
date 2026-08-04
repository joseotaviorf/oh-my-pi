-- Workable and Greenhouse offer accept/decline export for TA analytics.
-- Exception: Workable leg is inlined from datalake_workable_redshift_clean (frozen) and
-- datalake_gsheets_people_clean.mapping_wb_to_gh. Greenhouse leg uses greenhouse_v3_clean.
WITH declined_responses AS (
    SELECT
        COALESCE(field_values.ts_created, field_choices.ts_created) AS declined_date,
        candidates.id AS candidate_id,
        COALESCE(field_choices.label, field_values.data) AS response
    FROM
        datalake_workable_redshift_clean.fields AS fields
    LEFT JOIN
        datalake_workable_redshift_clean.field_values AS field_values
            ON fields.id = field_values.id_field
    LEFT JOIN
        datalake_workable_redshift_clean.field_value_choices AS field_value_choices
            ON field_value_choices.id_field_value = field_values.id
    LEFT JOIN
        datalake_workable_redshift_clean.field_choices AS field_choices
            ON field_choices.id = field_value_choices.id_field_choice
    LEFT JOIN
        datalake_workable_redshift_clean.candidates AS candidates
            ON candidates.id = field_values.id_resource
    WHERE
        fields.label LIKE '%Offer was accepted?%'
        OR fields.label LIKE '%Candidate declined%'
),
decline_reasons AS (
    SELECT
        candidates.id AS candidate_id,
        CASE
            WHEN field_choices.label IS NULL THEN field_values.data
            ELSE field_choices.label
        END AS reason_decline_offer
    FROM
        datalake_workable_redshift_clean.fields AS fields
    LEFT JOIN
        datalake_workable_redshift_clean.field_values AS field_values
            ON fields.id = field_values.id_field
    LEFT JOIN
        datalake_workable_redshift_clean.field_value_choices AS field_value_choices
            ON field_value_choices.id_field_value = field_values.id
    LEFT JOIN
        datalake_workable_redshift_clean.field_choices AS field_choices
            ON field_choices.id = field_value_choices.id_field_choice
    LEFT JOIN
        datalake_workable_redshift_clean.candidates AS candidates
            ON candidates.id = field_values.id_resource
    WHERE
        fields.label = 'If no, check the reason of the decline'
),
declined_offers AS (
    SELECT
        declined.declined_date,
        candidates.id_job,
        candidates.job_title,
        candidates.id AS id_candidate,
        candidates.name AS candidate_name,
        candidates.current_stage_name,
        jobs.department,
        parent_dept.name AS job_department_macro,
        decline_reasons.reason_decline_offer
    FROM
        datalake_workable_redshift_clean.candidates AS candidates
    LEFT JOIN
        datalake_workable_redshift_clean.jobs AS jobs
            ON candidates.id_job = jobs.id
    LEFT JOIN
        declined_responses AS declined
            ON candidates.id = declined.candidate_id
    LEFT JOIN
        decline_reasons
            ON candidates.id = decline_reasons.candidate_id
    LEFT JOIN
        datalake_workable_redshift_clean.departments AS dept
            ON dept.id = jobs.id_department
    LEFT JOIN
        datalake_workable_redshift_clean.departments AS parent_dept
            ON parent_dept.id = dept.id_parent
    WHERE
        (
            LOWER(declined.response) = LOWER('false')
            OR candidates.disqualification_reason = 'Rejected offer'
        )
        AND candidates.current_stage_name = 'Offer'
        AND candidates.job_title <> 'Analista de Teste de Offer - 5A, CM e Velo'
),
workable_rejected_offers AS (
    SELECT
        TO_DATE(declined.declined_date) AS response_date,
        CAST(declined.id_job AS STRING) AS req_id,
        declined.job_title,
        CAST(declined.id_candidate AS STRING) AS application_id,
        declined.candidate_name,
        declined.current_stage_name,
        'Rejected' AS offer_status,
        declined.department AS job_department,
        declined.job_department_macro AS job_department_macro,
        declined.reason_decline_offer,
        'WB' AS source_system,
        '-' AS l1,
        '-' AS employment_type
    FROM
        declined_offers AS declined
    WHERE
        declined.declined_date >= TIMESTAMP('2024-01-01')
),
candidate_hunted AS (
    SELECT c.id AS c_id, fv.data
    FROM datalake_workable_redshift_clean.fields f 
    LEFT JOIN datalake_workable_redshift_clean.field_values fv ON fv.id_field = f.id
    LEFT JOIN datalake_workable_redshift_clean.candidates c ON c.id = fv.id_resource 
    WHERE f.label = 'Candidate was hunted?'
  ),
first_hire AS (
  SELECT DISTINCT 
    a.action, 
    a.id_candidate, 
    MIN(a.ts_activity_created) AS hired_at
  FROM datalake_workable_redshift_clean.activities a
  WHERE a.action = 'Candidate moved to stage "Hired"'
  GROUP BY a.action, a.id_candidate
),
first_opened AS (SELECT DISTINCT 
    a.action, 
    a.id_trackable, 
    MIN(a.ts_activity_created) AS opened_at
  FROM datalake_workable_redshift_clean.activities a
  WHERE a.action = 'requisition-open'
  GROUP BY a.action, a.id_trackable
),
cancelled_at AS (SELECT DISTINCT
  a.action,
  a.id_trackable,
  a.ts_activity_created
  from datalake_workable_redshift_clean.activities a
where a.action = 'requisition-cancelled'
),
custom_fields AS ( -- cf = custom_fields
  SELECT DISTINCT
  r.id as id_req, 
    r.code, 
      f.id, 
      f.label, 
      fc.label AS value, 
      fv.data, 
      fc.id AS id_field,
      case when f.id = 12353302 and fc.label <> fv.data and fv.data in ('deborah leticia gouveia abi saber','lara anderlini hammoud','lauren morton','lucas maia alves de lima') then fv.data
      else fc.label end as l1_override_value
    FROM datalake_workable_redshift_clean.fields AS f 
      LEFT JOIN datalake_workable_redshift_clean.field_values fv ON fv.id_field = f.id 
      LEFT JOIN datalake_workable_redshift_clean.field_value_choices fvc ON fvc.id_field_value = fv.id 
      LEFT JOIN datalake_workable_redshift_clean.field_choices fc ON fc.id = fvc.id_field_choice 
      LEFT JOIN datalake_workable_redshift_clean.requisitions r ON r.id = fv.id_resource 
    WHERE 
      code <> ''
  ),
requisitions_staged AS (
    SELECT
  r.id AS req_id, 
  r.code AS req_code,
  j.id AS job_id,
  j.title AS title,
  CASE 
    WHEN min(r.state) = 0 THEN 'draft' 
    WHEN min(r.state) = 1 THEN 'pending' 
    WHEN min(r.state) = 2 THEN 'approved' 
    WHEN min(r.state) = 3 THEN 'open' 
    WHEN min(r.state) = 4 THEN 'filled' 
    WHEN min(r.state) = 5 THEN 'rejected' 
    WHEN min(r.state) = 6 THEN 'cancelled' 
    WHEN min(r.state) = 7 THEN 'reserved' 
    ELSE 'on hold' 
  END AS status,
  any_value(m.name) as requisition_owner,
  any_value(m2.name) as hiring_manager,
  any_value(r.ts_created) as created_at,
  any_value(r.dt_plan) as plan_date,  
  r.dt_opened as opened_on,
  CASE 
        WHEN r.code IN ('5A5532','5A5261','5A5286') THEN '2024-11-29'
        WHEN r.code IN ('5A5087-2','5A4759','5A5140') THEN '2024-09-01'
        WHEN r.code = '5A5490' THEN '2024-10-28'
        WHEN r.code = '5A5435' THEN '2024-10-29'
        WHEN r.code = '5A4551' THEN '2024-11-01'
        WHEN r.code IN ('5A5838','5A4997') THEN '2024-12-31'
        ELSE any_value(first_hire.hired_at)
  END as filled_on,
  cancelled_at.ts_activity_created as cancelled_at,
  MAX(CASE WHEN cf.id = '10846949' AND cf.value <> '' THEN cf.value END) AS diversity_profiles_presented,
  COALESCE(
    MAX(CASE WHEN cf.id = '10852861' AND cf.value <> '' THEN cf.value END),
    MAX(CASE WHEN cf.id = '9703446' AND cf.data <> '' THEN cf.data END)
  ) AS company,
  MAX(CASE WHEN cf.id = '10846888' THEN cf.data END) AS country,
  COALESCE(
    MAX(CASE WHEN cf.id = '10852862' AND cf.value <> '' THEN cf.value END),
    MAX(CASE WHEN cf.id = '9704821' AND cf.data <> '' THEN cf.data END)
  ) AS hiring_reason,
  COALESCE(
    MAX(CASE WHEN cf.id = '10846887' AND cf.value <> '' THEN cf.value END),
    MAX(CASE WHEN cf.id = '9703446' AND cf.data <> '' THEN cf.data END)
  ) AS brand,
  MAX(CASE WHEN cf.id = '10846889' AND cf.data <> '' THEN cf.data END) AS is_confidential_requisition,
  MAX(CASE WHEN cf.id = '10846890' AND cf.data <> '' THEN cf.data END) AS replaced_employee_email,
 COALESCE(
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '10846891' AND cf.data <> '' THEN cf.data END)), 'N/A'),
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '10846892' AND cf.data <> '' THEN cf.data END)), 'N/A'),
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '10846893' AND cf.data <> '' THEN cf.data END)), 'N/A'),
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '10846912' AND cf.data <> '' THEN cf.data END)), 'N/A'),
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '10846913' AND cf.data <> '' THEN cf.data END)), 'N/A'),
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '10846914' AND cf.data <> '' THEN cf.data END)), 'N/A'),
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '9705595' AND cf.data <> '' THEN cf.data END)), 'N/A'),
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '11926384' AND cf.data <> '' THEN cf.data END)), 'N/A'),
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '12090736' AND cf.data <> '' THEN cf.data END)), 'N/A')
) AS position_name,
  COALESCE(
    MAX(CASE WHEN fv.id_field = '10846915' AND fv.data <> '' THEN fv.data END),
    MAX(CASE WHEN fv.id_field = '9715997' AND fv.data <> '' THEN fv.data END)
  ) AS band,
  MAX(CASE WHEN cf.id = '10846916' AND cf.data <> '' THEN cf.data END) AS salary_table,
  MAX(CASE WHEN cf.id = '10846917' AND cf.data <> '' THEN cf.data END) AS career_path,
  COALESCE(
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '12090737' AND cf.data <> '' THEN cf.data END)), 'N/A'), -- Centro de Custo: 
    NULLIF(TRIM(REPLACE(MAX(CASE WHEN cf.id = '10846918' AND cf.data <> '' THEN cf.data END),CHAR(10), '')), 'N/A'), -- Centro de Custo - Product & Tech
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '10846940' AND cf.data <> '' THEN cf.data END)), 'N/A'), -- Centro de Custo - Operations
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '10846941' AND cf.data <> '' THEN cf.data END)), 'N/A'), -- Centro de Custo - Corp
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '9708921' AND cf.data <> '' THEN cf.data END)), 'N/A'), -- Centro de Custo
    NULLIF(TRIM(MAX(CASE WHEN cf.id = '11988194' AND cf.data <> '' THEN cf.data END)), 'N/A') -- Centro de Custo - Latam
  ) AS cost_center,
  -- MAX(CASE WHEN cf.id = '10846942' AND cf.value <> '' THEN cf.value END) AS line,
  MAX(CASE WHEN cf.id = '10846943' AND cf.value <> '' THEN cf.value END) AS bp,
      COALESCE(
    MAX(CASE 
        WHEN cf.id = '10852863' AND cf.data <> '' THEN cf.data 
    END),
    MAX(CASE 
        WHEN cf.id = '9715678' AND cf.data <> '' THEN
            TO_DATE(
                DATE_FORMAT(TO_TIMESTAMP(cf.data, 'd MMMM yyyy'), 'yyyy-MM-dd'),
                'yyyy-MM-dd'
            )
    END)
  ) AS expected_close_date, 
  COALESCE(
    TO_DATE(MAX(CASE 
        WHEN cf.id = '10846945' AND cf.data <> '' THEN cf.data 
    END), 'yyyy-MM-dd'),
    TO_DATE(MAX(CASE 
        WHEN cf.id = '9715715' AND cf.data <> '' THEN cf.data 
    END), 'yyyy-MM-dd')
  ) AS renegotiated_close_date, 
  MAX(CASE WHEN cf.id = '10846944' AND cf.data <> '' THEN cf.data END) AS hunting_start_date,
  COALESCE(MAX(CASE WHEN cf.id = '10846946' AND cf.value <> '' THEN cf.value END),
           MAX(CASE WHEN cf.id = '9715918' AND cf.data <> '' THEN cf.data END)) AS affirmative_requisition,
  MAX(CASE WHEN cf.id = '10846947' AND cf.value <> '' THEN cf.value END) AS how_requisition_was_closed,
  COALESCE(
    MAX(
        CASE 
            WHEN cf.id = '10846948' AND cf.value <> '' THEN cf.value 
        END
    ),
    CASE 
        WHEN candidate_hunted.data = 'true' OR (c.source = 'Uploaded' AND c.application_method = 'Uploaded') THEN 'Hunting'
        WHEN c.source = 'referral' OR c.application_method = 'Referred' OR source_category = 'Referrals' THEN 'Referência' 
        WHEN c.source = 'internal_application' THEN 'Aplicação interna'
        WHEN c.application_method = 'Applied' OR (c.source_category = 'Job Boards' AND c.application_method = 'LinkedIn') THEN 'Orgânico'
        WHEN c.source = 'Copied' AND c.application_method = 'Copied' THEN 'Copied'
        WHEN c.source IS NULL AND c.application_method = 'Uploaded' AND c.source_category = 'Other' THEN 'Suggested by Workable'
    END
  ) AS candidate_source,
  MAX(CASE
    WHEN cf.id = '10846950' AND cf.data <> '' THEN cf.data
    WHEN r.code IN (
      '5A3265',
      '5A3301',
      '5A3363-3',
      '5A3363-4',
      '5A3364',
      '5A3503',
      '5A3472',
      '5A3198',
      '5A3392',
      '5A3632',
      '5A3615-1',
      '5A3690-2',
      '5A3574',
      '5A3611',
      '5A3668',
      '5A3696',
      '5A3822-1',
      '5A3822-2',
      '5A3599',
      '5A3826',
      '5A3838',
      '5A3978',
      '5A4296',
      '5A4329'
    ) THEN 'TRUE'
  END) AS closed_with_diverse_profile,
  MAX(CASE
    WHEN cf.id = '10846951' AND cf.value <> '' THEN cf.value
      WHEN r.code IN (
      '5A3265',
      '5A3301',
      '5A3363-3',
      '5A3363-4',
      '5A3364',
      '5A3503',
      '5A3472',
      '5A3198',
      '5A3392',
      '5A3632',
      '5A3615-1',
      '5A3690-2',
      '5A3574',
      '5A3611',
      '5A3668',
      '5A3696',
      '5A3822-1',
      '5A3822-2',
      '5A3599',
      '5A3826',
      '5A3838',
      '5A3978',
      '5A4296',
      '5A4329'
    ) THEN 'Pessoa com Deficiência'
  END) AS diverse_profile,
  COALESCE(
    MAX(CASE WHEN cf.id = '10852864' AND cf.data <> '' THEN cf.data END),
    MAX(CASE WHEN cf.id = '9715770' AND cf.data <> '' THEN cf.data END)
  ) AS delay_reason,
  MAX(CASE WHEN cf.id = '10846952' AND cf.data <> '' THEN cf.data END) AS other_delay_reason,
  COALESCE(
    MAX(CASE WHEN cf.id = '9716094' AND cf.data <> '' THEN cf.data END),
    MAX(CASE WHEN cf.id = '10846955' AND cf.data <> '' THEN cf.data END)
  ) AS notes,
  MAX(CASE WHEN cf.id = '10853195' AND cf.value <> '' THEN cf.value END) AS level,
  CASE 
    WHEN r.code in ('5A6821','5A6822','5A6828','5A6876-1') then 'Overhead'
    ELSE COALESCE(
       MAX(CASE WHEN cf.id = '9715999' AND cf.data <> '' THEN cf.data END),
       MAX(CASE WHEN cf.id = '8391521' AND cf.data <> '' THEN cf.data END),
       MAX(CASE WHEN cf.id = '10943566' AND cf.value <> '' THEN cf.value END)
       )
  END AS capacity_overhead,
  
  TRIM(REGEXP_REPLACE(COALESCE(
    MAX(CASE WHEN r.code = '5A4977' then 'monique.zardin@quintoandar.com.br' END),
    MAX(CASE WHEN cf.id = '11011710' AND cf.data <> '' THEN cf.data END)
  ), '\\t', ' ')) AS hiring_manager_email,
  MAX(CASE WHEN cf.id = '11347475' AND cf.data <> '' THEN cf.data END) AS new_opened_on, -- form opened date; remove on next update 
    r.id_candidate as candidate_id,
    c.name as candidate_name,
  CASE 
    WHEN r.code = '5A5255' THEN 'Data'
    WHEN r.code IN ('5A5377','5A5287','5A5188','5A5104-2','5A5427') THEN 'Product and technology'
    ELSE j.department
  END AS job_department,
  dp.name AS job_department_macro,
  r.dt_start as start_date,
  p.name as pipeline,
  MAX(
    CASE
      WHEN r.code IN (
        '5A5539-5', '5A5539-4', '5A5553', '5A5356', '5A5280', '5A5225', '5A5206', '5A5084', '5A4953', '5A4963', '5A4670-3', '5A4613', '5A4572-2', '5A4572-1', '5A4551', '5A4580-4', '5A5539-1', '5A5707'
        ) THEN 'nicolau mari de camargo'
      WHEN r.code IN (
        '5A5691', '5A5530-13', '5A5453', '5A5427', '5A5330', '5A5106', '5A5104-2', '5A4904', '5A4804', '5A4793', '5A4535', '5A4475', '5A5943-1', '5A5839', '5A4748-3', '5A5306'
        ) THEN 'paulo braz golgher'
      WHEN r.code IN (
        '5A5626', '5A5490', '5A5374', '5A5244', '5A5175', '5A4191', '5A4667', '5A4699', '5A4996', '5A5296', '5A5510'
        ) THEN 'deborah leticia gouveia abi saber'
      WHEN r.code IN (
        '5A5682', '5A5965', '5A5493', '5A5985', '5A4877', '5A5294', '5A5992', '5A5782'
        ) THEN 'larissa fontaine'
      WHEN r.code IN (
        '5A5450', '5A5449', '5A5304', '5A5173', '5A5158', '5A4921', '5A5931'
        ) THEN 'abel federico picchio'
      WHEN r.code IN (
        '5A4311'
        ) THEN 'lauren morton'
      WHEN r.code IN (
        '5A5729', '5A5080', '5A4876', '5A4518'
        ) THEN 'ana carolina pellegrini monteiro'
      WHEN r.code IN (
        '5A4588', '5A4501', '5A5763', '5A5756', '5A5839','5A4512','5A4557','5A4559','5A4564','5A4582','5A4593','5A4612','5A4697','5A4743-1','5A4743-2','5A4744','5A4850','5A4881','5A4890','5A4897-1','5A4897-2','5A4897-3','5A4914-1','5A4914-2','5A4914-3','5A5020','5A5029','5A5053','5A5063','5A5064','5A5097','5A5098-1','5A5098-2','5A5099','5A5156','5A5171','5A5200','5A5226','5A5227-1','5A5227-2','5A5228','5A5229','5A5231','5A5242','5A5251','5A5283', '5A5292','5A5295-1','5A5295-2','5A5307','5A5312','5A5326','5A5349-1','5A5349-2','5A5383','5A5386','5A5393','5A5394','5A5401','5A5424','5A5437','5A5477-1','5A5477-2','5A5477-3','5A5477-4','5A5477-5','5A5525','5A5556-1','5A5556-2','5A5599-1','5A5599-2','5A5625','5A5655','5A5657','5A5697','5A5709','5A5797','5A5798','5A5802','5A5911','5A5950', '5A5996','5A5999-3','5A5999-4'
        ) THEN 'lucas maia alves de lima'
      WHEN r.code IN (
        '5A5654'
        ) THEN 'lara anderlini hammoud'
      -- Custom field override
      WHEN cf.id = '12353302' AND cf.l1_override_value <> '' THEN cf.l1_override_value
        ELSE NULL
    END
  ) AS l1_manager_form,
  any_value(rs.value) AS rs_requisition_type_value
FROM datalake_workable_redshift_clean.requisitions r
LEFT JOIN datalake_workable_redshift_clean.candidates c ON c.id = r.id_candidate
LEFT JOIN datalake_workable_redshift_clean.jobs j on j.id = r.id_job
LEFT JOIN datalake_workable_redshift_clean.pipelines p on j.id_pipeline = p.id
LEFT JOIN datalake_workable_redshift_clean.members m ON m.id = r.id_owner
LEFT JOIN datalake_workable_redshift_clean.members m2 ON m2.id = r.id_hiring_manager
LEFT JOIN datalake_workable_redshift_clean.activities a ON a.id_candidate = r.id_candidate
LEFT JOIN datalake_workable_redshift_clean.field_values fv ON fv.id_resource = r.id
LEFT JOIN candidate_hunted ON candidate_hunted.c_id = c.id
LEFT JOIN first_hire ON r.id_candidate = first_hire.id_candidate
LEFT JOIN first_opened ON r.id = first_opened.id_trackable
LEFT JOIN cancelled_at ON r.id = cancelled_at.id_trackable
LEFT JOIN custom_fields AS cf ON cf.id_req = r.id
LEFT JOIN datalake_workable_redshift_clean.departments d on d.id = j.id_department
LEFT JOIN datalake_workable_redshift_clean.departments dp on dp.id = d.id_parent
LEFT JOIN custom_fields AS rs ON (rs.id_req = r.id AND rs.id = 14170994)
WHERE 1=1
  AND r.code NOT IN ('5A5880','5A1932')
  AND r.id_job NOT IN (2641112,4358229)
GROUP BY
  r.id, r.code, j.id, j.title, r.id_candidate, c.name, j.department, r.dt_start, p.name, candidate_hunted.data, c.source, c.application_method, c.source_category, first_opened.opened_at, dp.name, cancelled_at.ts_activity_created, r.dt_opened

),
requisitions_with_close_dates AS (
    SELECT
        staged.*,
        COALESCE(staged.renegotiated_close_date, staged.expected_close_date) AS final_agreed_close_date
    FROM
        requisitions_staged AS staged
),
requisitions_with_type AS (
    SELECT
        with_close.*,
        COALESCE(
            with_close.rs_requisition_type_value,
            CASE
                WHEN with_close.title ILIKE '%xecut%' AND with_close.title ILIKE '%conta%' THEN 'Exec. Contas B3'
                WHEN with_close.capacity_overhead = 'Capacity' AND with_close.career_path = 'Líder' THEN 'Capacity Leader'
                WHEN with_close.capacity_overhead = 'Capacity'
                    AND with_close.band NOT IN ('JA', 'Estag', 'Estag1', 'Estag2', 'Estag3') THEN 'Capacity'
                WHEN with_close.band IN ('JA', 'Estag', 'Estag1', 'Estag2', 'Estag3') THEN 'JA/Intern'
                WHEN with_close.band IN ('1', '2', '3') THEN '01-03'
                WHEN with_close.band IN ('4', '5', '6') THEN '04-06'
                WHEN with_close.band IN ('7', '8', '9')
                    AND LOWER(with_close.country) IN (
                        'perú', 'peru', 'panamá', 'panama', 'méxico', 'mexico', 'equador', 'argentina'
                    ) THEN 'LATAM 07-09'
                WHEN with_close.band IN ('7', '8', '9') THEN '07-09'
                WHEN with_close.band IN ('10', '11') THEN '10-11'
                WHEN TRY_CAST(with_close.band AS INT) >= 12 THEN '12+'
                ELSE 'Out of rule'
            END
        ) AS requisition_type
    FROM
        requisitions_with_close_dates AS with_close
),
requisitions_with_sla_table AS (
    SELECT
        with_type.*,
        CASE
            WHEN with_type.requisition_type = 'Exec. Contas B3' THEN 30
            WHEN with_type.requisition_type = 'Capacity Leader' THEN 35
            WHEN with_type.requisition_type = 'Capacity' THEN 20
            WHEN with_type.requisition_type = 'JA/Intern' THEN 30
            WHEN with_type.requisition_type = '01-03' THEN 25
            WHEN with_type.requisition_type = '04-06' THEN 35
            WHEN with_type.requisition_type = '07-09' THEN 40
            WHEN with_type.requisition_type = 'LATAM 07-09' THEN 60
            WHEN with_type.requisition_type = '10-11' THEN 75
            WHEN with_type.requisition_type = '12+' THEN 90
        END AS sla_table_days
    FROM
        requisitions_with_type AS with_type
),
requisitions_with_sla_group AS (
    SELECT
        with_sla.*,
        CASE
            WHEN (
                with_sla.capacity_overhead = 'Overhead'
                AND TRY_CAST(with_sla.band AS INT) < 10
            )
            OR with_sla.req_code IN ('5A6821', '5A6822', '5A6828', '5A6876-1') THEN 'SLA OH until B9'
            WHEN with_sla.capacity_overhead = 'Capacity' THEN 'SLA Massive'
            WHEN TRY_CAST(with_sla.band AS INT) > 9 THEN 'SLA OH B10+'
            ELSE 'Undefined'
        END AS sla_group
    FROM
        requisitions_with_sla_table AS with_sla
),
requisitions_with_sla_days AS (
    SELECT
        with_group.*,
        CASE
            WHEN with_group.sla_group = 'SLA Massive' THEN 25
            WHEN with_group.sla_group = 'SLA OH until B9' THEN 45
            WHEN with_group.sla_group = 'SLA OH B10+' THEN 60
            ELSE 0
        END AS sla_days
    FROM
        requisitions_with_sla_group AS with_group
),
requisitions_new AS (
    SELECT
        with_days.*,
        DATE_ADD(with_days.opened_on, with_days.sla_table_days) AS expected_sla_close_date,
        DATE_ADD(with_days.opened_on, with_days.sla_days) AS sla_expected_date,
        CASE
            WHEN EXTRACT(YEAR FROM with_days.created_at) = 2024 THEN 'SLA Novo'
            WHEN EXTRACT(YEAR FROM with_days.created_at) = 2025 THEN 'SLA 2025'
            ELSE 'Other SLA'
        END AS sla_type,
        COALESCE(with_days.new_opened_on, with_days.opened_on) AS sla_opened_on_adjusted,
        CURRENT_TIMESTAMP() AS ts_updated
    FROM
        requisitions_with_sla_days AS with_days
),
requisitions_projected AS (
    SELECT
        req_id,
        req_code,
        job_id,
        title,
        status,
        candidate_id,
        candidate_name,
        created_at,
        filled_on,
        job_department,
        job_department_macro,
        l1_manager_form AS l1
    FROM
        requisitions_new
    WHERE
        created_at >= TIMESTAMP('2024-01-01')
        OR filled_on >= TIMESTAMP('2024-01-01')
),
requisitions_ranked AS (
    SELECT
        projected.*,
        ROW_NUMBER() OVER (
            PARTITION BY projected.req_code
            ORDER BY projected.created_at DESC NULLS LAST, projected.req_id DESC
        ) AS rn
    FROM
        requisitions_projected AS projected
),
workable_accepted_offers AS (
    SELECT
        TO_DATE(requisitions.filled_on) AS response_date,
        requisitions.req_code AS req_id,
        requisitions.title AS job_title,
        CAST(requisitions.candidate_id AS STRING) AS application_id,
        requisitions.candidate_name,
        'hired' AS current_stage_name,
        'Accepted' AS offer_status,
        requisitions.job_department AS job_department,
        requisitions.job_department_macro AS job_department_macro,
        CAST(NULL AS STRING) AS reason_decline_offer,
        'WB' AS source_system,
        requisitions.l1 AS l1,
        '-' AS employment_type
    FROM
        requisitions_ranked AS requisitions
    LEFT JOIN
        datalake_gsheets_people_clean.mapping_wb_to_gh AS mapping
            ON UPPER(mapping.requisition_code) = requisitions.req_code
    WHERE
        requisitions.rn = 1
        AND mapping.job_opening_id IS NULL
        AND requisitions.status = 'filled'
        AND requisitions.filled_on >= DATE('2024-01-01')
),
workable_offers AS (
    SELECT
        rejected.*
    FROM
        workable_rejected_offers AS rejected
    UNION ALL
    SELECT
        accepted.*
    FROM
        workable_accepted_offers AS accepted
),
job_departments AS (
    SELECT
        jobs.id_job,
        CASE
            WHEN dept.id_parent IS NULL THEN NULL
            ELSE jobs.id_department
        END AS id_department,
        CASE
            WHEN dept.id_parent IS NULL THEN jobs.id_department
            ELSE dept.id_parent
        END AS id_parent_department
    FROM
        datalake_greenhouse_v3_clean.jobs AS jobs
    LEFT JOIN
        datalake_greenhouse_v3_clean.departments AS dept
            ON jobs.id_department = dept.id_department
),
current_stage_ranked AS (
    SELECT
        astg.id_application,
        curr_stage.name AS current_stage_name,
        ROW_NUMBER() OVER (
            PARTITION BY astg.id_application
            ORDER BY astg.ts_updated DESC NULLS LAST, astg.id DESC
        ) AS rn
    FROM
        datalake_greenhouse_v3_clean.application_stages AS astg
    INNER JOIN
        datalake_greenhouse_v3_clean.job_interview_stages AS curr_stage
            ON curr_stage.id_job_interview_stage = astg.id_job_interview_stage
    WHERE
        astg.is_current = TRUE
),
current_stage AS (
    SELECT
        id_application,
        current_stage_name
    FROM
        current_stage_ranked
    WHERE
        rn = 1
),
latest_offers_ranked AS (
    SELECT
        ofr.id_application,
        ofr.id_job,
        ofr.id_candidate,
        ofr.ts_resolved,
        ofr.status,
        ofr.employment_type,
        ROW_NUMBER() OVER (
            PARTITION BY ofr.id_application
            ORDER BY ofr.version DESC
        ) AS rn
    FROM
        datalake_greenhouse_v3_clean.offers AS ofr
),
latest_offers AS (
    SELECT
        id_application,
        id_job,
        id_candidate,
        ts_resolved,
        status,
        employment_type
    FROM
        latest_offers_ranked
    WHERE
        rn = 1
),
latest_rejection_ranked AS (
    SELECT
        rejection.id_application,
        rejection.id_rejection_reason,
        ROW_NUMBER() OVER (
            PARTITION BY rejection.id_application
            ORDER BY rejection.ts_created DESC
        ) AS rn
    FROM
        datalake_greenhouse_v3_clean.rejection_details AS rejection
),
latest_rejection AS (
    SELECT
        id_application,
        id_rejection_reason
    FROM
        latest_rejection_ranked
    WHERE
        rn = 1
),
greenhouse_offers AS (
    SELECT
        TO_DATE(ofr.ts_resolved) AS response_date,
        CAST(jobs.id_requisition AS STRING) AS req_id,
        jobs.name AS job_title,
        CAST(ofr.id_application AS STRING) AS application_id,
        CONCAT_WS(' ', cand.first_name, cand.last_name) AS candidate_name,
        CASE
            WHEN LOWER(ofr.status) = 'accepted' THEN 'hired'
            ELSE cs.current_stage_name
        END AS current_stage_name,
        ofr.status AS offer_status,
        dept.name AS job_department,
        parent_dept.name AS job_department_macro,
        rejection_reasons.name AS reason_decline_offer,
        'GH' AS source_system,
        jobs.l1_full_name AS l1,
        ofr.employment_type
    FROM
        latest_offers AS ofr
    LEFT JOIN
        datalake_greenhouse_v3_clean.jobs AS jobs
            ON jobs.id_job = ofr.id_job
    LEFT JOIN
        datalake_greenhouse_v3_clean.candidates AS cand
            ON cand.id_candidate = ofr.id_candidate
    LEFT JOIN
        current_stage AS cs
            ON cs.id_application = ofr.id_application
    LEFT JOIN
        job_departments AS jdept
            ON jdept.id_job = jobs.id_job
    LEFT JOIN
        datalake_greenhouse_v3_clean.departments AS dept
            ON dept.id_department = jdept.id_department
    LEFT JOIN
        datalake_greenhouse_v3_clean.departments AS parent_dept
            ON parent_dept.id_department = jdept.id_parent_department
    LEFT JOIN
        latest_rejection AS rejection_details
            ON rejection_details.id_application = ofr.id_application
    LEFT JOIN
        datalake_greenhouse_v3_clean.rejection_reasons AS rejection_reasons
            ON rejection_reasons.id_rejection_reason = rejection_details.id_rejection_reason
    WHERE
        jobs.employment_type NOT IN ('Contract', 'Temporary')
),
combined_offers AS (
    SELECT
        gh.*
    FROM
        greenhouse_offers AS gh
    UNION ALL
    SELECT
        wb.*
    FROM
        workable_offers AS wb
)
SELECT
    offers.response_date,
    offers.req_id,
    offers.job_title,
    offers.application_id,
    offers.candidate_name,
    offers.current_stage_name,
    offers.offer_status,
    offers.job_department AS dpto_job,
    offers.job_department_macro AS dpto_job_macro,
    offers.reason_decline_offer,
    offers.source_system AS fl_system,
    offers.l1,
    offers.employment_type,
    DATE('{load_start_date}') AS data_atualizacao,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    combined_offers AS offers
