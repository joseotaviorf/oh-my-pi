WITH
    gross_sales_tax_aux as (
       SELECT
        DATE_FORMAT(dt_reference, 'yyyyMM') AS accrual_year_month,
        SUM(debit_credit) AS gross_sales_tax
      FROM
        datalake_pas.ledger
      WHERE
        account_number in (
          '31201.01.01',
          '31201.01.02',
          '31201.01.03',
          '31201.01.04',
          '31201.01.05',
          '31201.01.06',
          '31201.01.08',
          '31201.01.09',
          '31201.01.12',
          '31201.01.13',
          '31201.01.14',
          '31201.01.15',
          '31201.01.18',
          '31201.01.19',
          '31201.01.20',
          '31201.01.21',
          '31201.01.22',
          '31202.01.01',
          '31202.01.02',
          '41102.02.20',
          '41102.02.21'
        )
        AND cost_center_code REGEXP '^R.*'
        AND DATE_FORMAT(dt_reference, 'yyyyMM') >= 202301
      GROUP BY 1
    ),
    tax_credit_aux as (
        SELECT
          DATE_FORMAT(dt_reference, 'yyyyMM') AS accrual_year_month,
          SUM(debit_credit) AS tax_credit
        FROM
          datalake_pas.ledger
        WHERE
          account_number IN (
            '41101.04.09',
            '41101.05.11',
            '41101.06.18',
            '41101.07.22',
            '41101.09.19',
            '41101.12.05',
            '41101.16.03',
            '41101.16.06',
            '41101.17.02',
            '41101.18.02',
            '41101.23.12',
            '41101.24.12',
            '51101.05.04',
            '51101.07.03',
            '51101.09.02'
          )
          AND cost_center_code REGEXP '^R.*'
          AND DATE_FORMAT(dt_reference, 'yyyyMM') >= 202301
        GROUP BY 1
    ),
    metrics_aux as (
      SELECT
        accrual_year_month,
        SUM(rental_management) AS rental_management,
        SUM(rental_brokerage) AS rental_brokerage,
        SUM(partner_share_management) AS partner_share_management,
        SUM(partner_share_brokerage) AS partner_share_brokerage,
        SUM(insurance_commission) insurance_commission,
        SUM(late_payments) AS late_payments,
        SUM(addons_guarantee) addons_guarantee,
        SUM(addons_service_fee) AS addons_service_fee,
        SUM(addons_lra) AS addons_lra,
        SUM(addons_reserve) AS addons_reserve,
        SUM(addons_mra) AS addons_mra,
        SUM(addons_bfi) AS addons_bfi,
        SUM(addons_ccp) AS addons_ccp,
        SUM(addons_new_business_revenue) addons_new_business_revenue,
        SUM(addons_revenue_total) addons_revenue,
        SUM(agents_commission) AS agents_commission,
        SUM(affiliates_commission) AS affiliates_commission,
        SUM(revenue_share_total) revenue_share_total,
        SUM(gross_revenue) gross_revenue,
        SUM(net_revenue_pre_taxes) net_revenue_pre_taxes
    FROM
        dw_rental_contribution_margin.fact_house_listing_revenues
    WHERE
        (country_code = 'BR' or country_code='Undefined')
        AND accrual_year_month >= '202301'
    GROUP BY
        1
    )

SELECT
        ma.accrual_year_month,
        ma.rental_management,
        ma.rental_brokerage,
        ma.partner_share_management,
        ma.partner_share_brokerage,
        ma.insurance_commission,
        ma.late_payments,
        ma.addons_guarantee,
        ma.addons_service_fee,
        ma.addons_lra,
        ma.addons_reserve,
        ma.addons_mra,
        ma.addons_bfi,
        ma.addons_ccp,
        ma.addons_new_business_revenue,
        ma.addons_revenue,
        ma.agents_commission,
        ma.affiliates_commission,
        ma.net_revenue_pre_taxes,
        ma.gross_revenue,
        ma.revenue_share_total,
        -1 * (gst.gross_sales_tax + tc.tax_credit) as sales_tax,
        ma.gross_revenue + ma.revenue_share_total - (gst.gross_sales_tax + tc.tax_credit) as net_revenue
    FROM
        metrics_aux AS ma
    LEFT JOIN
        gross_sales_tax_aux AS gst
          ON cast(ma.accrual_year_month as int)=gst.accrual_year_month
    LEFT JOIN
        tax_credit_aux AS tc
          ON cast(ma.accrual_year_month as int)=tc.accrual_year_month
    ORDER BY
      1
