# Starting a New API Ingestion: Prerequisites

**Audience:** Pipeline authors about to build a new `api_ingestion` DAG.

All new `api_ingestion` DAGs run on **EMR** (see [user_guide.md](user_guide.md) for the runtime
itself). Before writing a single line of DAG code, SQL, or target schemas, three approval-gated
prerequisites need to be requested. None of them requires the DAG, the SQL, or even the target
schema to exist yet — they only need a handful of static facts you already know. Request all
three as early as possible: every one of them goes through an external team's approval queue,
and that queue time is almost always the actual bottleneck, not the implementation.

## The Three Prerequisites

| # | What | Why It Is Gated | Static Input Needed | Approval Owner |
| --- | --- | --- | --- | --- |
| 1 | **Data Contract** (raw + clean) | Access to a new schema is disabled by default | Domain/subdomain + schema names | Data Governance, authX |
| 2 | **Cybersec: Application Internet Access** | All new outbound access from EMR is disabled by default | Destination API URL (+ protocol/port/env) | SecurityHub |
| 3 | **Vault → EMR Secrets Manager Mirror** | EMR reads credentials strictly from AWS Secrets Manager | Target Vault path | Data Platform |

## Recommended Order

1. **Data Contract — start this first.** It has the longest and least predictable lead time (up
   to 3 PRs across 2 approving teams), so don't let it be an afterthought. Its only inputs are
   the domain/subdomain and the raw + clean schema names.
2. **Cybersec ticket and Vault mirror PR — fire the same day, in either order.** Both need only
   one static fact (the API URL, and the Vault path, respectively), go through a single approval
   chain, and have no soft blockers. There's no benefit to sequencing them relative to each other
   or to waiting on the Data Contract.

## 1. Data Contract

Access to a new schema is disabled by default; a Data Contract is what turns it on. The contract
**does not require the schema to exist** in Databricks/Glue/Trino yet, so it can be created
before (or in parallel with) building the ingestion DAG.

Create one for **both `raw` and `clean`**.

> In most cases the schema lands in an existing, already-owned domain, so the domain/subdomain
> input is just as static and self-known as the other two prerequisites. The one exception is a
> **new** domain/subdomain, where that ownership decision needs to be resolved with your
> team/Leadership before the contract can be requested, adding delay ahead of the step that
> already has the longest tail.

**How to provision:**
1. Clone/open the [`data-contracts`](https://github.com/quintoandar/data-contracts) repo — needs
   to be in the same workspace as `bi-etl-ejuice` and
   [`infrastructure-iam`](https://github.com/quintoandar/infrastructure-iam).
2. Run the `manage-data-contract` command (`.cursor/commands/manage-data-contract.md`, backed by
   the `provision-data-contract` skill). It walks through domain/subdomain, schema/tables,
   servers, and Leadership Team interactively, and produces:
   - Data Contract YAML in both `prod` (active) and `forno` (draft).
   - IdentityNow access profile + role (prod only, when Trino is involved).
   - Schema registration in [`authX`](https://github.com/quintoandar/authX) (prod only, when
     Trino is involved).
3. Background: [User Guide - Data Producer](https://docs.google.com/document/d/1v7AihVIjI9qVV3vu5tK5xx6MGf8szFBUBkK4R6j_NWk/edit?usp=sharing).

This can open up to **3 PRs** ([`data-contracts`](https://github.com/quintoandar/data-contracts),
[`infrastructure-iam`](https://github.com/quintoandar/infrastructure-iam),
[`authX`](https://github.com/quintoandar/authX)) — this is the main reason it has the longest
tail of the three.

**Remember to request/verify your own access to the contract you just created** — creating it
does not automatically grant you access to query it. Request access via IDN
([quin.to/access](http://quin.to/access)): **New Access > Access items > Functions > Data
Contract - (...)**. You can validate the access actually landed by querying another table that
already lives inside the same Data Contract.

**Approvals:**
- Data Governance (responsible team)
- authX (approvers on the `infrastructure-iam` PR, via Google Chat)

## 2. Cybersec: Application Internet Access

All new outbound network access from EMR is disabled by default; opening it requires a
SecurityHub ticket. The ticket format is straightforward and the inputs are static — this is
just gated on someone else's approval + implementation queue, which can take some time.

Portal: [Application Internet Access](https://quintoandar.atlassian.net/servicedesk/customer/portal/4203/create/10185)
(Help Center → SecurityHub → Application Internet Access)

**Ticket fields:**
1. Summary
2. What do you need? (Change / Create / Delete)
3. What is your team
4. Project name
5. Details (why you need this; link an RFC if you have one)
6. Request type
7. Environment (Prod / Forno / Staging / All)
8. Source (application name, AWS account, or IP address/type)
9. Destination (the API's endpoint or IP)
10. Protocol (e.g. HTTPS)
11. Port (e.g. 443)
12. Approvers (responsible(s) for the project)

**Approval:** SecurityHub

## 3. Vault → EMR Secrets Manager mirror

EMR resolves credentials **by key name in AWS Secrets Manager** (`us-east-1`, account
`206390561754`) — never from Vault directly. Partners write the secret in prod Vault; Terraform
mirrors it into Secrets Manager. **Never create the secret by hand** in the AWS or Databricks UI.

**Vault path** (write with QLI, no `kv/` prefix): `apps/databricks/prod/secrets/<SECRET_NAME>`
— the Terraform `vault_generic_secret` path is `kv/` + that same path. Use the EMR lookup name
as `<SECRET_NAME>`, unless a provider already owns a different leaf (then keep that leaf and set
the AWS Secrets Manager `name` to the EMR key). Host: `https://vault.sre.quintoandar.com.br`.

**How to add a mirror:**
1. Put the secret in Vault at the path above. Never commit values to git, PRs, or chat.
2. Add a stack under
   [`infrastructure/cloud/apps/databricks/prod/secrets/`](https://github.com/quintoandar/infrastructure/tree/master/cloud/apps/databricks/prod/secrets)
   (clone a nearby EMR-only stack) and open a PR against
   [`infrastructure`](https://github.com/quintoandar/infrastructure). Targeted Atlantis:
   `atlantis plan -d cloud/apps/databricks/prod/secrets/<stack>/`.
3. **Do not `atlantis apply` until Vault is populated** — an empty path 404s on plan, which is
   expected; only the apply step needs the secret to be there, so the PR can be opened and
   reviewed before the credential exists. Re-plan if more than ~15 minutes pass between plan and
   apply (the Vault AWS login signature can expire).
4. Rotation: update Vault, then re-apply the same stack — don't edit Secrets Manager directly.

**Approval:** Data Platform.

---

Once these three are in flight, proceed to building the DAG — see [user_guide.md](user_guide.md)
for declaration parameters and [contributing.md](contributing.md) for the implementation map.
