# `base_app_org_access` — reverse export governance

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_s3.base_app_org_access` |
| **Business owner** | kevin.trindade@quintoandar.com.br |
| **Technical owner** | Enterprise Engineering |
| **Domain** | People |
| **One-line summary** | Daily row-level access matrix exported as a single CSV object to the Base44 office bucket for the Org Health app. |
| **Business purpose** | Migrated from Daily Pipeline notebook `dash_org_health` view `base_app_org_access` ([DBP-1310](https://quintoandar.atlassian.net/browse/DBP-1310)). Row-level access for the Org Health organization base — which viewer email (`email_acesso`) may see each employee row (`colaborador_id`) in the Base44 / S.A.R.A stack and the Org Health dashboard. |
| **Business consumer** | [S.A.R.A](https://app-sara.base44.app/) (Base44 Org Health app); [Org Health Looker Studio dashboard](https://lookerstudio.google.com/u/0/reporting/a4ca40f0-eeb0-4e4a-b9db-c26e8d73e817/page/p_nr3079wm0d). |
| **Operational source of truth** | `metric_people.employee_snapshots` (roster scope, hierarchy access lists, band filter); `datalake_gsheets_people_clean.org_health_user_roles` (sheet `16O12KfrMfxZUBbclxMfwzD6AD6mZY5KcRT1fo0TR6PQ`, tab `roles`). Replaces sandbox `base_completa_hierarquia` and notebook temp `user_roles`. |
| **Delivery channel** | S3 object **`s3://5a-base44-office/orghealth/base_app_org_health_access.csv`** (prod). Canned ACL `bucket-owner-full-control` on write. Forno redirects to `people_bucket` under `reverse_s3_test/orghealth/base_app_org_health_access.csv` (no partner ACL). |
| **Grain** | One row per (`colaborador_id`, `email_acesso`) after `UNION` of natural hierarchy access and matrix roles, then the golden-rule security filter. |
| **Contract notes** | CSV columns: `colaborador_id`, `email_acesso` only (no lake partition columns). Spark CSV writer (`header=true`, comma, UTF-8, empty nulls). Manager emails in the golden rule are compared with `LOWER(...)`; the allow/block lists remain **hardcoded** in SQL (aligned with business owner Kevin Trindade — not moved to the roles sheet in this migration). |

## Useful links

| Resource | URL |
| --- | --- |
| Org Health Looker Studio dashboard | [Dash Org Health](https://lookerstudio.google.com/u/0/reporting/a4ca40f0-eeb0-4e4a-b9db-c26e8d73e817/page/p_nr3079wm0d) |
| S.A.R.A (Base44 Org Health app) | [app-sara.base44.app](https://app-sara.base44.app/) |
| Roles sheet (matrix access) | Google Sheet `16O12KfrMfxZUBbclxMfwzD6AD6mZY5KcRT1fo0TR6PQ`, tab `roles` → `datalake_gsheets_people_clean.org_health_user_roles` |
| Legacy notebook | `/People/People_Analytics/Daily_Pipeline/dash_org_health` (disable access CSV write after prod cutover) |

## Scoped roster (who appears as a visible row)

Same scope as `base_app_org_health`: `is_current_for_employee = TRUE`, and either:

- **Active** employee (`status = active`), or
- **Terminated manager** still leading at least one active employee (keeps manager subtrees visible after termination).

Legacy notebook: active rows plus anyone in `gestores_de_colaboradores_ativos`.

## Stream 1 — Natural access (hierarchy list)

1. Explode `access_list` on each scoped employee. When `access_list_no_hrbp` is empty (`---`) or null, use `access_list`; otherwise use `access_list_no_hrbp` (HRBP stripped list).
2. Split on `-`, trim, lowercase viewer emails.
3. **Band gate:** only viewers in bands **10–16** (`emails_banda_10_a_16` in the legacy notebook) may receive natural hierarchy access.

## Stream 2 — Matrix access (roles sheet)

Rows from `org_health_user_roles` grant access by role name match on the **target** employee:

| `special_role` match | Effect (legacy intent) |
| --- | --- |
| `super_admin` | Company-wide: every scoped employee row × every super-admin email on the sheet |
| Target `name_l1` | Viewer sees employees under that L1 scope (legacy: `l1_gestor` match) |
| Target `name_l3` | Viewer sees employees under that L3 subtree (legacy: `l3_gestor` match) |

Implementation uses three equi-join legs (`l1_matrix_access`, `l3_matrix_access`, `super_admin_matrix_access`) combined with `UNION`.

## Golden rule (HRBP security filter)

After `UNION` of natural + matrix access, rows are **removed** when both hold:

- **Condition A — common HRBP viewer:** the viewer’s manager (`manager_work_email`) is Pedro, Larissa, Marília, or Mariana (legacy: `viewer.email_gestor`).
- **Condition B — protected target:** the target’s manager is Deborah or one of those four leads, **or** the viewer is the target themselves, **or** the viewer is the target’s direct manager.

Legacy label: *regra de ouro / corte de segurança para HRBPs comuns*. Keeps common HRBPs from seeing People leadership rows they should not access in the app.

## Rollout and prod validation

IAM for the partner bucket is the same grant as `base_app_org_health` ([infrastructure#42914](https://github.com/quintoandar/infrastructure/pull/42914)). The `orghealth/*` prefix must cover Spark staging under `orghealth/_staging/load_to_s3/*`.

**This export cannot be fully validated in Forno** (People DW / metric sources are not available there). After merge:

1. Confirm `gsheets_people` has materialized `org_health_user_roles` in prod.
2. Trigger a **manual prod run** of `base_app_org_access` on `bietlejuice.reverse_s3`.
3. Confirm `s3://5a-base44-office/orghealth/base_app_org_health_access.csv` is a single GET-able object.
4. Disable the access CSV write in notebook `/People/People_Analytics/Daily_Pipeline/dash_org_health` only after the object is confirmed.
