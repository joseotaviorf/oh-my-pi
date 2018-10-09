-- CREATE GOOGLE ADS KEYWORD DIMENSION TABLE
WITH latest as (
    SELECT
     keywords.keywordid as sk_keyword,
     keywords.keywordid as keyword_id,
     keywords.keyword as keyword_name,
     RANK() OVER (PARTITION BY keywords.day, keywordid
                    ORDER BY keywords._sdc_report_datetime DESC)
    FROM stitch.googleads_keywords_performance_report keywords
    WHERE keywords.dt = '{dt}'
    GROUP BY 1, 2, 3, keywords.day, keywords._sdc_report_datetime
    ORDER BY day ASC
)
SELECT * FROM latest
WHERE rank = 1