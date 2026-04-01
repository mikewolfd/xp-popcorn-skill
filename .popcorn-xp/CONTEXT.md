# Popcorn XP Session — Form Workflow Framework

## Task
Build a demo workflow management framework for forms using SpiffWorkflow (https://github.com/sartography/SpiffWorkflow).

The framework wraps SpiffWorkflow to manage form-driven workflows:
- Define workflows with UserTasks that pause for form input
- Attach JSON-based form schemas to UserTasks
- Run workflows that pause at form steps, accept input, then resume
- Serialize/deserialize workflow state for persistence
- Demo: a multi-step onboarding workflow with forms

## Tech Stack
- Python 3.11+
- SpiffWorkflow (pip install SpiffWorkflow)
- No web framework (CLI demo only)
- pytest for tests

## Roster
| Role | Agent | Current Assignment |
|------|-------|--------------------|
| scout | scout | Orientation & scope mapping |
| craftsman | craftsman | Implementation driver |
| expert | expert | Correctness navigator |

## Current Driver
craftsman (pending — orientation round first)

## Checklist
1. [ ] Project setup (pyproject.toml, package structure, venv, install SpiffWorkflow)
2. [ ] Core WorkflowManager class wrapping SpiffWorkflow
3. [ ] Form schema model (field definitions, validation rules)
4. [ ] UserTask-to-form integration (connect form schemas to workflow tasks)
5. [ ] Demo multi-step workflow (e.g., employee onboarding with 3 form steps)
6. [ ] Tests for core functionality
