SELECT
    COALESCE(LOWER(CONCAT(id_firestore, id_user)), -1) AS sk_sale_offer_user,
    COALESCE(id_firestore, -1) AS sk_offer,
    COALESCE(id_external, -1) AS sk_user_external,
    COALESCE(sou.id_user, -1) AS sk_user_sales_flow,
    COALESCE(sou_info.sk_user_info, -1) AS sk_user_info,
    COALESCE(id_inviter, -1) AS sk_inviter,
    COALESCE(id_house, -1) AS sk_house,
    COALESCE(id_house_docx_folder, -1) AS sk_house_docx_folder,
    COALESCE(id_user_docx_folder, -1) AS sk_user_docx_folder,
    COALESCE(CAST(REPLACE(SUBSTRING(ts_user_invited, 1, 10),'-','') AS BIGINT), -1) AS sk_date_user_invited,
    COALESCE(CAST(REPLACE(SUBSTRING(ts_user_invite_accepted, 1, 10),'-','') AS BIGINT), -1) AS sk_date_user_invite_accepted,
    ts_user_invited,
    ts_user_invite_accepted
FROM
    datalake_sale_offer_flows.sale_offer_users AS sou
LEFT JOIN
    datalake_sale_offer_flows.sale_offer_users_info AS sou_info
        ON sou.type = sou_info.user_type
        AND sou.is_ccv_buyer <=> sou_info.is_ccv_buyer
        AND sou.is_seller_ccv_signer <=> sou_info.is_seller_ccv_signer
        AND sou.buyer_signer_status <=> sou_info.buyer_signer_status
        AND sou.is_pj <=> sou_info.is_pj
        AND sou.is_original_user <=> sou_info.is_original_user
        AND sou.is_income_partner <=> sou_info.is_income_partner
        AND sou.has_joint_buyer <=> sou_info.has_joint_buyer
