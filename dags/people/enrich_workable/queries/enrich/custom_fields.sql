WITH
  custom_fields AS (
    SELECT DISTINCT
      f.id,
      f.label,
      NULLIF(NULLIF(COALESCE(fc.label, fv.data), ''), 'N/A') AS response,
      fc.id AS id_field,
      fv.id_resource,
      fv.ts_updated
    FROM
      datalake_workable_redshift_clean.fields AS f
    LEFT JOIN 
      datalake_workable_redshift_clean.field_values AS fv 
        ON fv.id_field = f.id
    LEFT JOIN 
      datalake_workable_redshift_clean.field_value_choices AS fvc 
        ON fvc.id_field_value = fv.id
    LEFT JOIN 
      datalake_workable_redshift_clean.field_choices AS fc 
        ON fc.id = fvc.id_field_choice
    WHERE
      fv.id_resource IS NOT NULL
      AND f.id IN (
        10852861,9703446,10852862,9704821,10846889,10846891,10846892,10846893,
        10846912,10846913,10846914,9705595,10846915,9715997,10846917,10846918,
        10846940,10846941,9708921,10846942,10846943,10846946,9715918,10846947,
        9715999,8391521,10943566,11347475,10852863,9715678,10846945,9715715,
        11988194,11011710,10654611,10846948
      )
  )
SELECT
  id_resource,
  COALESCE(
    MAX(
      CASE
        WHEN id = 10852861 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 9703446 THEN response
      END
    )
  ) AS company,
  COALESCE(
    MAX(
      CASE
        WHEN id = 10852862 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 9704821 THEN response
      END
    )
  ) AS opening_reason,
  COALESCE(
    MAX(
      CASE
        WHEN id = 10846891 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 10846892 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 10846893 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 10846912 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 10846913 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 10846914 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 9705595 THEN response
      END
    )
  ) AS position_name,
  COALESCE(
    MAX(
      CASE
        WHEN id = 10846915 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 9715997 THEN response
      END
    )
  ) AS salary_band,
  MAX(
    CASE
      WHEN id = 10846917 THEN response
    END
  ) AS career_track,
  COALESCE(
    MAX(
      CASE
        WHEN id = 10846918 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 10846940 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 10846941 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 9708921 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 11988194 THEN response
      END
    )
  ) AS cost_center,
  MAX(
    CASE
      WHEN id = 10846943 THEN response
    END
  ) AS business_partner,
  COALESCE(
    MAX(
      CASE
        WHEN id = 10846946 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 9715918 THEN response
      END
    )
  ) AS affirmative_position,
  MAX(
    CASE
      WHEN id = 10846947 THEN response
    END
  ) AS how_closed,
  COALESCE(
    MAX(
      CASE
        WHEN id = 9715999 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 8391521 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 10943566 THEN response
      END
    )
  ) AS capacity_overhead,
  MAX(
    CASE
      WHEN id = 11011710 THEN
        CASE
          WHEN NOT CONTAINS (response, '@') THEN CONCAT(response, '@quintoandar.com.br')
          ELSE response
        END
    END
  ) AS hiring_manager_email,
  MAX(
    CASE
      WHEN id = 10846948 THEN response
    END
  ) AS candidate_source,
  MAX(
    CASE
      WHEN id = 10846889 THEN BOOLEAN(response)
    END
  ) AS is_confidential,
  MAX(
    CASE
      WHEN id = 10654611 THEN BOOLEAN(response)
    END
  ) AS is_hunted,
  MAX(
    CASE
      WHEN id = 11347475 THEN DATE(response)
    END
  ) AS dt_new_opened,
  COALESCE(
    MAX(
      CASE
        WHEN id = 10852863 THEN response
      END
    ),
    MAX(
      CASE
        WHEN id = 9715678 THEN TO_DATE(response, 'd MMMM yyyy')
      END
    )
  ) AS dt_closure_expected,
  COALESCE(
    MAX(
      CASE
        WHEN id = 10846945 THEN DATE(response)
      END
    ),
    MAX(
      CASE
        WHEN id = 9715715 THEN TO_DATE(response, 'd MMMM yyyy')
      END
    )
  ) AS dt_closure_renegotiated,
  MAX(ts_updated) AS ts_updated
FROM
  custom_fields
GROUP BY
  id_resource