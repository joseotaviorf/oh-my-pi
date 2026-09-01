# Starting a New API Ingestion: Prerequisites

**Audience:** Pipeline authors about to build a new `api_ingestion` DAG.

All new `api_ingestion` DAGs run on **EMR** (see [user_guide.md](user_guide.md) for the runtime
itself). Before you're done, three approval-gated prerequisites need to be requested. All three
can — and should — be **started** right away with static facts you already know, but the Data
Contract has a catch: it can only be **implemented/activated** once the target raw and clean
schemas already exist in Databricks/Glue/Trino — request/build both together, not one at a time.
Start the paperwork immediately, just don't merge/activate until both are real.

## The Three Prerequisites

| # | What | Why It Is Gated | Static Input Needed | Approval Owner |
| --- | --- | --- | --- | --- |
| 1 | **Data Contract** (raw + clean) | Access to a new schema is disabled by default | Domain/subdomain + schema names to start; **both the raw and clean schemas must exist before it can be activated** | Data Governance, authX |
| 2 | **Cybersec: Application Internet Access** | All new outbound access from EMR is disabled by default | Destination API URL (+ protocol/port/env) | SecurityHub |
| 3 | **Vault → EMR Secrets Manager Mirror** | EMR reads credentials strictly from AWS Secrets Manager | Target Vault path | Data Platform |

## Recommended Order

1. **Start all three processes right away, in parallel.** Open the Data Contract PRs (using just
   the domain/subdomain and the raw + clean schema names), file the Cybersec ticket, and open the
   Vault mirror PR. None of them blocks another at this stage — **do not merge/apply any of the
   three yet.**
2. **Once Cybersec access and the Vault credential mirror are approved/in place, merge the PR
   that adds the new DAG and run it.** This is what actually materializes the raw and clean
   schemas — see [user_guide.md](user_guide.md) and [contributing.md](contributing.md). Include
   the raw tables you actually want, plus **at least one clean table** (a plain `SELECT *` off
   raw is enough at this stage) so the clean schema is created too — this also makes the raw data
   queryable/explorable sooner, ahead of building out the real clean-layer transformations.
3. **Last, merge the Data Contract PRs.** Provisioning applies **incrementally**: if the target
   raw and clean schemas aren't there yet when the contract is applied, it simply doesn't attach,
   and it does **not** retry later once they show up — so this step has to come after step 2, not
   in parallel with it. Follow the specifics in the `provision-data-contract` skill (see "How to
   provision" below), including requesting/verifying your own access to the contract afterward.

## 1. Data Contract

Access to a new schema is disabled by default; a Data Contract is what turns it on. You can (and
should) start the contract PRs early using just the domain/subdomain and schema names, but the
contract **requires the target raw and clean schemas to already exist together** in
Databricks/Glue/Trino to actually take effect — provisioning is incremental and one-shot: if
either schema is missing when the contract is applied/activated, it does not attach, and it will
**not** automatically pick them up later. Merge/activate the contract only after both schemas
exist, and re-apply if you activated it too early.

Create and activate one contract covering **both `raw` and `clean` together** — don't split
activation across the two.

> In most cases the schema lands in an existing, already-owned domain, so the domain/subdomain
> input is just as static and self-known as the other two prerequisites. The one exception is a
> **new** domain/subdomain, where that ownership decision needs to be resolved with your
> team/Leadership before the contract can be requested, adding delay on top of the step that
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

With all three processes started, merge the DAG PR and run it once Cybersec + the Vault mirror
are approved — see [user_guide.md](user_guide.md) for declaration parameters and
[contributing.md](contributing.md) for the implementation map. Include at least one clean table
(a `SELECT *` placeholder is fine to start) alongside the raw tables so both schemas are created
in the same run. Only merge the Data Contract PRs last, once both the raw and clean schemas
exist.
