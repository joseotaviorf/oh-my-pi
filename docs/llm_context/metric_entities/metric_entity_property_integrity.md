# **<span style="font-size:12px">Property Integrity</span>**

## **Ownership**

***_Data Owner:_***- [carolina.espinoza@quintoandar.com.br](mailto:carolina.espinoza@quintoandar.com.br)- [felipe.abreu@quintoandar.com.br](mailto:felipe.abreu@quintoandar.com.br)  
***_Data Steward:_***- [victor.prado@quintoandar.com.br](mailto:victor.prado@quintoandar.com.br)

## **Overview**

***_Property Integrity_*** is a family of offboarding-quality metrics for the For Rent product thatmeasure how a termination resolves repairs and agreements — how often it closes *_withoutfriction_* (no mediation), ***_without repairs_***, and, when repairs do exist, how the partiessettle them (mutual agreement vs. compulsory / band-aid). It covers four indicators:***_% Offb. W/o Mediation_***, ***_% Without Repairs_***, ***_% Both Agree_***, and***_% Compulsory/Band-Aid 2_***.  
All four are computed from the pre-joined offboarding table `dw_offboarding.obt_offboarding`,which already carries every flag these metrics need at one row per termination.  
*_Exists exclusively for For Rent offboarding — these metrics have no equivalent for FS orother products._*

## **Related Business Entities**

- Termination

- Inspection

- Repairs

## **MBR**

Post Contract

## MBR

- Post Contract

## **Glossary and Synonyms**

- ***_Property Integrity_***, ***_integridade do imóvel_***, ***_qualidade do offboarding_*** → this family of four metrics- ***_% Offb. W/o Mediation_***, ***_% Offboarding sem mediação_***, ***_% sem mediação_*** → % Offb. W/o Mediation- ***_% Without Repairs_***, ***_% sem reparos_***, ***_% termos sem reparo_*** → % Without Repairs- ***_% Both Agree_***, ***_% ambos concordam_***, ***_% acordo mútuo_***, ***_both agree_*** → % Both Agree- ***_% Compulsory/Band-Aid 2_***, ***_% compulsório/band-aid_***, ***_compulsory or bandaid resolution_*** → % Compulsory/Band-Aid 2- ***_band-aid_***, ***_bandaid_***, ***_desconto automático_***, ***_automatic discount_*** → the automatic-discount agreement flag (`has_discount_agreement`)

## **Scope**

***_Included_***: For Rent offboarding terminations that have already ***_finished_*** (non-null`ts_termination_finished`), ***_excluding evictions_***. The reference axis for all four metrics isthe ***_termination-finished date_*** — the calendar date of `ts_termination_finished`(`CAST(ts_termination_finished AS DATE)`, UTC), matching the operational monthly reporting.  
***_Excluded_***: evictions (`is_eviction = TRUE`), canceled terminations (already removed upstreamby the OBT), and terminations that have not yet reached closure (NULL `ts_termination_finished`).

## **Calculation**

Compute directly from `dw_offboarding.obt_offboarding`, reading the pre-materialized flags andapplying the exact `= true` / `= false` comparisons below (a NULL flag counts as neither `true`nor `false`).  
The four indicators, all over the same finished-non-eviction base:  
```% Offb. W/o Mediation = count_if(has_mediation_ticket = false) / count(*)  
% Without Repairs = count_if(has_repairs = false) / count(*)  
% Both Agree = count_if(has_repairs = true AND has_agreement = true AND (has_early_agreement = true OR has_late_agreement = true)) / count_if(has_repairs = true)  
% Compulsory/Band-Aid 2 = ( count_if(has_repairs = true AND has_agreement = true AND has_discount_agreement = true) + count_if(has_repairs = true AND has_compulsory_agreement = true) ) / count_if(has_repairs = true)```  
The denominators differ by metric: ***_% Offb. W/o Mediation_*** and ***_% Without Repairs_*** divide bythe whole finished-non-eviction base (`count(*)`); ***_% Both Agree_*** and ***_% Compulsory/Band-Aid 2_***divide by the ***_with-repairs_*** subset (`count_if(has_repairs = true)`).

### **Canonical Filter**

Apply on `dw_offboarding.obt_offboarding`:  
```sqlis_eviction = falseAND ts_termination_finished IS NOT NULL -- finished terminations only (see Warning)```  
***_Warning_***: dropping `is_eviction = false` lets evictions into the base and inflates everyratio, since eviction terminations behave very differently on repairs and mediation. Restrictingto finished terminations (non-null `ts_termination_finished`) is required for *_% Offb. W/oMediation_*: `has_mediation_ticket` is only populated once a termination reaches `DONE`, sostill-open terminations would be counted as "without mediation" and understate the mediationrate. Using `ts_termination_finished` as the axis naturally enforces this scope.

### **Nuances**

