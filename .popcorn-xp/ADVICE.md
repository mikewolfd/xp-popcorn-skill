# Popcorn XP Advice

**Current Driver:** none (orientation round)

## Open

---

STR-2-1: Use BpmnWorkflow + BpmnProcessSpec, not core Workflow + WorkflowSpec
File: src/form_workflow/engine.py (to be written)
Evidence: Verified in 3.1.2 — UserTask only exists under SpiffWorkflow.bpmn.specs.defaults; the core `SpiffWorkflow.specs` namespace has no UserTask. BpmnWorkflow + BpmnProcessSpec + BpmnWorkflowSerializer all work programmatically without XML/BPMN files.
Suggestion: Import from `SpiffWorkflow.bpmn.*`. Build spec with: BpmnProcessSpec(name, description), StartEvent(spec, id, NoneEventDefinition()), UserTask(spec, id), EndEvent(spec, id, NoneEventDefinition()), connect via .connect(). Run workflow: wf.do_engine_steps(), then list(wf.get_tasks(state=TaskState.READY)).

---

OBJECTION OBJ-2-1: `get_ready_user_tasks()` does not exist on BpmnWorkflow in 3.1.2
File: src/form_workflow/engine.py (to be written)
Evidence: `hasattr(BpmnWorkflow_instance, 'get_ready_user_tasks')` returns False. The method is referenced in older docs/tutorials but is not present in 3.1.2.
Required: Use `list(wf.get_tasks(state=TaskState.READY))` and filter by `isinstance(t.task_spec, UserTask)` to get ready user tasks. Example: `[t for t in wf.get_tasks(state=TaskState.READY) if isinstance(t.task_spec, UserTask)]`

---

STR-2-2: Task data does not inherit wf.data — initialize data on the task directly
File: src/form_workflow/engine.py (to be written)
Evidence: Verified in 3.1.2 — `task.data` is initially `{}` (empty), not a copy of `wf.data`. Data set on `wf.data` before `do_engine_steps()` is NOT visible in `task.data`. Sequential tasks DO inherit data from their parent task.
Suggestion: To pass initial context to the first UserTask, set it after `do_engine_steps()` by merging into `task.data` before completing it, or inject into the root task directly. Do not rely on `wf.data` being propagated.

---

FYI FYI-2-1: Parallel branch task data behavior — last writer wins, wf.data unchanged
File: src/form_workflow/engine.py (to be written)
Evidence: Verified in 3.1.2 — when two parallel UserTasks write to the same key, the final merged `wf.data` retains the value from BEFORE the split (original), not either branch's value. Branches get isolated data copies. After join, parent task's data (pre-split values) are what propagate forward, not the union of branch writes.
No response needed — just be aware if the demo workflow uses parallel branches.

---

OBJ-2-2: Serializer silently drops form_schema — requires custom FormUserTask subclass + converter (UPDATED from STR-2-3)
File: src/form_workflow/integration.py (to be written)
Evidence: Scout's probe confirmed: setting `task_spec.form_schema = ...` on a plain UserTask and serializing loses it silently. Fix is verified in probe (8/8 passing): subclass UserTask as FormUserTask, write a FormUserTaskConverter extending BpmnTaskSpecConverter, register via `dict(DEFAULT_CONFIG)` + `BpmnWorkflowSerializer.configure(config=custom_config)`. The serializer constructor takes `registry=` not `config=`.
Required:
  1. FormUserTask(UserTask): add `form_schema` param to `__init__`
  2. FormUserTaskConverter(BpmnTaskSpecConverter): to_dict adds form_schema; from_dict pops it and re-attaches after task_spec_from_dict()
  3. Build registry: `custom_config = dict(DEFAULT_CONFIG); custom_config[FormUserTask] = FormUserTaskConverter; registry = BpmnWorkflowSerializer.configure(config=custom_config)`
  4. Instantiate serializer: `BpmnWorkflowSerializer(registry=registry)`
  Do NOT use BpmnWorkflowSerializer(config=...) — that kwarg does not exist.

---

