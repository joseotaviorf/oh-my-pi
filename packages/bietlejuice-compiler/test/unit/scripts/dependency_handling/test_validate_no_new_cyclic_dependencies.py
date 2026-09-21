from scripts.dependency_handling import validate_no_new_cyclic_dependencies as mod

# The supply cycle that caused the 2026-07-30 obt_supply incident, trimmed to the DAGs and edges that
# matter for these tests.
SUPPLY_CYCLE = {
    "bietlejuice.enrich_supply_acquisition": [
        "bietlejuice.enrich_supply_leads:load-enrich-leads-sks:first-run-of-day"
    ],
    "bietlejuice.enrich_supply_leads": [
        "bietlejuice.enrich_supply_tracking:load-enrich-supply-events-tracking:first-run-of-day"
    ],
    "bietlejuice.enrich_supply_tracking": [
        "bietlejuice.enrich_supply_acquisition:load-enrich-acquisition-tracking:first-run-of-day"
    ],
}
ATTA_CYCLE = {
    "bietlejuice.dw_atta": [
        "bietlejuice.dw_sale_closing_flows:load-dw-sale-fact-closing-flows:first-run-of-day"
    ],
    "bietlejuice.dw_sale_closing_flows": [
        "bietlejuice.dw_atta:load-dw-atta-dim-proposal-atta:first-run-of-day"
    ],
}


def as_cycles(*cycles):
    return {frozenset(cycle): cycle for cycle in cycles}


class TestFindNewCycles:
    def test_reports_a_cycle_that_does_not_exist_in_the_base_commit(self):
        new_cycles = mod.find_new_cycles(
            as_cycles(SUPPLY_CYCLE, ATTA_CYCLE), as_cycles(ATTA_CYCLE)
        )

        assert new_cycles == as_cycles(SUPPLY_CYCLE)

    def test_ignores_pre_existing_cycles(self):
        assert (
            mod.find_new_cycles(
                as_cycles(SUPPLY_CYCLE, ATTA_CYCLE),
                as_cycles(SUPPLY_CYCLE, ATTA_CYCLE),
            )
            == {}
        )

    def test_ignores_an_unrelated_change_to_a_dag_already_inside_a_cycle(self):
        # Same DAGs taking part in the cycle, but one of them gained an edge. The cycle is still the
        # same cycle, so the change did not introduce it.
        cycle_with_extra_edge = {
            **SUPPLY_CYCLE,
            "bietlejuice.enrich_supply_acquisition": [
                "bietlejuice.enrich_supply_leads:load-enrich-lead-origin:first-run-of-day",
                "bietlejuice.enrich_supply_leads:load-enrich-leads-sks:first-run-of-day",
            ],
        }

        assert (
            mod.find_new_cycles(
                as_cycles(cycle_with_extra_edge), as_cycles(SUPPLY_CYCLE)
            )
            == {}
        )

    def test_reports_a_cycle_that_pulled_in_another_dag(self):
        grown_cycle = {
            **SUPPLY_CYCLE,
            "bietlejuice.enrich_supply_conversion": [
                "bietlejuice.enrich_supply_leads:load-enrich-leads-sks:first-run-of-day"
            ],
        }

        assert mod.find_new_cycles(
            as_cycles(grown_cycle), as_cycles(SUPPLY_CYCLE)
        ) == as_cycles(grown_cycle)

    def test_reports_nothing_when_there_are_no_cycles_at_all(self):
        assert mod.find_new_cycles({}, {}) == {}


class TestPrintReport:
    def test_lists_every_dag_and_edge_of_the_cycle(self, capsys):
        mod.print_report(
            as_cycles(SUPPLY_CYCLE),
            [
                "dags/growth/enrich_supply_leads/queries/enrich/isaias_session_attribution.sql"
            ],
            "origin/master",
        )

        output = capsys.readouterr().out
        for dag, dependencies in SUPPLY_CYCLE.items():
            assert dag in output
            for dependency in dependencies:
                assert dependency in output
        assert "3 ordering edges would be silently dropped" in output
        assert (
            "dags/growth/enrich_supply_leads/queries/enrich/isaias_session_attribution.sql"
            in output
        )
        assert "Find the backwards read" in output

    def test_reports_each_cycle_separately(self, capsys):
        mod.print_report(as_cycles(SUPPLY_CYCLE, ATTA_CYCLE), [], "origin/master")

        output = capsys.readouterr().out
        assert "creates 2 dependency cycles that do not exist" in output
        assert output.count("DAGs now depend on each other") == 2


