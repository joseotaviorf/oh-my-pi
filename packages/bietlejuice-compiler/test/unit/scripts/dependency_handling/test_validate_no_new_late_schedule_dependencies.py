from scripts.dependency_handling import (
    validate_no_new_late_schedule_dependencies as mod,
)

CONSUMER = "bietlejuice.enrich_big_agent_incentives"
FAST_LANE = "bietlejuice.big_agent_fast_lane"
NAZARE = "bietlejuice.nazare"


def _dep(dag_id: str) -> str:
    return f"{dag_id}:load-task:first-run-of-day"


class TestFirstDailyMinutes:
    def test_noon_cron(self):
        assert mod.first_daily_minutes("0 12 * * *") == 12 * 60

    def test_hourly_cron_starts_at_midnight(self):
        assert mod.first_daily_minutes("0 * * * *") == 0

    def test_multi_hour_cron_uses_earliest_tick(self):
        assert mod.first_daily_minutes("0 9,18 * * *") == 9 * 60

    def test_monthly_cron_uses_clock_not_midnight(self):
        # 2024-01-01 is a Monday; this cron only fires on the 15th and 30th.
        assert mod.first_daily_minutes("0 13 15,30 * *") == 13 * 60

    def test_weekday_only_cron_that_skips_monday(self):
        assert mod.first_daily_minutes("0 18 * * 5") == 18 * 60

    def test_sunday_only_cron_that_skips_monday(self):
        assert mod.first_daily_minutes("0 22 * * 0") == 22 * 60


