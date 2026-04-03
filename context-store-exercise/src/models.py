"""Data models for the discount engine."""

from dataclasses import dataclass
from datetime import datetime
from typing import Optional


@dataclass
class Product:
    """A product that can be added to an order.

    Attributes:
        name: Product display name.
        price: Product price in currency units.
        category: Product category for filtering and reporting.
    """
    name: str
    price: float
    category: str


@dataclass
class Order:
    """A customer order containing products.

    Attributes:
        products: List of products in this order.
        created_at: Timestamp when the order was created.
        customer_id: Unique identifier for the customer.
        notes: Optional notes or special instructions for the order.
    """
    products: list[Product]
    created_at: datetime
    customer_id: str
    notes: Optional[str] = None

    def total(self) -> float:
        """Calculate the total price of all products in the order."""
        return sum(p.price for p in self.products)


@dataclass
class DiscountRule:
    name: str
    percentage: float
    priority: int
    expires_at: Optional[datetime] = None


@dataclass
class CouponCode:
    """A coupon code that applies a discount rule with usage limits.

    Attributes:
        code: The alphanumeric coupon code string.
        discount_rule: The discount rule applied when this coupon is redeemed.
        max_uses: Maximum number of times this coupon can be used.
        current_uses: Number of times this coupon has been used so far.
        active: Whether this coupon is currently active.
    """
    code: str
    discount_rule: DiscountRule
    max_uses: int
    current_uses: int = 0
    active: bool = True
