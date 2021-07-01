-- enrichment stage
with
    boleto as (
        select
            b.id,
            b.company_use,
            'charge' as type,
            b.related_document_type,
            b.id_related_document,
            b.occurrence_code,
            b.payer_document,
            null as payee_document,
            null as payee_name,
            null as has_payee_savings_acc,
            b.ts_created,
            b.ts_issued,
            b.ts_updated,
            b.dt_due,
            b.dt_fine_due,
            b.dt_paid,
            b.due_amount,
            b.paid_amount,
            b.fine_amount,
            b.one_day_interest,
            b.interest
        from datalake_vans_clean.boleto b
    ),
    payment as (
        select
            p.id,
            p.company_use,
            'transfer' as type,
            p.related_document_type,
            p.id_related_document,
            p.occurrence_code,
            null as payer_document,
            p.payee_document,
            null as payee_name,
            p.has_payee_savings_acc,
            p.ts_created,
            p.ts_issued,
            p.ts_updated,
            p.dt_dued as dt_due,
            null as dt_fine_due,
            p.dt_paid,
            p.due_amount,
            p.paid_amount,
            null as fine_amount,
            null as one_day_interest,
            null as interest
        from datalake_vans_clean.payment p
    ),
    payment_boleto as (
        select
            pb.id,
            pb.company_use,
            'account payable' as type,
            pb.related_document_type,
            pb.id_related_document,
            pb.occurrence_code,
            null as payer_document,
            null as payee_document,
            pb.payee_name,
            null as has_payee_savings_acc,
            pb.ts_created,
            null as ts_issued,
            pb.ts_updated,
            null as dt_due,
            null as dt_fine_due,
            pb.dt_paid,
            null as due_amount,
            pb.paid_amount,
            null as fine_amount,
            null as one_day_interest,
            null as interest
        from datalake_vans_clean.payment_boleto pb
    ),
    consolidation_table as (
        select * from boleto
        union all
        select * from payment
        union all
        select * from payment_boleto
    ),
    delete_documents_repeated as (
        select
            max(cons.id) as max_id,
            nullif(regexp_extract(cons.company_use, '(\\d+\\D\\d{{4}})\d*', 1), '') as id_company_use,
            company_use,
            cons.ts_created,
            cons.ts_issued,
            cons.dt_paid
        from consolidation_table cons
        group by 2,3,4,5,6
    ),
    vans_payments as (
        select 
            cons.*, 
            nullif(cons.company_use, '') as company_use_code,
            del.id_company_use
        from consolidation_table cons
        join delete_documents_repeated del
            on cons.id=del.max_id
            -- <=> return TRUE when both key values are null 
            and del.company_use<=>cons.company_use
            and del.ts_created<=>cons.ts_created
            and del.ts_issued<=>cons.ts_issued
            and del.dt_paid<=>cons.dt_paid
    ),
    -- fact model - it's generating sk_banking_file_payment, the pk of the fact table
    index_version as (
        select
            string(id) as primary_key,
            id_company_use,
            company_use_code,
            type,
            case 
                when id_company_use is not null then 'DEFAULT'
                when company_use_code is null then 'INVALID'
                when (id_company_use is null and company_use_code is not null) then 'CUSTOM' 
            end as format,
            string(row_number() over (partition by id_company_use order by ts_issued, ts_created, dt_paid)) as version_index
        from vans_payments
    ),
    generate_key as (
        select
            primary_key,
            type as tp,
            id_company_use,
            company_use_code,
            case
                when format = 'DEFAULT' and type = 'charge' then concat(id_company_use, '1', lpad(version_index, 3, '0'))
                when format = 'DEFAULT' and type = 'transfer' then concat(id_company_use, '2', lpad(version_index, 3, '0'))
                when format = 'DEFAULT' and type = 'account payable' then concat(id_company_use, '3', lpad(version_index, 3, '0'))
                when format = 'INVALID' then concat(format, primary_key)
                when format = 'CUSTOM' then concat(company_use_code, primary_key)
            end as sk_banking_file_payment
        from index_version
   ),
   -- fact model - business rules
   business_rules as (
        select
            string(id) as primary_key,
            type as tp,
            id_company_use,
            case 
                when related_document_type = 'invoice' then coalesce(cast(id_related_document as bigint), -1)
                else -1
            end as sk_invoice,
            case when related_document_type = 'payment-request' then coalesce(cast(id_related_document as bigint), -1)
                else -1
            end as sk_payment_request,
            coalesce(cast(nullif(regexp_extract(company_use_code, '(\\d+)\\D\\d{{4}}\\d*'),'') as bigint), -1) as sk_contract,
            coalesce(company_use_code, -1) as sk_company_use,
            coalesce(occurrence_code, -1) as sk_occurrence_code,
            coalesce(payer_document, -1) as sk_charge_payer_user,
            coalesce(payee_document, -1) as sk_transfer_payee_user,
            coalesce(payee_name, -1) as sk_account_payable_corporate_user,
            coalesce(has_payee_savings_acc, false) as is_payee_savings_acc,
            coalesce(cast(date_format(ts_created, 'yyyyMMdd') as int), -1) as sk_created_date,
            coalesce(cast(date_format(ts_issued, 'yyyyMMdd') as int), -1) as sk_issued_date,
            coalesce(cast(date_format(ts_updated, 'yyyyMMdd') as int), -1) as sk_updated_date,
            coalesce(cast(date_format(dt_due, 'yyyyMMdd') as int), -1) as sk_due_date,
            coalesce(cast(date_format(dt_fine_due, 'yyyyMMdd') as int), -1) as sk_fine_due_date,
            coalesce(cast(date_format(dt_paid, 'yyyyMMdd') as int), -1) as sk_paid_date,
            case 
                when type = 'charge' then due_amount
                when type = 'transfer' then (-1)*due_amount
                when type = 'account payable' then due_amount
            end as brl_due_amount,
            case
                when type = 'charge' then paid_amount
                when type = 'transfer' then (-1)*paid_amount
                when type = 'account payable' then (-1)*paid_amount
            end as brl_paid_amount,
            fine_amount as brl_fine_amount,
            one_day_interest as brl_one_day_interest,
            interest as brl_charged_interest
        from vans_payments
    )
    select
        key.sk_banking_file_payment,
        buz.sk_invoice,
        buz.sk_payment_request,
        buz.sk_contract,
        buz.sk_company_use,
        buz.sk_occurrence_code,
        buz.sk_charge_payer_user,
        buz.sk_transfer_payee_user,
        buz.sk_account_payable_corporate_user,
        buz.is_payee_savings_acc,
        buz.sk_created_date,
        buz.sk_issued_date,
        buz.sk_updated_date,
        buz.sk_due_date,
        buz.sk_fine_due_date,
        buz.sk_paid_date,
        buz.brl_due_amount,
        buz.brl_paid_amount,
        buz.brl_fine_amount,
        buz.brl_one_day_interest,
        buz.brl_charged_interest,
        now() as ts_load
    from generate_key key
    join business_rules buz
    on key.primary_key=buz.primary_key
    and key.tp=buz.tp
    and key.id_company_use<=>buz.id_company_use