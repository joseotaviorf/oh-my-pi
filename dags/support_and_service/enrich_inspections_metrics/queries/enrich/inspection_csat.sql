WITH inspections AS (
    SELECT
        fi.id_inspection,
        fi.id_contract,
        fi.inspection_type,
        fi.ts_inspected,
        fi.ts_created,
        COALESCE(
            LEAD(fi.ts_inspected) OVER(PARTITION BY fi.id_contract ORDER BY fi.ts_created),
            CURRENT_DATE
        ) AS ts_next_inspected
    FROM
        datalake_inspections.inspection_booking AS fi
    WHERE
        fi.status NOT IN ('scheduled', 'cancelled', 'ContratoCancelado')
        AND fi.ts_inspected IS NOT NULL
    GROUP BY 1,2,3,4,5
)
SELECT
    sa.id_answer,
    i.id_inspection,
    sa.id_contract,
    sa.year,
    sa.month,
    sa.day
FROM
    datalake_satisfaction_rating.satisfaction_answers AS sa
LEFT JOIN
    inspections AS i
        ON sa.id_contract = i.id_contract
        AND sa.service_context = i.inspection_type
        AND sa.ts_submitted >= i.ts_inspected
        AND sa.ts_submitted < i.ts_next_inspected
WHERE
    sa.service_type = "inspection"
    AND sa.year = {year}
    AND sa.month = {month}
    AND sa.day = {day}