class TestFindLateScheduleFindings:
    def _dataset_schedules(self, **overrides):
        schedules = {
            CONSUMER: {},
            FAST_LANE: {"schedule_interval": "0 0 * * *"},
            NAZARE: {"schedule_interval": "0 12 * * *"},
        }
        schedules.update(overrides)
        return schedules

    def test_nazare_regression_reports_late_upstream(self):
        # arrange
        old_graph = {CONSUMER: [_dep(FAST_LANE)]}
        new_graph = {CONSUMER: [_dep(FAST_LANE), _dep(NAZARE)]}
        schedules = self._dataset_schedules()
        downstreams = {
            CONSUMER: [
                "bietlejuice.dw_bpo_performance",
                "bietlejuice.dw_listing",
            ]
        }

        # act
        findings = mod.find_late_schedule_findings(
            old_graph,
            new_graph,
            schedules,
            downstreams=downstreams,
        )

        # assert
        assert len(findings) == 1
        finding = findings[0]
        assert finding.kind == "new_late_upstream"
        assert finding.consumer == CONSUMER
        assert finding.producer == NAZARE
        assert finding.descendant_count == 2
        assert "bietlejuice.dw_bpo_performance" in finding.descendants

    def test_cron_consumer_gaining_late_upstream_is_ignored(self):
        # arrange
        cron_consumer = "bietlejuice.cron_consumer"
        old_graph = {cron_consumer: [_dep(FAST_LANE)]}
        new_graph = {cron_consumer: [_dep(FAST_LANE), _dep(NAZARE)]}
        schedules = self._dataset_schedules(
            **{
                cron_consumer: {"schedule_interval": "0 6 * * *"},
            }
        )

        # act
        findings = mod.find_late_schedule_findings(old_graph, new_graph, schedules)

        # assert
        assert findings == []

    def test_manual_consumer_is_ignored(self):
        # arrange
        manual_consumer = "bietlejuice.manual_consumer"
        old_graph = {manual_consumer: [_dep(FAST_LANE)]}
        new_graph = {manual_consumer: [_dep(FAST_LANE), _dep(NAZARE)]}
        schedules = self._dataset_schedules(
            **{
                manual_consumer: {"schedule_interval": None},
            }
        )

        # act
        findings = mod.find_late_schedule_findings(old_graph, new_graph, schedules)

        # assert
        assert findings == []

    def test_new_earlier_upstream_does_not_report(self):
        # arrange
        hourly = "bietlejuice.hourly_upstream"
        noon_upstream = "bietlejuice.noon_upstream"
        old_graph = {CONSUMER: [_dep(noon_upstream)]}
        new_graph = {CONSUMER: [_dep(noon_upstream), _dep(hourly)]}
        schedules = {
            CONSUMER: {},
            noon_upstream: {"schedule_interval": "0 12 * * *"},
            hourly: {"schedule_interval": "0 * * * *"},
        }

        # act
        findings = mod.find_late_schedule_findings(old_graph, new_graph, schedules)

        # assert
        assert findings == []

    def test_allowlisted_pair_is_suppressed(self):
        # arrange
        old_graph = {CONSUMER: [_dep(FAST_LANE)]}
        new_graph = {CONSUMER: [_dep(FAST_LANE), _dep(NAZARE)]}
        schedules = self._dataset_schedules()
        allowlist = {(CONSUMER, NAZARE): "approved exception"}

        # act
        findings = mod.find_late_schedule_findings(
            old_graph,
            new_graph,
            schedules,
            allowlist=allowlist,
        )

        # assert
        assert findings == []

    def test_delayed_producer_with_dataset_children_reports(self):
        # arrange
        producer = "bietlejuice.delayed_producer"
        child = "bietlejuice.dataset_child"
        old_graph = {child: [_dep(producer)]}
        new_graph = {child: [_dep(producer)]}
        old_schedules = {
            producer: {"schedule_interval": "0 0 * * *"},
            child: {},
        }
        new_schedules = {
            producer: {"schedule_interval": "0 12 * * *"},
            child: {},
        }
        downstreams = {producer: [child]}

        # act
        findings = mod.find_late_schedule_findings(
            old_graph,
            new_graph,
            new_schedules,
            old_schedules=old_schedules,
            downstreams=downstreams,
        )

        # assert
        assert len(findings) == 1
        finding = findings[0]
        assert finding.kind == "delayed_producer"
        assert finding.producer == producer
        assert finding.descendant_count == 1

    def test_descendant_count_is_not_capped(self):
        # arrange
        old_graph = {CONSUMER: [_dep(FAST_LANE)]}
        new_graph = {CONSUMER: [_dep(FAST_LANE), _dep(NAZARE)]}
        schedules = self._dataset_schedules()
        downstreams = {
            CONSUMER: [f"bietlejuice.dw_child_{index}" for index in range(25)]
        }

        # act
        findings = mod.find_late_schedule_findings(
            old_graph,
            new_graph,
            schedules,
            downstreams=downstreams,
        )

        # assert
        assert findings[0].descendant_count == 25

    def test_replacing_noon_with_earlier_cron_is_not_late(self):
        noon = "bietlejuice.noon_upstream"
        morning = "bietlejuice.morning_upstream"
        old_graph = {CONSUMER: [_dep(noon)]}
        new_graph = {CONSUMER: [_dep(morning)]}
        schedules = {
            CONSUMER: {},
            noon: {"schedule_interval": "0 12 * * *"},
            morning: {"schedule_interval": "0 6 * * *"},
        }

        findings = mod.find_late_schedule_findings(old_graph, new_graph, schedules)

        assert findings == []

    def test_new_dataset_dag_first_daytime_wait_is_not_late(self):
        new_consumer = "bietlejuice.brand_new_dataset"
        old_graph = {}
        new_graph = {new_consumer: [_dep(NAZARE)]}
        schedules = {
            new_consumer: {},
            NAZARE: {"schedule_interval": "0 12 * * *"},
        }

        findings = mod.find_late_schedule_findings(old_graph, new_graph, schedules)

        assert findings == []

    def test_swap_that_is_later_than_removed_parent_is_reported(self):
        noon = "bietlejuice.noon_upstream"
        afternoon = "bietlejuice.afternoon_upstream"
        old_graph = {CONSUMER: [_dep(noon)]}
        new_graph = {CONSUMER: [_dep(afternoon)]}
        schedules = {
            CONSUMER: {},
            noon: {"schedule_interval": "0 12 * * *"},
            afternoon: {"schedule_interval": "0 13 * * *"},
        }

        findings = mod.find_late_schedule_findings(old_graph, new_graph, schedules)

        assert len(findings) == 1
        assert findings[0].producer == afternoon
        assert findings[0].old_ready_minutes == 12 * 60
        assert findings[0].old_ready_producer == noon

    def test_monthly_producer_added_to_midnight_consumer_is_reported(self):
        monthly = "bietlejuice.itbi_sp"
        old_graph = {CONSUMER: [_dep(FAST_LANE)]}
        new_graph = {CONSUMER: [_dep(FAST_LANE), _dep(monthly)]}
        schedules = self._dataset_schedules(
            **{monthly: {"schedule_interval": "0 13 15,30 * *"}}
        )

        findings = mod.find_late_schedule_findings(old_graph, new_graph, schedules)

        assert len(findings) == 1
        assert findings[0].producer == monthly
        assert findings[0].producer_first_tick_minutes == 13 * 60


