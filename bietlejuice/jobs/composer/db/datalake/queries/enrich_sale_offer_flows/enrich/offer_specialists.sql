WITH last_specialist AS (
    SELECT
        ROW_NUMBER() OVER (
            PARTITION BY 
                id_sales_flow,
                kind
            ORDER BY
                sp.ts_updated DESC
        ) AS row,
        sp.*,
        us.id AS id_user
    FROM
        datalake_sales_flow_clean.specialist AS sp
    LEFT JOIN 
        datalake_ebdb_clean.user AS us
            ON sp.id_main_user = us.id
),
offers_specialists AS (
    SELECT
        id_firestore AS id_offer,
        id_sales_flow
    FROM
        datalake_sales_flow_clean.offer AS o
    GROUP BY
        1,
        2
)
SELECT
    id_offer,
    dm.id_user AS id_user_consultant,
    dm.id_specialist AS id_consultant,
    tl.id_user AS id_user_team_lead,
    tl.id_specialist AS id_team_lead,
    pre.id_user AS id_user_pre_specialist,
    pre.id_specialist AS id_pre_specialist,
    post.id_user AS id_user_post_specialist,
    post.id_specialist AS id_post_specialist,
    credit.id_user AS id_user_credit_specialist,
    credit.id_specialist AS id_credit_specialist,
    ms.id_user AS id_user_start_financing_specialist,
    ms.id_specialist AS id_start_financing_specialist,
    mfup.id_user AS id_user_follow_up_financing_specialist,
    mfup.id_specialist AS id_follow_up_financing_specialist,
    me.id_user AS id_user_end_financing_specialist,
    me.id_specialist AS id_end_financing_specialist,
    crn.id_user AS id_user_notes_registry_specialist,
    crn.id_specialist AS id_notes_registry_specialist,
    cri.id_user AS id_user_real_estate_register_specialist,
    cri.id_specialist AS id_real_estate_register_specialist,
    lr.id_user AS id_user_legal_risk_analyst,
    lr.id_specialist AS id_legal_risk_analyst,
    dm.specialist_name AS consultant_name,
    dm.email AS consultant_email,
    tl.specialist_name AS team_lead_name,
    tl.email AS team_lead_email,
    pre.specialist_name AS pre_specialist_name,
    pre.email AS pre_specialist_email,
    post.specialist_name AS post_specialist_name,
    post.email AS post_specialist_email,
    credit.specialist_name AS credit_specialist_name,
    credit.email AS credit_specialist_email,
    ms.specialist_name AS start_financing_specialist_name,
    ms.email AS start_financing_specialist_email,
    mfup.specialist_name AS follow_up_financing_specialist_name,
    mfup.email AS follow_up_financing_specialist_email,
    me.specialist_name AS end_financing_specialist_name,
    me.email AS end_financing_specialist_email,
    crn.specialist_name AS notes_registry_specialist_name,
    crn.email AS notes_registry_specialist_email,
    cri.specialist_name AS real_estate_register_specialist_name,
    cri.email AS real_estate_register_specialist_email,
    lr.specialist_name AS legal_risk_analyst_name,
    lr.email AS legal_risk_analyst_email
FROM
    offers_specialists AS o
LEFT JOIN 
    last_specialist AS dm 
    ON dm.id_sales_flow = o.id_sales_flow
    AND dm.kind = 'DEAL_MAKER'
    AND dm.row = 1
LEFT JOIN 
    last_specialist AS tl 
    ON tl.id_sales_flow = o.id_sales_flow
    AND tl.kind = 'TEAM_LEAD'
    AND tl.row = 1
LEFT JOIN 
    last_specialist AS pre 
    ON pre.id_sales_flow = o.id_sales_flow
    AND pre.kind = 'PRE'
    AND pre.row = 1
LEFT JOIN 
    last_specialist AS post 
    ON post.id_sales_flow = o.id_sales_flow
    AND post.kind = 'POST'
    AND post.row = 1
LEFT JOIN 
    last_specialist AS credit 
    ON credit.id_sales_flow = o.id_sales_flow
    AND credit.kind = 'CREDIT'
    AND credit.row = 1
LEFT JOIN 
    last_specialist AS ms 
    ON ms.id_sales_flow = o.id_sales_flow
    AND ms.kind = 'MORTGAGE_START'
    AND ms.row = 1
LEFT JOIN 
    last_specialist AS mfup
    ON mfup.id_sales_flow = o.id_sales_flow
    AND mfup.kind = 'MORTGAGE_FUP'
    AND mfup.row = 1
LEFT JOIN 
    last_specialist AS me
    ON me.id_sales_flow = o.id_sales_flow
    AND me.kind = 'MORTGAGE_END'
    AND me.row = 1
LEFT JOIN 
    last_specialist AS crn
    ON crn.id_sales_flow = o.id_sales_flow
    AND crn.kind = 'CRN'
    AND crn.row = 1
LEFT JOIN 
    last_specialist AS cri
    ON cri.id_sales_flow = o.id_sales_flow
    AND cri.kind = 'CRI'
    AND cri.row = 1
LEFT JOIN 
    last_specialist AS lr
    ON lr.id_sales_flow = o.id_sales_flow
    AND lr.kind = 'LEGAL_RISK'
    AND lr.row = 1