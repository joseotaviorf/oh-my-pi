WITH possible_combinations AS (
    SELECT DISTINCT
        type AS user_type,
        CASE
            WHEN is_ccv_buyer IS TRUE THEN "CCV Buyer"
            WHEN is_ccv_buyer IS FALSE THEN "Not a CCV Buyer"
            ELSE "Unknown"
        END AS ccv_buyer_status,
        CASE
            WHEN is_seller_ccv_signer IS TRUE THEN "Signer"
            WHEN is_seller_ccv_signer IS FALSE THEN "Not Signer"
        END AS seller_ccv_signer_status,
        CASE
            WHEN buyer_signer_status = "SIGNER" THEN "Signer"
            WHEN buyer_signer_status = "NOT_SIGNER" THEN "Not Signer"
            ELSE "Unknown"
        END AS buyer_ccv_signer_status,
        CASE
            WHEN is_pj IS TRUE THEN "Pessoa Jurídica"
            WHEN is_pj IS FALSE THEN "Pessoa Física"
            WHEN is_pj IS NULL THEN "Unknown"
        END AS user_legal_type,
        CASE
            WHEN is_original_user IS TRUE THEN "Original user"
            ELSE "Not an original user"
        END AS original_user_status,
        CASE
            WHEN is_income_partner IS TRUE THEN "Income partner"
            WHEN is_income_partner IS FALSE THEN "Not an income partner"
            ELSE "Unknown"
        END AS income_partner_status,
        CASE
            WHEN has_joint_buyer IS TRUE THEN "Has a joint buyer"
            WHEN has_joint_buyer IS FALSE THEN "Has no joint buyer"
            ELSE "Unknown"
        END AS joint_buyer_status,
        is_ccv_buyer,
        is_seller_ccv_signer,
        buyer_signer_status,
        is_pj,
        is_original_user,
        is_income_partner,
        has_joint_buyer
    FROM
        datalake_sale_offer_flows.sale_offer_users
),
last_sk_values AS (
    SELECT
        COALESCE(MAX(sk_user_info), 0) AS sk_user_info
    FROM
        datalake_sale_offer_flows.sale_offer_users_info
)
SELECT
    COALESCE(sui.sk_user_info, l_sk.sk_user_info + MONOTONICALLY_INCREASING_ID() + 1) AS sk_user_info,
    pos.user_type,
    pos.ccv_buyer_status,
    pos.seller_ccv_signer_status,
    pos.buyer_ccv_signer_status,
    pos.user_legal_type,
    pos.original_user_status,
    pos.income_partner_status,
    pos.joint_buyer_status,
    pos.is_ccv_buyer,
    pos.is_seller_ccv_signer,
    pos.buyer_signer_status,
    pos.is_pj,
    pos.is_original_user,
    pos.is_income_partner,
    pos.has_joint_buyer
FROM
    possible_combinations AS pos,
    last_sk_values AS l_sk
LEFT JOIN
    datalake_sale_offer_flows.sale_offer_users_info AS sui
        USING (
          sk_user_info,
          user_type,
          ccv_buyer_status,
          seller_ccv_signer_status,
          buyer_ccv_signer_status,
          user_legal_type,
          original_user_status,
          income_partner_status,
          joint_buyer_status
        )
