"""Inspect AI Task wiring: tars's real SKILL.md as system prompt, a ReAct
agent with the sandboxed read_file/run_bash tools, and the golden-query
dataset (``tars_evals``)."""

import os
from pathlib import Path

from inspect_ai import Task, task
from inspect_ai.agent import react
from inspect_ai.dataset import Sample
from inspect_ai.model import ChatMessageSystem, GenerateConfig, Model, get_model
from inspect_ai.solver import Generate, Solver, TaskState, solver

from tars_evals.config import EvalConfig, load_config
from tars_evals.dataset import golden_items_to_samples, load_golden_dataset
from tars_evals.prompt import load_system_prompt
from tars_evals.retry import generate_config_kwargs
from tars_evals.scorer import judge_query_match
from tars_evals.tools import read_file, run_bash

# Package root (packages/tars-evals/), cwd-independent: task.py -> tars_evals
# -> src -> package root.
_PACKAGE_ROOT = Path(__file__).resolve().parents[2]
_DATASETS_DIR = _PACKAGE_ROOT / "datasets"
_CONFIG_PATH = _PACKAGE_ROOT / "config.yaml"


def _resolve_skill_dir() -> Path:
    configured = os.environ.get("TARS_SKILL_DIR")
    if not configured:
        raise RuntimeError(
            "TARS_SKILL_DIR is not set. Point it at your local ai-tools checkout, "
            "e.g. export TARS_SKILL_DIR=/path/to/ai-tools/marketplace/tars/skills/tars"
        )
    return Path(configured)


def _subject_model(cfg: EvalConfig) -> Model:
    """Build the subject model via the openai-api compatible provider (not
    openai/), so Inspect's is_latest/gpt-5 heuristic can't strip temperature=0.

    temperature=0 is pinned HERE (on the subject model) rather than on the
    Task's shared GenerateConfig, because the task config is merged into every
    generate call in the eval — including the judge's. The judge uses
    reasoning_effort (extended thinking), and Vertex Claude rejects
    temperature != 1 when thinking is enabled ("temperature may only be set to
    1 when thinking is enabled") — so a task-level temperature=0 makes the judge
    400. Scoping it to the subject keeps the subject deterministic without
    leaking into the reasoning judge."""
    return get_model(
        cfg.tars_model,
        config=GenerateConfig(temperature=0.0, **generate_config_kwargs()),
    )


@solver
def verbatim_system_message(content: str) -> Solver:
    """Insert `content` as a system message with NO templating.

    Inspect's built-in `system_message()` runs `str.format`-style
    substitution, which mangles the literal curly braces in tars's SKILL.md
    (`${VAR:-default}`, GraphQL `{...}`) and breaks the byte-identical fidelity
    contract. This bypasses templating by building ChatMessageSystem directly.
    """

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        state.messages.insert(0, ChatMessageSystem(content=content))
        return state

    return solve


_SCRIPT_DIR_NOTE_TEMPLATE = """[Eval harness note]
Scripts path — use this literal path when calling python3 (no shell variable expansion):
{scripts_dir}
Commands must be single-line; no backslash continuation, no heredoc."""


_NON_INTERACTIVE_NOTE = """[Eval harness note]
Non-interactive eval — no human will reply. Never ask clarifying questions.
Pick the most reasonable interpretation, state it in one line, then always finish with the SQL (run it via trino_connect.py or include a ```sql block)."""


def _tars_solver_chain(skill_dir: Path, system_prompt: str) -> list[Solver]:
    """Build the tars-faithful agent: verbatim SKILL.md, then a ReAct loop
    with the sandboxed tools.

    ``prompt=None`` and ``submit=False`` preserve fidelity — they suppress
    react()'s default "helpful assistant" prompt and synthetic submit() tool,
    neither of which tars's real sessions have. Without submit, the loop ends
    when the model responds without a tool call, and that message is scored.

    The two harness notes are separate system messages after SKILL.md (never
    edits to it): the script-dir path can't be auto-discovered here because the
    allowlist blocks SKILL.md's `find` preamble (see tools.py).
    """
    scripts_dir = skill_dir / "scripts"
    # verbatim_system_message inserts at index 0, so the LAST solver here ends
    # up FIRST: this order yields [SKILL.md, script-dir note, non-interactive].
    return [
        verbatim_system_message(_NON_INTERACTIVE_NOTE),
        verbatim_system_message(
            _SCRIPT_DIR_NOTE_TEMPLATE.format(scripts_dir=scripts_dir)
        ),
        verbatim_system_message(system_prompt),
        react(
            prompt=None,
            submit=False,
            tools=[read_file(skill_dir), run_bash(skill_dir)],
        ),
    ]


def make_tars_eval_task(
    samples: list[Sample],
    *,
    config: EvalConfig | None = None,
    config_path: Path | None = None,
    skill_dir: Path | None = None,
) -> Task:
    """Assemble the shared Inspect Task used by all-dataset and per-stem runners.

    temperature=0 is NOT set on the Task GenerateConfig — it's pinned on the
    subject model in ``_subject_model()`` so it doesn't leak into the judge's
    reasoning call (Vertex 400s on temperature!=1 + thinking). This task config
    is merged into every generate in the eval, so it must stay temperature-free.
    ``max_tool_output`` is well above Inspect's 16 KB default so DataHub's large
    golden_query payloads aren't truncated mid-JSON. ``message_limit=80`` matches
    tars's 40–60 message workflow before writing SQL.
    """
    if config is None:
        config = load_config(config_path or _CONFIG_PATH)
    resolved_skill_dir = skill_dir if skill_dir is not None else _resolve_skill_dir()
    system_prompt = load_system_prompt(resolved_skill_dir)

    return Task(
        dataset=samples,
        solver=_tars_solver_chain(resolved_skill_dir, system_prompt),
        scorer=judge_query_match(
            config.judge_model,
            config.judge_threshold,
            reasoning_effort=config.judge_reasoning_effort,
            temperature=config.judge_temperature,
        ),
        model=_subject_model(config),
        # Retry policy (bounded attempts + wall clock) comes from retry.py, so
        # the task config, the subject model and the judge can't drift apart.
        config=GenerateConfig(max_tool_output=200_000, **generate_config_kwargs()),
        message_limit=80,
    )


@task
def tars_evals():
    """Run tars against the hand-authored golden-query datasets, scored by
    an LLM judge.

    Loads every ``*.yaml`` under this package's ``datasets/`` directory
    (each a flat list of ``{id, question, expected_query}`` items — no
    doc-derived indirection, no ``{{placeholder}}`` substitution), converts
    the items to Inspect Samples, and scores each with
    ``judge_query_match``: a judge model (config.yaml's ``judge_model``)
    rates the SQL text tars asked ``trino_connect.py`` to run against
    ``expected_query`` on a 1-5 scale, passing at or above
    ``judge_threshold``. ``run_bash`` mocks every ``trino_connect.py`` call
    (see tools.py), so this task needs no Trino/OAuth credentials and no
    live cluster access; it only needs real models (tars_model + judge_model)
    to run.
    """
    golden_paths = sorted(_DATASETS_DIR.glob("*.yaml"))
    if not golden_paths:
        raise RuntimeError(
            f"No *.yaml golden-query datasets found under {_DATASETS_DIR}"
        )
    items = load_golden_dataset(golden_paths)
    samples = golden_items_to_samples(items)
    return make_tars_eval_task(samples, config_path=_CONFIG_PATH)