Every concept these metrics need is already a column in `dw_offboarding.obt_offboarding` — readit directly. Concept → column:  
| Concept | `obt_offboarding` column || :---- | :---- || Mediation ticket present on the termination | `has_mediation_ticket` || Termination had tenant repairs | `has_repairs` || Any agreement (early, late/budget, or discount) | `has_agreement` || Early both-agree agreement | `has_early_agreement` || Late agreement via budget approval | `has_late_agreement` || Band-aid / automatic-discount agreement | `has_discount_agreement` || Compulsory owner-approval settlement | `has_compulsory_agreement` || Eviction termination | `is_eviction` || Termination-finished date (axis) | `CAST(ts_termination_finished AS DATE)` (UTC calendar date) |  
***_Band-aid flag_***: the band-aid (automatic discount) is `has_discount_agreement`("agreement reached through the application of automatic discounts"). This is the canonicalband-aid flag documented in `business_entities/termination.md`. Do ***_not_*** use`model_discount_type` (also a column in `obt_offboarding`) to identify band-aid — it onlydistinguishes the discount application mode (`AUTOMATIC_BANDAID` vs `OFFERED_DISCOUNT`), notwhether a band-aid agreement happened.  
***_Grain_***: `obt_offboarding` is 1 row per termination (most recent exit inspection, canceledterminations excluded), so `count(*)` / `count_if(...)` need no dedup.  
**## Dos and Don'ts**  
***_Do:_***  
- Read the flags directly from `dw_offboarding.obt_offboarding`.- Always apply the full canonical filter (`is_eviction = false` AND finished terminations only).- Use the ***_calendar date_*** of `ts_termination_finished` (`CAST(ts_termination_finished AS DATE)`, UTC) as the reference axis, so monthly buckets match the operational reporting.- Keep the exact `= true` / `= false` comparisons — a NULL flag is neither `true` nor `false`.- Divide ***_% Both Agree_*** and ***_% Compulsory/Band-Aid 2_*** by `count_if(has_repairs = true)`, not by `count(*)`.  
***_Don't:_***  
- Don't map the band-aid flag to `model_discount_type`; use `has_discount_agreement`.- Don't include evictions, canceled, or still-open terminations in any denominator.- Don't `COALESCE` the agreement flags to `FALSE` before comparing with `= true` — it changes nothing (a NULL is already not `true`) and only obscures the intent.

## **Golden Queries**

All four metrics share the same base, axis and filter, so a single scan of`dw_offboarding.obt_offboarding` produces them side by side. Trino dialect.  
**### Query 1 — Property Integrity (all four metrics by month)**  
The month axis and the range predicates below bucket by the ***_calendar date_*** of`ts_termination_finished` (`CAST(... AS DATE)`, i.e. the UTC date), matching the operationalmonthly reporting convention — a termination finished in the early UTC hours of the 1st counts inthat new month, not the previous one. The range predicates are for partition pruning / performance(adjust or drop the window as needed); only `is_eviction = false` and the finished-only scope arerequired by the calculation.  
```sqlSELECT DATE_TRUNC('month', CAST(obt.ts_termination_finished AS DATE)) AS ref_month, COUNT(*) AS total_terminations, CAST(COUNT_IF(obt.has_mediation_ticket = false) AS DOUBLE) / COUNT(*) AS pct_offb_wo_mediation, CAST(COUNT_IF(obt.has_repairs = false) AS DOUBLE) / COUNT(*) AS pct_without_repairs, CAST( COUNT_IF( obt.has_repairs = true AND obt.has_agreement = true AND (obt.has_early_agreement = true OR obt.has_late_agreement = true) ) AS DOUBLE ) / CAST(NULLIF(COUNT_IF(obt.has_repairs = true), 0) AS DOUBLE) AS pct_both_agree, ( CAST( COUNT_IF( obt.has_repairs = true AND obt.has_agreement = true AND obt.has_discount_agreement = true ) AS DOUBLE ) + CAST( COUNT_IF( obt.has_repairs = true AND obt.has_compulsory_agreement = true ) AS DOUBLE ) ) / CAST(NULLIF(COUNT_IF(obt.has_repairs = true), 0) AS DOUBLE) AS pct_compulsory_bandaid2FROM dw_offboarding.obt_offboarding AS obtWHERE obt.is_eviction = false AND obt.ts_termination_finished IS NOT NULL AND CAST(obt.ts_termination_finished AS DATE) >= DATE_ADD('month', -24, CURRENT_DATE) AND CAST(obt.ts_termination_finished AS DATE) < CURRENT_DATEGROUP BY 1ORDER BY 1```  
To isolate a single indicator, keep only its numerator/denominator pair and the same`FROM` / `WHERE`.

## **Superset Golden Assets**

Superset charts where these indicators are published (BI reference only — not used in thecalculation):  
- ***_Property Integrity — Superset chart_*** — URN: `urn:li:chart:(superset,chart.56400)` ([link]([https://datahub.apps.data-prd.habitat.zone/chart/urn:li:chart:(superset,chart.56400)/Documentation?is\_lineage\_mode=false](https://datahub.apps.data-prd.habitat.zone/chart/urn:li:chart:(superset,chart.56400)/Documentation?is%5C_lineage%5C_mode=false)))- ***_Property Integrity — Superset chart_*** — URN: `urn:li:chart:(superset,chart.57915)` ([link]([https://datahub.apps.data-prd.habitat.zone/chart/urn:li:chart:(superset,chart.57915)/Documentation?is\_lineage\_mode=false](https://datahub.apps.data-prd.habitat.zone/chart/urn:li:chart:(superset,chart.57915)/Documentation?is%5C_lineage%5C_mode=false)))

## DataHub catalog

- **Data Product:** `urn:li:dataProduct:metric-entity-property-integrity`

