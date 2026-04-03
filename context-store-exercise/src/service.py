"""Business logic for the discount engine."""

from datetime import datetime

from .config import MIN_ORDER_AMOUNT
from .models import CouponCode, DiscountRule, Order
from .validators import validate_coupon


def apply_order_discount(order: Order, discount_percent: float) -> float:
    """Apply a flat discount to an order total.

    Returns the discounted total, or the original total if
    the order doesn't meet the minimum amount.
    """
    total = order.total()
    if total < MIN_ORDER_AMOUNT:
        return total
    return total * (1 - discount_percent / 100)


def calculate_discount(price: float, rules: list[DiscountRule]) -> float:
    """Apply the highest-priority non-expired discount rule to a price.

    Args:
        price: The original price to discount.
        rules: List of discount rules to consider.

    Returns:
        The discounted price. If no valid rules exist, returns the original price.
    """
    now = datetime.now()

    # Filter out expired rules
    valid_rules = [
        rule for rule in rules
        if rule.expires_at is None or rule.expires_at >= now
    ]

    # If no valid rules, return original price
    if not valid_rules:
        return price

    # Sort by priority (highest first)
    valid_rules.sort(key=lambda rule: rule.priority, reverse=True)

    # Apply the highest-priority rule
    best_rule = valid_rules[0]
    return price * (1 - best_rule.percentage / 100)


def apply_coupon(order: Order, coupon: CouponCode) -> float:
    """Apply a coupon's discount to an order and increment usage.

    Validates the coupon, applies the coupon's discount rule to the order
    total via calculate_discount, and increments the coupon's current_uses.

    Args:
        order: The order to discount.
        coupon: The coupon to apply.

    Returns:
        The discounted order total.

    Raises:
        ValueError: If the coupon fails validation.
    """
    errors = validate_coupon(coupon)
    if errors:
        raise ValueError(f"Invalid coupon: {'; '.join(errors)}")

    total = order.total()
    discounted = calculate_discount(total, [coupon.discount_rule])
    coupon.current_uses += 1
    return discounted
