"""Validation rules for the discount engine."""

from datetime import datetime

from .config import MAX_DISCOUNT_PERCENT
from .models import CouponCode, DiscountRule


def validate_discount_percent(percent: float) -> list[str]:
    """Validate a discount percentage. Returns a list of error messages."""
    errors = []
    if percent < 0:
        errors.append("Discount percentage cannot be negative")
    if percent > MAX_DISCOUNT_PERCENT:
        errors.append(f"Discount percentage cannot exceed {MAX_DISCOUNT_PERCENT}%")
    return errors


def validate_discount_rule(rule: DiscountRule) -> list[str]:
    """Validate a discount rule. Returns a list of error messages.

    Checks for:
    - Empty or whitespace-only names
    - Negative percentages
    - Percentages exceeding 100%
    - Rules that have already expired
    """
    errors = []

    # Check for empty name
    if not rule.name or not rule.name.strip():
        errors.append("Rule name cannot be empty")

    # Check for negative percentage
    if rule.percentage < 0:
        errors.append("Discount percentage cannot be negative")

    # Check for percentage > 100
    if rule.percentage > MAX_DISCOUNT_PERCENT:
        errors.append(f"Discount percentage cannot exceed {MAX_DISCOUNT_PERCENT}%")

    # Check for expired rule
    if rule.expires_at is not None and rule.expires_at < datetime.now():
        errors.append("Discount rule has expired")

    return errors


def validate_coupon(coupon: CouponCode) -> list[str]:
    """Validate a coupon code object. Returns a list of error messages."""
    errors = []

    if not coupon.code or not coupon.code.strip():
        errors.append("Coupon code cannot be empty")

    if coupon.max_uses <= 0:
        errors.append("Max uses must be greater than zero")
    elif coupon.current_uses >= coupon.max_uses:
        errors.append("Coupon has reached its maximum number of uses")

    if not coupon.active:
        errors.append("Coupon is not active")

    # Cascading validation: check the nested discount rule
    errors.extend(validate_discount_rule(coupon.discount_rule))

    return errors


def validate_coupon_code_format(code: str) -> list[str]:
    """Validate the format of a coupon code string. Returns a list of error messages.

    Coupon codes must be alphanumeric and between 4-20 characters.
    """
    errors = []

    if not code.isalnum():
        errors.append("Coupon code must be alphanumeric")

    if len(code) < 4 or len(code) > 20:
        errors.append("Coupon code must be between 4 and 20 characters")

    return errors
