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

from cpython.datetime cimport datetime
from libc.stdint cimport int64_t

from nautilus_trader.backtest.data_container cimport BacktestDataContainer
from nautilus_trader.common.clock cimport Clock
from nautilus_trader.common.logging cimport LoggerAdapter
from nautilus_trader.data.engine cimport DataEngine
from nautilus_trader.model.data cimport Data
from nautilus_trader.model.tick cimport QuoteTick
from nautilus_trader.model.tick cimport TradeTick


cdef class DataProducerFacade:
    cdef readonly list execution_resolutions
    cdef readonly datetime min_timestamp
    cdef readonly datetime max_timestamp
    cdef readonly int64_t min_timestamp_ns
    cdef readonly int64_t max_timestamp_ns
    cdef readonly bint has_data

    cpdef void setup(self, int64_t start_ns, int64_t stop_ns) except *
    cpdef void reset(self) except *
    cpdef Data next(self)


cdef class BacktestDataProducer(DataProducerFacade):
    cdef Clock _clock
    cdef LoggerAdapter _log
    cdef DataEngine _data_engine
    cdef BacktestDataContainer _data
    cdef object _quote_tick_data
    cdef object _trade_tick_data
    cdef dict _instrument_index
    cdef bint _is_connected

    cdef unsigned short[:] _quote_instruments
    cdef str[:] _quote_bids
    cdef str[:] _quote_asks
    cdef str[:] _quote_bid_sizes
    cdef str[:] _quote_ask_sizes
    cdef int64_t[:] _quote_timestamps
    cdef int _quote_index
    cdef int _quote_index_last
    cdef QuoteTick _next_quote_tick

    cdef unsigned short[:] _trade_instruments
    cdef str[:] _trade_prices
    cdef str[:] _trade_sizes
    cdef str[:] _trade_match_ids
    cdef str[:] _trade_sides
    cdef int64_t[:] _trade_timestamps
    cdef int _trade_index
    cdef int _trade_index_last
    cdef TradeTick _next_trade_tick

    cpdef LoggerAdapter get_logger(self)
    cpdef void setup(self, int64_t start_ns, int64_t stop_ns) except *
    cpdef void reset(self) except *
    cpdef void clear(self) except *
    cpdef Data next(self)

    cdef inline QuoteTick _generate_quote_tick(self, int index)
    cdef inline TradeTick _generate_trade_tick(self, int index)
    cdef inline void _iterate_quote_ticks(self) except *
    cdef inline void _iterate_trade_ticks(self) except *


cdef class CachedProducer(DataProducerFacade):
    cdef BacktestDataProducer _producer
    cdef LoggerAdapter _log
    cdef list _data_cache
    cdef list _ts_cache
    cdef int _tick_index
    cdef int _tick_index_last
    cdef int _init_start_tick_index
    cdef int _init_stop_tick_index

    cpdef void setup(self, int64_t start_ns, int64_t stop_ns) except *
    cpdef void reset(self) except *
    cpdef Data next(self)
    cdef void _create_data_cache(self) except *