class TestPrintReport:
    def test_prints_consumer_finding_details(self, capsys):
        finding = mod.LateScheduleFinding(
            kind="new_late_upstream",
            consumer=CONSUMER,
            producer=NAZARE,
            producer_schedule="0 12 * * *",
            producer_first_tick_minutes=12 * 60,
            old_ready_minutes=0,
            old_ready_producer=FAST_LANE,
            descendants=["bietlejuice.dw_bpo_performance"],
        )

        mod.print_report([finding], "abc1234")

        output = capsys.readouterr().out
        assert CONSUMER in output
        assert NAZARE in output
        assert "12:00 America/Sao_Paulo" in output
        assert "dataset-triggered descendants" in output
        assert "dw_bpo_performance" in output

    def test_caps_descendant_names_and_keeps_full_count(self, capsys):
        descendants = [f"bietlejuice.dw_child_{index}" for index in range(25)]
        finding = mod.LateScheduleFinding(
            kind="new_late_upstream",
            consumer=CONSUMER,
            producer=NAZARE,
            producer_schedule="0 12 * * *",
            producer_first_tick_minutes=12 * 60,
            old_ready_minutes=0,
            old_ready_producer=FAST_LANE,
            descendants=descendants,
        )

        mod.print_report([finding], "abc1234")

        output = capsys.readouterr().out
        assert "inherit this wait: 25" in output
        assert "+5 more" in output


class TestMain:
    _UNSET = object()

    def _stub_lookups(
        self,
        monkeypatch,
        findings,
        *,
        old_graph=None,
        load_old_graph_returns=_UNSET,
    ):
        monkeypatch.setattr(mod, "fetch_diff_base", lambda _from: None)
        monkeypatch.setattr(mod, "resolve_base_commit", lambda _from, _to: "abc1234")
        if load_old_graph_returns is not self._UNSET:
            monkeypatch.setattr(
                mod,
                "load_dependencies_from_commit",
                lambda _commit: load_old_graph_returns,
            )
        else:
            monkeypatch.setattr(
                mod,
                "load_dependencies_from_commit",
                lambda _commit: old_graph or {},
            )
        monkeypatch.setattr(mod, "load_current_dependencies", lambda: {})
        monkeypatch.setattr(mod, "load_schedules_from_declarations", lambda: {})
        monkeypatch.setattr(mod, "load_allowlist", lambda: {})
        monkeypatch.setattr(
            mod,
            "find_late_schedule_findings",
            lambda *_args, **_kwargs: findings,
        )

    def test_defaults_to_pr_target_branch(self, monkeypatch):
        monkeypatch.setenv("CI_PIPELINE_EVENT", "pull_request")
        monkeypatch.setenv("CI_COMMIT_BRANCH", "development")
        monkeypatch.delenv("CI_COMMIT_TARGET_BRANCH", raising=False)

        assert mod._parse_args([]).from_branch == "origin/development"

    def test_fails_when_findings_remain(self, monkeypatch, capsys):
        self._stub_lookups(
            monkeypatch,
            [
                mod.LateScheduleFinding(
                    kind="new_late_upstream",
                    consumer=CONSUMER,
                    producer=NAZARE,
                    producer_schedule="0 12 * * *",
                    producer_first_tick_minutes=12 * 60,
                    old_ready_minutes=0,
                    old_ready_producer=FAST_LANE,
                    descendants=[],
                )
            ],
        )

        assert mod.main([]) == 1
        assert "introducing a dependency whose first daily run is later" in (
            capsys.readouterr().out
        )

    def test_passes_when_there_are_no_findings(self, monkeypatch, capsys):
        self._stub_lookups(monkeypatch, [])

        assert mod.main([]) == 0
        assert "No new late-schedule DAG dependencies" in capsys.readouterr().out

    def test_passes_when_merge_base_yaml_is_missing(self, monkeypatch, capsys):
        def missing_old_graph(_commit):
            print(
                "WARNING: could not read dags/dependencies.yaml at abc1234, so this "
                "validation is being skipped."
            )
            return None

        monkeypatch.setattr(mod, "fetch_diff_base", lambda _from: None)
        monkeypatch.setattr(mod, "resolve_base_commit", lambda _from, _to: "abc1234")
        monkeypatch.setattr(mod, "load_dependencies_from_commit", missing_old_graph)
        monkeypatch.setattr(mod, "load_current_dependencies", lambda: {})
        monkeypatch.setattr(mod, "load_schedules_from_declarations", lambda: {})
        monkeypatch.setattr(mod, "load_allowlist", lambda: {})
        monkeypatch.setattr(mod, "find_late_schedule_findings", lambda *_a, **_k: [])

        assert mod.main([]) == 0
        output = capsys.readouterr().out
        assert "WARNING" in output
        assert "introducing a dependency whose first daily run is later" not in output


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
