# AAREDE-482 implementation plan

## Phase 0 Decision Log

- scope: metadata + wiki join-pattern doc only; no dim_listing SQL
- out_of_scope: facts, house SQL, 481 rebase, Forno
- success: dim_listing.yml semantics + lineage; wiki join recipe
- delivery: branch AAREDE-482/document-dim-listing-primary-market from origin/master; draft PR; static checks

## Steps

1. Update `dim_listing.yml` `is_primary_market` description (strict PRIMARY via house passthrough; join recipe).
2. Keep lineage `datalake_ebdb_listing.house.is_sale_primary_market`.
3. Add interim join section to `concepts/downstream-lineage-propagation.md`; append `log.md`.
4. Run metadata/lineage validators. Skip Forno (no SQL).
5. Commit, push, draft PR assigned to rompegustavo.

## Verify

```bash
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-metadata-files-content
CI_COMMIT_BRANCH=$(git branch --show-current) make validate-lineage-consistency
```