SML-3-1: FormSchema.validate() treats False as falsy — checkbox required fields always fail
File: src/form_workflow/forms.py:77
Evidence: `if form_field.required and (raw is None or raw == "")` — this correctly handles None and empty string, but `False` is a valid checkbox value. A required checkbox with value `False` (user unchecked it) correctly passes this check. However, `raw = data.get(form_field.name, form_field.default)` — if `default=False` and the field is absent from data, it will resolve to `False` and pass the required check even though the user never submitted it. This is a subtle ambiguity: absence-with-default vs explicit submission.
Suggestion: For required validation, distinguish "key absent from data" from "key present with falsy value". Consider checking `form_field.name not in data` as the absent signal, rather than relying on the resolved value.

---

OBJ-4-1: Storing a FormSchema dataclass on form_schema raises TypeError on serialization
File: src/form_workflow/integration.py (to be written)
Evidence: Verified — `FormUserTaskConverter.to_dict()` calls `self.get_default_attributes(spec)` which feeds into `json.dumps()`. If `spec.form_schema` is a FormSchema dataclass (not a plain dict), serialization raises `TypeError: Object of type FormSchema is not JSON serializable`. No warning, just a crash at persistence time.
Required: `form_schema` stored on the task_spec must be a plain JSON-serializable dict (or None), not a FormSchema dataclass instance. The converter's `to_dict` should call `dataclasses.asdict(spec.form_schema)` if a FormSchema is stored, OR the design decision should be to store the schema as a dict always and look up the FormSchema object via task_spec.bpmn_id when needed. Either works — but the boundary must be explicit.

FYI FYI-4-1: get_tasks() returns a plain list, not a generator — indexing and len() are safe
File: src/form_workflow/engine.py (to be written)
Evidence: Verified — `wf.get_tasks(state=TaskState.READY)` returns `<class 'list'>` with `__len__` in SpiffWorkflow 3.1.2. No need to defensively wrap in `list()` before indexing, though doing so is harmless.

---

SML-2-1: get_pending_user_tasks() returns internal SpiffWorkflow engine tasks if called before run()
File: src/form_workflow/engine.py:72
Evidence: Verified — before `run()`, the internal `BpmnStartTask` named 'Start' appears in `get_tasks(state=TaskState.READY)` and is returned by `get_pending_user_tasks()` with `form_schema=None`. If a caller uses this ID with `complete_user_task()`, it succeeds silently and advances the workflow unexpectedly. The method has no guard against this.
Suggestion: Filter `get_pending_user_tasks()` to only include tasks whose `task_spec` is a `FormUserTask` instance: `isinstance(t.task_spec, FormUserTask)`. This makes the method's contract airtight regardless of when it's called.

---

SML-3-1 (CONFIRMED LIVE, BROADER THAN CHECKBOX): any required field with a non-None/non-empty default passes validation when key is absent
File: src/form_workflow/forms.py:74,77
Evidence: Verified — `schema.validate({})` on ANY required field with a non-None, non-empty default (e.g. `default=False` for checkbox, `default=0` for number) returns `{}`. The required check is `raw is None or raw == ""`, and the default fills in a truthy value, so the check is skipped. The tests do not cover this case (test_validate_checkbox_valid tests explicit False, not absent+default). No test for required+default+absent exists.
ALSO: 31/31 tests pass but neither SML fix was applied. The passing test suite does not catch these bugs.
Suggestion: At line 74, distinguish absent from present: `absent = form_field.name not in data`. Use `raw = data[form_field.name] if not absent else form_field.default`. Then required check at line 77: `if form_field.required and (absent or raw is None or raw == "")`. The `absent` flag catches all missing-key cases regardless of default value.
Additional tests needed: test_validate_required_checkbox_absent_default_false, test_validate_required_field_absent_nonzero_default.

## Resolved

---

STR-2-1: RESOLVED — craftsman used BpmnWorkflow + BpmnProcessSpec correctly.
OBJ-2-1: RESOLVED — craftsman used get_tasks(state=TaskState.READY) correctly.
OBJ-2-2: RESOLVED — FormUserTaskConverter with _schema_to_dict/_schema_from_dict implemented and verified working.
OBJ-4-1: RESOLVED — craftsman implemented _schema_to_dict/_schema_from_dict helpers instead of storing dataclass directly.
