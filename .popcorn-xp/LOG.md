# Popcorn XP Log

## Round 0 — Orientation

### Session Start
Task: Build a demo workflow management framework for forms using SpiffWorkflow.
Roster: scout (orientation), craftsman (driver), expert (navigator).
SpiffWorkflow research complete — UserTask pause/resume mechanism is the core integration point for forms.

## Round 0 — Scout Orientation: SpiffWorkflow API Research

### Version installed
SpiffWorkflow 3.1.2 (latest as of 2026-04-01)

### Confirmed API Patterns (all verified by running code)

**Programmatic workflow creation (no BPMN XML required)**
```python
spec = BpmnProcessSpec(name='my_workflow')
start = StartEvent(spec, 'start', NoneEventDefinition())
task = UserTask(spec, 'collect_info')   # or FormUserTask subclass
end = EndEvent(spec, 'end', NoneEventDefinition())
spec.start.connect(start)
start.connect(task)
task.connect(end)
wf = BpmnWorkflow(spec)
```

**Pause/resume at UserTask**
- `wf.do_engine_steps()` runs until a UserTask is reached; UserTask stays READY
- `wf.get_tasks(state=TaskState.READY)` returns the blocked task(s)
- Set `task.data.update({...})` then `task.complete()` to resume
- TaskState constants: READY=16, COMPLETED=64, WAITING=8

**Data propagation**
- Data set on a task is copied forward to all subsequent tasks automatically
- All tasks in the chain see the accumulated dict from all prior steps

**Serialization**
- `BpmnWorkflowSerializer` serializes to/from JSON
- Default: custom attributes on task_spec (e.g. `form_schema`) are silently dropped
- Fix: subclass `UserTask` → `FormUserTask(form_schema=...)` and register a custom `BpmnTaskSpecConverter`
- Pattern: `BpmnWorkflowSerializer.configure(config=custom_config)` returns a registry; pass to serializer

### Surprises / Gotchas

1. **No built-in form support**: `UserTask` is a thin wrapper — `manual=True` is literally its only addition. We own the form schema layer entirely.
2. **Serializer drops unknown attributes silently**: Setting `task_spec.form_schema = ...` and serializing loses it with no error. Must use custom converter.
3. **`BpmnWorkflowSerializer(config=...)` doesn't exist**: The config goes through `BpmnWorkflowSerializer.configure(config=...)` which returns a registry, then `BpmnWorkflowSerializer(registry=registry)`.
4. **`DEFAULT_CONFIG` is a class-keyed dict**: Extend it with `dict(DEFAULT_CONFIG)` then add your subclass as a key. Don't mutate it in place.
5. **`BpmnProcessSpec` auto-creates `Start`, `End`, and `EndJoin` internal tasks**: Don't be confused by these — they appear in `task_specs` but are infrastructure.
6. **`UserTask` lives in `SpiffWorkflow.bpmn.specs.defaults`**, not `SpiffWorkflow.specs`. The old non-BPMN `SpiffWorkflow.specs` namespace has no UserTask at all.

### Recommended Package Structure for Implementation

```
src/form_workflow/
    __init__.py
    forms.py          # FormField, FormSchema dataclasses + validate()
    engine.py         # WorkflowManager: build spec, run, pause, submit, complete
    integration.py    # FormUserTask subclass + FormUserTaskConverter for serializer
```

- `integration.py` owns the `FormUserTask` subclass and its serializer converter
- `engine.py` builds the registry via `BpmnWorkflowSerializer.configure(custom_config)` and holds it
- `forms.py` is pure Python dataclasses — no SpiffWorkflow imports needed

### Probe Script
`.popcorn-xp/spiff_probe.py` — 8 passing tests covering:
- Programmatic workflow construction
- UserTask pause behavior
- form_schema accessibility from ready task
- Data propagation between steps
- Full workflow completion
- Serialize/deserialize mid-workflow
- form_schema survival through serialization round-trip
- TaskState constant values

Run with: `python .popcorn-xp/spiff_probe.py`

---

## Round 1 — Task #1: Project Setup (craftsman)

- Created pyproject.toml (setuptools build, SpiffWorkflow + pytest dev deps)
- Created src/form_workflow/__init__.py, engine.py, forms.py, integration.py (stubs with docstrings)
- Created tests/__init__.py, tests/conftest.py
- Created .venv with python3.12, installed project in dev mode
- Verified: SpiffWorkflow 3.1.2 imports OK
- Task #1 complete. Moving to Task #2 (WorkflowManager) and Task #3 (FormSchema) in parallel.

## Round 2 — Tasks #2 and #3 (craftsman)

### Task #3: FormSchema (forms.py)
- FormField dataclass: name, field_type, label, required, options, default
- FormSchema dataclass: title, description, fields list
- FormSchema.validate(data) returns dict[field_name -> list[str]] errors (all at once)
- Supports: text, email, number, select, checkbox, textarea
- email: checks @ and dot in domain; number: float() coercion; select: options list; checkbox: isinstance(bool)
- Verified with valid and invalid data.

### Task #2: WorkflowManager (engine.py) + integration.py
- Switched from basic WorkflowSpec/Workflow to BPMN API per scout research
  (BpmnProcessSpec, BpmnWorkflow, BpmnWorkflowSerializer)
- integration.py: FormUserTask (UserTask subclass with form_schema attr), 
  FormUserTaskConverter (round-trips FormSchema through JSON), build_serializer()
- engine.py: WorkflowManager wrapping BpmnWorkflow
  - run(): do_engine_steps()
  - get_pending_user_tasks(): returns [{id, name, form_schema}] for READY tasks
  - complete_user_task(task_id, data): finds by UUID, updates data, calls task.complete()
  - get_state(): serialize_json via BpmnWorkflowSerializer
  - is_completed(): delegates to BpmnWorkflow.is_completed()
  - from_state(json_str): classmethod to restore from JSON
- Verified: two-step form workflow, FormSchema survives serialize/deserialize, data propagates, workflow completes
- Tasks #2 and #3 complete.

## Round 3 — Task #4: UserTask-to-form integration (craftsman)

- Added build_form_workflow_spec(name, steps) to integration.py
- Accepts list of (task_id, FormSchema) pairs, builds BpmnProcessSpec with
  start → FormUserTask(step1) → FormUserTask(step2) → … → end
- Hides BPMN plumbing (StartEvent, EndEvent, NoneEventDefinition) from caller
- Verified: builder + WorkflowManager + serialize/deserialize round-trip all work
- Task #4 complete.

## Round 4 — Task #5: Demo onboarding workflow (craftsman)

- Created src/form_workflow/demo.py: 3-step employee onboarding CLI demo
- Steps: personal_info, employment_details, emergency_contact
- Each step uses FormSchema with appropriate field types (text, email, select, checkbox)
- Demo shows: build spec, run, pause, print form fields, validate, serialize/restore, complete, resume
- Data propagation verified: all 12 submitted fields appear in final summary
- Run with: python -m form_workflow.demo
- Task #5 complete.

## Round 5 — Task #6: Tests (craftsman)

- tests/conftest.py: personal_schema, job_schema, two_step_spec fixtures
- tests/test_forms.py: 18 tests covering FormField construction, type validation, all field types
- tests/test_engine.py: 13 tests covering build_form_workflow_spec, WorkflowManager lifecycle,
  serialize/deserialize, data propagation, error paths
- All 31 tests pass in 0.02s
- Task #6 complete. All 6 tasks done.
