-- Active-employee AI adoption roster, exported as S3 CSV.
-- Consumer: AI Adoption Portal (https://5a-ai-adoption-portal.base44.app/).
-- Destination: Base44 office bucket, aiadoption/vertical_information.csv.
-- One row per active employee assignment: work email, assignment number, the
-- work email of the layer-1 leader (one level below the CEO) in the reporting
-- chain, and the work email of the direct manager (immediate supervisor).
SELECT
    LOWER(es.work_email) AS email,
    LOWER(es.assignment_number) AS assignment_number,
    NULLIF(LOWER(es.email_l1), '-1') AS email_l1,
    LOWER(es.manager_work_email) AS email_manager
FROM
    metric_people.employee_snapshots AS es
WHERE
    es.is_current_for_employee = TRUE
    AND es.is_active = TRUE
