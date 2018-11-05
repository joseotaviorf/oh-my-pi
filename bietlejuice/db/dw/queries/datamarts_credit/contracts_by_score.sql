-- count of contracts signed by 5A score buckets

select
    case
        when score_5A < 100
            then '0-99'
        when score_5A >= 100 and score_5A < 200
            then '100-199'
        when score_5A >= 200 and score_5A < 300
            then '200-299'
        when score_5A >= 300 and score_5A < 400
            then '300-399'
        when score_5A >= 400 and score_5A < 500
            then '400-499'
        when score_5A >= 500 and score_5A < 600
            then '500-599'
        when score_5A >= 600 and score_5A < 700
            then '600-699'
        when score_5A >= 700 and score_5A < 800
            then '700-799'
        when score_5A >= 800 and score_5A < 900
            then '800-899'
        when score_5A >= 900 and score_5A < 1000
            then '900-999'
        when score_5A >= 1000
            then '1000-~'
        else 'null'
    end as score_5A,
    count(distinct dc.sk_contract) as contracts
from dim_contract dc
join fact_listing_rent_flows fd
    on dc.sk_contract = fd.sk_contract
join datalake_raw.sortinghat_proposal sp
    on sp.id = fd.sk_proposal
where dc.status in ('Ativo', 'Finalizado')
group by 1
order by 1
;
