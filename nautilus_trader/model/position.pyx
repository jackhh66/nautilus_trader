# -------------------------------------------------------------------------------------------------
#  Copyright (C) 2015-2021 Nautech Systems Pty Ltd. All rights reserved.
#  https://nautechsystems.io
#
#  Licensed under the GNU Lesser General Public License Version 3.0 (the "License");
#  You may not use this file except in compliance with the License.
#  You may obtain a copy of the License at https://www.gnu.org/licenses/lgpl-3.0.en.html
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# -------------------------------------------------------------------------------------------------

from decimal import Decimal

from nautilus_trader.core.correctness cimport Condition
from nautilus_trader.model.c_enums.order_side cimport OrderSide
from nautilus_trader.model.c_enums.position_side cimport PositionSide
from nautilus_trader.model.c_enums.position_side cimport PositionSideParser
from nautilus_trader.model.events cimport OrderFilled
from nautilus_trader.model.identifiers cimport ExecutionId
from nautilus_trader.model.objects cimport Price
from nautilus_trader.model.objects cimport Quantity


cdef class Position:
    """
    Represents a position in a financial market.
    """

    def __init__(self, OrderFilled event not None):
        """
        Initialize a new instance of the `Position` class.

        Parameters
        ----------
        event : OrderFilled
            The order fill event which opened the position.

        Raises
        ------
        ValueError
            If event.position_id has a 'NULL' value.
        ValueError
            If event.strategy_id has a 'NULL' value.

        """
        Condition.true(event.position_id.not_null(), "event.position_id.value was 'NULL'")
        Condition.true(event.strategy_id.not_null(), "event.strategy_id.value was 'NULL'")

        self._events = []         # type: list[OrderFilled]
        self._execution_ids = []  # type: list[ExecutionId]
        self._buy_qty = Decimal()
        self._sell_qty = Decimal()

        # Identifiers
        self.id = event.position_id
        self.account_id = event.account_id
        self.from_order = event.cl_ord_id
        self.strategy_id = event.strategy_id
        self.instrument_id = event.instrument_id

        # Properties
        self.symbol = event.instrument_id.symbol
        self.venue = event.instrument_id.venue
        self.entry = event.order_side
        self.side = Position.side_from_order_side(event.order_side)
        self.relative_qty = Decimal()  # Initialized in apply()
        self.quantity = Quantity()     # Initialized in apply()
        self.peak_qty = Quantity()     # Initialized in apply()
        self.timestamp_ns = event.execution_ns
        self.opened_timestamp_ns = event.execution_ns
        self.closed_timestamp_ns = 0
        self.open_duration_ns = 0
        self.avg_px_open = event.fill_price.as_decimal()
        self.avg_px_close = None      # Can be None
        self.quote_currency = event.currency
        self.is_inverse = event.is_inverse
        self.realized_points = Decimal()
        self.realized_return = Decimal()
        self.realized_pnl = Money(0, self.quote_currency)
        self.commission = Money(0, self.quote_currency)
        self._commissions = {}

        self.apply(event)

    def __eq__(self, Position other) -> bool:
        return self.id.value == other.id.value

    def __ne__(self, Position other) -> bool:
        return self.id.value != other.id.value

    def __hash__(self) -> int:
        return hash(self.id.value)

    def __repr__(self) -> str:
        return f"{type(self).__name__}(id={self.id.value}, {self.status_string_c()})"

    cdef list cl_ord_ids_c(self):
        cdef OrderFilled event
        return sorted(list({event.cl_ord_id for event in self._events}))

    cdef list order_ids_c(self):
        cdef OrderFilled event
        return sorted(list({event.order_id for event in self._events}))

    cdef list execution_ids_c(self):
        cdef OrderFilled event
        return [event.execution_id for event in self._events]

    cdef list events_c(self):
        return self._events.copy()

    cdef OrderFilled last_event_c(self):
        return self._events[-1]

    cdef ExecutionId last_execution_id_c(self):
        return self._events[-1].execution_id

    cdef int event_count_c(self) except *:
        return len(self._events)

    cdef str status_string_c(self):
        cdef str quantity = " " if self.relative_qty == 0 else f" {self.quantity.to_str()} "
        return f"{PositionSideParser.to_str(self.side)}{quantity}{self.instrument_id}"

    cdef bint is_open_c(self) except *:
        return self.side != PositionSide.FLAT

    cdef bint is_closed_c(self) except *:
        return self.side == PositionSide.FLAT

    cdef bint is_long_c(self) except *:
        return self.side == PositionSide.LONG

    cdef bint is_short_c(self) except *:
        return self.side == PositionSide.SHORT

    @property
    def cl_ord_ids(self):
        """
        The client order identifiers associated with the position.

        Returns
        -------
        list[OrderId]

        Notes
        -----
        Guaranteed not to contain duplicate identifiers.

        """
        return self.cl_ord_ids_c()

    @property
    def order_ids(self):
        """
        The order identifiers associated with the position.

        Returns
        -------
        list[OrderId]

        Notes
        -----
        Guaranteed not to contain duplicate identifiers.

        """
        return self.order_ids_c()

    @property
    def execution_ids(self):
        """
        The execution identifiers associated with the position.

        Returns
        -------
        list[ExecutionId]

        Notes
        -----
        Assumption that all `ExecutionId`s were, unique, so the list
        may contain duplicates.

        """
        return self.execution_ids_c()

    @property
    def events(self):
        """
        The order fill events of the position.

        Returns
        -------
        list[Event]

        """
        return self.events_c()

    @property
    def last_event(self):
        """
        The last order fill event.

        Returns
        -------
        OrderFilled

        """
        return self.last_event_c()

    @property
    def last_execution_id(self):
        """
        The last execution identifier for the position.

        Returns
        -------
        ExecutionId

        """
        return self.last_execution_id_c()

    @property
    def event_count(self):
        """
        The count of order fill events applied to the position.

        Returns
        -------
        int

        """
        return self.event_count_c()

    @property
    def is_open(self):
        """
        If the position side is not `FLAT`.

        Returns
        -------
        bool
            True if FLAT, else False.

        """
        return self.is_open_c()

    @property
    def is_closed(self):
        """
        If the position side is `FLAT`.

        Returns
        -------
        bool
            True if not FLAT, else False.

        """
        return self.is_closed_c()

    @property
    def is_long(self):
        """
        If the position side is `LONG`.

        Returns
        -------
        bool
            True if LONG, else False.

        """
        return self.is_long_c()

    @property
    def is_short(self):
        """
        If the position side is `SHORT`.

        Returns
        -------
        bool
            True if SHORT, else False.

        """
        return self.is_short_c()

    @staticmethod
    cdef inline PositionSide side_from_order_side_c(OrderSide side) except *:
        Condition.not_equal(side, OrderSide.UNDEFINED, "side", "UNDEFINED")

        return PositionSide.LONG if side == OrderSide.BUY else PositionSide.SHORT

    @staticmethod
    def side_from_order_side(OrderSide side):
        """
        Return the position side resulting from the given order side (from FLAT).

        Parameters
        ----------
        side : OrderSide (Enum)
            The order side

        Returns
        -------
        PositionSide (Enum)

        Raises
        ------
        ValueError
            If side is UNDEFINED.

        """
        return Position.side_from_order_side_c(side)

    cpdef void apply(self, OrderFilled event) except *:
        """
        Applies the given order fill event to the position.

        Parameters
        ----------
        event : OrderFillEvent
            The order fill event to apply.

        Raises
        ------
        KeyError
            If event.execution_id already applied to the position.

        """
        # Fast C method to avoid overhead of subclassing
        self.apply_c(event)

    cdef void apply_c(self, OrderFilled event) except *:
        Condition.not_none(event, "event")
        Condition.not_in(event.execution_id, self._execution_ids, "event.execution_id", "self._execution_ids")

        self._events.append(event)
        self._execution_ids.append(event.execution_id)

        # Calculate cumulative commission
        cdef Currency currency = event.commission.currency
        cdef Money cum_commission = Money(self._commissions.get(currency, Decimal()) + event.commission, currency)
        self._commissions[currency] = cum_commission
        if currency == self.quote_currency:
            self.commission = cum_commission

        # Calculate avg prices, points, return, PnL
        if event.order_side == OrderSide.BUY:
            self._handle_buy_order_fill(event)
        else:  # event.order_side == OrderSide.SELL:
            self._handle_sell_order_fill(event)

        # Set quantities
        self.quantity = Quantity(abs(self.relative_qty))
        if self.quantity > self.peak_qty:
            self.peak_qty = self.quantity

        # Set state
        if self.relative_qty > 0:
            self.side = PositionSide.LONG
        elif self.relative_qty < 0:
            self.side = PositionSide.SHORT
        else:
            self.side = PositionSide.FLAT
            self.closed_timestamp_ns = event.execution_ns
            self.open_duration_ns = self.closed_timestamp_ns - self.opened_timestamp_ns

    cpdef Money notional_value(self, Price last):
        """
        Return the current notional value of the position.

        Parameters
        ----------
        last : Price
            The last close price for the position.

        Returns
        -------
        Money
            In quote currency.

        """
        Condition.not_none(last, "last")

        if self.is_inverse:
            return Money(self.quantity, self.quote_currency)
        else:
            return Money(self.quantity * last, self.quote_currency)

    cpdef Money calculate_pnl(
        self,
        avg_px_open: Decimal,
        avg_px_close: Decimal,
        qty: Decimal,
    ):
        """
        Return a generic PnL from the given parameters.

        Parameters
        ----------
        avg_px_open : Decimal or Price
            The average open price.
        avg_px_close : Decimal or Price
            The average close price.
        qty : Decimal or Quantity
            The quantity for the calculation.

        Returns
        -------
        Money
            In the settlement currency.

        """
        Condition.type(avg_px_open, (Decimal, Price), "avg_px_open")
        Condition.type(avg_px_close, (Decimal, Price), "avg_px_close")
        Condition.type(qty, (Decimal, Quantity), "qty")

        pnl: Decimal = self._calculate_pnl(
            avg_px_open=avg_px_open,
            avg_px_close=avg_px_close,
            qty=qty,
        )

        return Money(pnl, self.quote_currency)

    cpdef Money unrealized_pnl(self, Price last):
        """
        Return the unrealized PnL from the given last quote tick.

        Parameters
        ----------
        last : Price
            The last price for the calculation.

        Returns
        -------
        Money
            In quote currency.

        """
        Condition.not_none(last, "last")

        if self.side == PositionSide.FLAT:
            return Money(0, self.quote_currency)

        pnl: Decimal = self._calculate_pnl(
            avg_px_open=self.avg_px_open,
            avg_px_close=last,
            qty=self.quantity,
        )
        return Money(pnl, self.quote_currency)

    cpdef Money total_pnl(self, Price last):
        """
        Return the total PnL from the given last quote tick.

        Parameters
        ----------
        last : Price
            The last price for the calculation.

        Returns
        -------
        Money
            In quote currency.

        """
        Condition.not_none(last, "last")

        return Money(self.realized_pnl + self.unrealized_pnl(last), self.quote_currency)

    cpdef list commissions(self):
        """
        Return the total commissions generated by the position.

        Returns
        -------
        list[Money]

        """
        return list(self._commissions.values())

    cdef inline void _handle_buy_order_fill(self, OrderFilled event) except *:
        # Initialize realized PnL for fill
        if event.commission.currency == self.quote_currency:
            realized_pnl: Decimal = -event.commission.as_decimal()
        else:
            realized_pnl: Decimal = Decimal()

        # LONG POSITION
        if self.relative_qty > 0:
            self.avg_px_open = self._calculate_avg_px_open_px(event)
        # SHORT POSITION
        elif self.relative_qty < 0:
            self.avg_px_close = self._calculate_avg_px_close_px(event)
            self.realized_points = self._calculate_points(self.avg_px_open, self.avg_px_close)
            self.realized_return = self._calculate_return(self.avg_px_open, self.avg_px_close)
            realized_pnl += self._calculate_pnl(self.avg_px_open, event.fill_price, event.fill_qty)

        self.realized_pnl = Money(self.realized_pnl + realized_pnl, self.quote_currency)

        # Update quantities
        self._buy_qty = self._buy_qty + event.fill_qty
        self.relative_qty = self.relative_qty + event.fill_qty

    cdef inline void _handle_sell_order_fill(self, OrderFilled event) except *:
        # Initialize realized PnL for fill
        if event.commission.currency == self.quote_currency:
            realized_pnl: Decimal = -event.commission.as_decimal()
        else:
            realized_pnl: Decimal = Decimal()

        # SHORT POSITION
        if self.relative_qty < 0:
            self.avg_px_open = self._calculate_avg_px_open_px(event)
        # LONG POSITION
        elif self.relative_qty > 0:
            self.avg_px_close = self._calculate_avg_px_close_px(event)
            self.realized_points = self._calculate_points(self.avg_px_open, self.avg_px_close)
            self.realized_return = self._calculate_return(self.avg_px_open, self.avg_px_close)
            realized_pnl += self._calculate_pnl(self.avg_px_open, event.fill_price, event.fill_qty)

        self.realized_pnl = Money(self.realized_pnl + realized_pnl, self.quote_currency)

        # Update quantities
        self._sell_qty = self._sell_qty + event.fill_qty
        self.relative_qty = self.relative_qty - event.fill_qty

    cdef inline object _calculate_avg_px_open_px(self, OrderFilled event):
        if not self.avg_px_open:
            return event.fill_price

        return self._calculate_avg_px(self.avg_px_open, self.quantity, event)

    cdef inline object _calculate_avg_px_close_px(self, OrderFilled event):
        if not self.avg_px_close:
            return event.fill_price

        close_quantity = self._sell_qty if self.side == PositionSide.LONG else self._buy_qty
        return self._calculate_avg_px(self.avg_px_close, close_quantity, event)

    cdef inline object _calculate_avg_px(
        self,
        avg_px: Decimal,
        qty: Decimal,
        OrderFilled event,
    ):
        start_cost: Decimal = avg_px * qty
        event_cost: Decimal = event.fill_price * event.fill_qty
        cumulative_quantity: Decimal = qty + event.fill_qty
        return (start_cost + event_cost) / cumulative_quantity

    cdef inline object _calculate_points(self, avg_px_open: Decimal, avg_px_close: Decimal):
        if self.side == PositionSide.LONG:
            return avg_px_close - avg_px_open
        elif self.side == PositionSide.SHORT:
            return avg_px_open - avg_px_close
        else:
            return Decimal()  # FLAT

    cdef inline object _calculate_points_inverse(self, avg_px_open: Decimal, avg_px_close: Decimal):
        if self.side == PositionSide.LONG:
            return (1 / avg_px_open) - (1 / avg_px_close)
        elif self.side == PositionSide.SHORT:
            return (1 / avg_px_close) - (1 / avg_px_open)
        else:
            return Decimal()  # FLAT

    cdef inline object _calculate_return(self, avg_px_open: Decimal, avg_px_close: Decimal):
        return self._calculate_points(avg_px_open, avg_px_close) / avg_px_open

    cdef inline object _calculate_pnl(
        self,
        avg_px_open: Decimal,
        avg_px_close: Decimal,
        qty: Decimal,
    ):
        if self.is_inverse:
            return self._calculate_return(avg_px_open, avg_px_close) * qty
        else:
            return self._calculate_points(avg_px_open, avg_px_close) * qty