class TestFindChangedFilesOfDags:
    def test_keeps_only_upserted_dag_files_of_the_given_dags(self, monkeypatch):
        monkeypatch.setattr(
            mod.GitService,
            "get_modified_files_from_diff",
            lambda _self, _from, _to: {
                "dags/growth/enrich_supply_leads/queries/enrich/isaias_session_attribution.sql": "A",
                "dags/growth/enrich_supply_leads/metadata/enrich/removed.yml": "D",
                "dags/growth/enrich_other_dag/queries/enrich/other.sql": "M",
                "packages/bietlejuice-compiler/scripts/whatever.py": "M",
            },
        )

        assert mod.find_changed_files_of_dags(
            frozenset({"bietlejuice.enrich_supply_leads"}), "origin/master", "HEAD"
        ) == [
            "dags/growth/enrich_supply_leads/queries/enrich/isaias_session_attribution.sql"
        ]

    def test_returns_nothing_when_the_diff_cannot_be_read(self, monkeypatch):
        def fail(_self, _from, _to):
            raise OSError("no git here")

        monkeypatch.setattr(mod.GitService, "get_modified_files_from_diff", fail)

        assert (
            mod.find_changed_files_of_dags(
                frozenset({"bietlejuice.enrich_supply_leads"}), "origin/master", "HEAD"
            )
            == []
        )


class TestMain:
    def _stub_lookups(self, monkeypatch, cycles, base_commit_cycles):
        monkeypatch.setattr(mod, "fetch_diff_base", lambda _from: None)
        monkeypatch.setattr(mod, "resolve_base_commit", lambda _from, _to: "abc1234")
        monkeypatch.setattr(mod, "find_cycles", lambda: cycles)
        monkeypatch.setattr(
            mod, "find_cycles_in_commit", lambda _commit: base_commit_cycles
        )
        monkeypatch.setattr(mod, "find_changed_files_of_dags", lambda *_args: [])

    def test_defaults_to_pr_target_branch(self, monkeypatch):
        monkeypatch.setenv("CI_PIPELINE_EVENT", "pull_request")
        monkeypatch.setenv("CI_COMMIT_BRANCH", "development")
        monkeypatch.delenv("CI_COMMIT_TARGET_BRANCH", raising=False)

        assert mod._parse_args([]).from_branch == "origin/development"

    def test_fails_when_a_new_cycle_was_introduced(self, monkeypatch, capsys):
        self._stub_lookups(monkeypatch, as_cycles(SUPPLY_CYCLE), {})

        assert mod.main([]) == 1
        assert "NEW CYCLIC DAG DEPENDENCY INTRODUCED" in capsys.readouterr().out

    def test_passes_when_the_only_cycles_are_pre_existing(self, monkeypatch, capsys):
        self._stub_lookups(
            monkeypatch, as_cycles(SUPPLY_CYCLE), as_cycles(SUPPLY_CYCLE)
        )

        assert mod.main([]) == 0
        assert "No new cyclic DAG dependencies" in capsys.readouterr().out

    def test_passes_when_the_base_commit_cannot_be_inspected(self, monkeypatch, capsys):
        # A cycle in the working tree must not fail the build when there is nothing to compare it
        # against: the validation is skipped instead of guessing.
        self._stub_lookups(monkeypatch, as_cycles(SUPPLY_CYCLE), None)

        assert mod.main([]) == 0
        assert "NEW CYCLIC DAG DEPENDENCY INTRODUCED" not in capsys.readouterr().out


class TestResolveBaseCommit:
    def test_returns_the_merge_base(self, monkeypatch):
        monkeypatch.setattr(
            mod,
            "_run",
            lambda *_args, **_kwargs: type("Result", (), {"stdout": "abc1234\n"}),
        )

        assert mod.resolve_base_commit("origin/master", "HEAD") == "abc1234"

    def test_falls_back_to_the_base_branch_when_there_is_no_merge_base(
        self, monkeypatch, capsys
    ):
        def fail(*_args, **_kwargs):
            raise mod.subprocess.CalledProcessError(1, "git merge-base")

        monkeypatch.setattr(mod, "_run", fail)

        assert mod.resolve_base_commit("origin/master", "HEAD") == "origin/master"
        assert "could not find the merge base" in capsys.readouterr().out
