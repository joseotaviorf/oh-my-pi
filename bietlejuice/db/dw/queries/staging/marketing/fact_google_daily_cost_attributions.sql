WITH
    {keywords_cte},
    {ads_cte},
    {campaign_cte}
SELECT * FROM final_cte_keywords
union all
SELECT * FROM final_cte_ads
union all
SELECT * FROM final_cte_campaigns