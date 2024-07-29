WITH assessment AS (
    SELECT
        a.id_assessment,
        a.id_previous_assessment,
        a.id_inspection,
        a.dt_owner_limit_revision,
        a.dt_tenant_limit_revision
    FROM
        datalake_inspections_clean.assessment AS a 
    QUALIFY 
        a.ts_updated = MAX(a.ts_updated) OVER(PARTITION BY a.id_assessment)
)
SELECT DISTINCT
    ra.id_reviewer,
    ra.id_user,
    ra.id_assessment,
    a.id_previous_assessment,
    a.id_inspection,
    ra.reviewer_type,
    ra.approval_reason,
    ra.approval_comment,
    ra.approval_type,
    ra.is_approved,
    ra.mod_is_approved,
    CASE 
      WHEN ra.reviewer_type = "OWNER" THEN a.dt_owner_limit_revision
      WHEN ra.reviewer_type = "TENANT" THEN a.dt_tenant_limit_revision
    END AS dt_limit_revision,
    ra.ts_approved,
    ra.ts_created,
    ra.ts_updated,
    ra.year,
    ra.month,
    ra.day
FROM
    datalake_inspections_clean.reviewer_aud AS ra
JOIN
    assessment AS a
      ON a.id_assessment = ra.id_assessment
WHERE
    MAKE_DATE(ra.year, ra.month, ra.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ra.ts_updated = MAX(ra.ts_updated) OVER (PARTITION BY ra.id_reviewer)
