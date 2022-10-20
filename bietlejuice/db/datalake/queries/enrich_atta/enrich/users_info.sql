WITH cte_most_recent AS (
    SELECT
        id_user,
        MAX(ts_last_updated) AS ts_last_updated
    FROM
        datalake_atta_clean.users_info
    GROUP BY 1
)
SELECT
    ui.id_user,
    ui.id_user_registration,
    ui.id_partner,
    ui.id_franchise,
    ui.user_name,
    ui.user_last_name,
    ui.user_email,
    ui.user_status,
    ui.ts_last_updated
FROM
    datalake_atta_clean.users_info AS ui
RIGHT JOIN
    cte_most_recent AS cte
        ON cte.id_user = ui.id_user
        AND cte.ts_last_updated = ui.ts_last_updated
