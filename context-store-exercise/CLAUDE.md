# Context Store Exercise

This is a test project for validating the popcorn-xp shared context store hooks.

## What This Is

A small Python discount engine. The codebase is intentionally structured so that
multiple files overlap: `config.py` defines constants used everywhere, `models.py`
defines data classes imported by both `service.py` and `validators.py`.

## The Task

Add a discount system:
- A `DiscountRule` dataclass in `models.py` with `name`, `percentage` (float 0-100), `priority` (int), and `expires_at` (optional datetime)
- A `calculate_discount(price: float, rules: list[DiscountRule]) -> float` function in `service.py` that applies the highest-priority non-expired rule
- Validation in `validators.py`: reject expired rules, negative percentages, percentages > 100, and empty names
- Tests in `tests/test_service.py` and `tests/test_validators.py`
- Update `MAX_DISCOUNT_PERCENT` in `config.py` if needed

## Important: Both Agents Must Touch models.py

To exercise the context store's soft lock feature:
- The **driver** should add the `DiscountRule` dataclass
- The **navigator** should independently fix any type hint issues or add docstrings to existing models while reviewing

This means both agents will edit `models.py` during the session, which should trigger the soft lock warning.

## Running Tests

```bash
python -m pytest tests/ -v
```

## Verifying Context Store

After the session, run:
```bash
bash bin/verify-exercise.sh
bash bin/inspect-store.sh
```
