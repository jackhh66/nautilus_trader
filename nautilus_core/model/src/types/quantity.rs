// -------------------------------------------------------------------------------------------------
//  Copyright (C) 2015-2023 Nautech Systems Pty Ltd. All rights reserved.
//  https://nautechsystems.io
//
//  Licensed under the GNU Lesser General Public License Version 3.0 (the "License");
//  You may not use this file except in compliance with the License.
//  You may obtain a copy of the License at https://www.gnu.org/licenses/lgpl-3.0.en.html
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
// -------------------------------------------------------------------------------------------------

use std::{
    cmp::Ordering,
    collections::hash_map::DefaultHasher,
    fmt::{Debug, Display, Formatter},
    hash::{Hash, Hasher},
    ops::{Add, AddAssign, Deref, Mul, MulAssign, Sub, SubAssign},
    str::FromStr,
};

use anyhow::Result;
use nautilus_core::{
    correctness::check_f64_in_range_inclusive, parsing::precision_from_str, python::to_pyvalue_err,
};
use pyo3::prelude::*;
use rust_decimal::Decimal;
use serde::{Deserialize, Deserializer, Serialize};

use super::fixed::{check_fixed_precision, FIXED_PRECISION, FIXED_SCALAR};
use crate::types::fixed::{f64_to_fixed_u64, fixed_u64_to_f64};

pub const QUANTITY_MAX: f64 = 18_446_744_073.0;
pub const QUANTITY_MIN: f64 = 0.0;

#[repr(C)]
#[derive(Copy, Clone, Eq, Default)]
#[pyclass]
pub struct Quantity {
    pub raw: u64,
    pub precision: u8,
}

impl Quantity {
    pub fn new(value: f64, precision: u8) -> Result<Self> {
        check_f64_in_range_inclusive(value, QUANTITY_MIN, QUANTITY_MAX, "`Quantity` value")?;
        check_fixed_precision(precision)?;

        Ok(Self {
            raw: f64_to_fixed_u64(value, precision),
            precision,
        })
    }

    #[must_use]
    pub fn from_raw(raw: u64, precision: u8) -> Self {
        check_fixed_precision(precision).unwrap();
        Self { raw, precision }
    }

    #[must_use]
    pub fn zero(precision: u8) -> Self {
        check_fixed_precision(precision).unwrap();
        Quantity::new(0.0, precision).unwrap()
    }

    #[must_use]
    pub fn is_zero(&self) -> bool {
        self.raw == 0
    }

    #[must_use]
    pub fn is_positive(&self) -> bool {
        self.raw > 0
    }

    #[must_use]
    pub fn as_f64(&self) -> f64 {
        fixed_u64_to_f64(self.raw)
    }

    #[must_use]
    pub fn as_decimal(&self) -> Decimal {
        // Scale down the raw value to match the precision
        let rescaled_raw = self.raw / u64::pow(10, (FIXED_PRECISION - self.precision) as u32);
        Decimal::from_i128_with_scale(rescaled_raw as i128, self.precision as u32)
    }
}

impl From<Quantity> for f64 {
    fn from(qty: Quantity) -> Self {
        qty.as_f64()
    }
}

impl From<&Quantity> for f64 {
    fn from(qty: &Quantity) -> Self {
        qty.as_f64()
    }
}

impl FromStr for Quantity {
    type Err = String;

    fn from_str(input: &str) -> Result<Self, Self::Err> {
        let float_from_input = input
            .parse::<f64>()
            .map_err(|e| format!("Cannot parse `input` string '{input}' as f64: {e}"))?;

        Self::new(float_from_input, precision_from_str(input))
            .map_err(|e: anyhow::Error| e.to_string())
    }
}

impl From<&str> for Quantity {
    fn from(input: &str) -> Self {
        Self::from_str(input).unwrap()
    }
}

impl From<i64> for Quantity {
    fn from(input: i64) -> Self {
        Self::new(input as f64, 0).unwrap()
    }
}

impl Hash for Quantity {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.raw.hash(state)
    }
}

impl PartialEq for Quantity {
    fn eq(&self, other: &Self) -> bool {
        self.raw == other.raw
    }
}

impl PartialOrd for Quantity {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }

    fn lt(&self, other: &Self) -> bool {
        self.raw.lt(&other.raw)
    }

    fn le(&self, other: &Self) -> bool {
        self.raw.le(&other.raw)
    }

    fn gt(&self, other: &Self) -> bool {
        self.raw.gt(&other.raw)
    }

    fn ge(&self, other: &Self) -> bool {
        self.raw.ge(&other.raw)
    }
}

impl Ord for Quantity {
    fn cmp(&self, other: &Self) -> Ordering {
        self.raw.cmp(&other.raw)
    }
}

impl Deref for Quantity {
    type Target = u64;

    fn deref(&self) -> &Self::Target {
        &self.raw
    }
}

impl Add for Quantity {
    type Output = Self;
    fn add(self, rhs: Self) -> Self::Output {
        Self {
            raw: self.raw + rhs.raw,
            precision: self.precision,
        }
    }
}

impl Sub for Quantity {
    type Output = Self;
    fn sub(self, rhs: Self) -> Self::Output {
        Self {
            raw: self.raw - rhs.raw,
            precision: self.precision,
        }
    }
}

impl Mul for Quantity {
    type Output = Self;
    fn mul(self, rhs: Self) -> Self::Output {
        Self {
            raw: (self.raw * rhs.raw) / (FIXED_SCALAR as u64),
            precision: self.precision,
        }
    }
}

impl Mul<f64> for Quantity {
    type Output = f64;
    fn mul(self, rhs: f64) -> Self::Output {
        self.as_f64() * rhs
    }
}

impl From<Quantity> for u64 {
    fn from(value: Quantity) -> Self {
        value.raw
    }
}

impl From<&Quantity> for u64 {
    fn from(value: &Quantity) -> Self {
        value.raw
    }
}

impl<T: Into<u64>> AddAssign<T> for Quantity {
    fn add_assign(&mut self, other: T) {
        self.raw += other.into();
    }
}

impl<T: Into<u64>> SubAssign<T> for Quantity {
    fn sub_assign(&mut self, other: T) {
        self.raw -= other.into();
    }
}

impl<T: Into<u64>> MulAssign<T> for Quantity {
    fn mul_assign(&mut self, other: T) {
        self.raw *= other.into();
    }
}

impl Debug for Quantity {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:.*}", self.precision as usize, self.as_f64())
    }
}

impl Display for Quantity {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:.*}", self.precision as usize, self.as_f64())
    }
}

impl Serialize for Quantity {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

impl<'de> Deserialize<'de> for Quantity {
    fn deserialize<D>(_deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let qty_str: &str = Deserialize::deserialize(_deserializer)?;
        let qty: Quantity = qty_str.into();
        Ok(qty)
    }
}

////////////////////////////////////////////////////////////////////////////////
// Python API
////////////////////////////////////////////////////////////////////////////////
#[cfg(feature = "python")]
#[pymethods]
impl Quantity {
    #[new]
    fn py_new(value: f64, precision: u8) -> PyResult<Self> {
        Quantity::new(value, precision).map_err(to_pyvalue_err)
    }

    fn __hash__(&self) -> isize {
        let mut h = DefaultHasher::new();
        self.hash(&mut h);
        h.finish() as isize
    }

    fn __str__(&self) -> String {
        self.to_string()
    }

    fn __repr__(&self) -> String {
        format!("{self:?}")
    }

    #[staticmethod]
    #[pyo3(name = "zero")]
    #[pyo3(signature = (precision = 0))]
    fn py_zero(precision: u8) -> PyResult<Quantity> {
        Quantity::new(0.0, precision).map_err(to_pyvalue_err)
    }

    #[getter]
    fn raw(&self) -> u64 {
        self.raw
    }

    #[getter]
    fn precision(&self) -> u8 {
        self.precision
    }

    #[pyo3(name = "as_double")]
    fn py_as_double(&self) -> f64 {
        self.as_f64()
    }

    #[staticmethod]
    #[pyo3(name = "from_int")]
    fn py_from_int(value: u64) -> PyResult<Quantity> {
        Quantity::new(value as f64, 0).map_err(to_pyvalue_err)
    }

    #[staticmethod]
    #[pyo3(name = "from_str")]
    fn py_from_str(value: &str) -> PyResult<Quantity> {
        Quantity::from_str(value).map_err(to_pyvalue_err)
    }

    #[pyo3(name = "as_decimal")]
    fn py_as_decimal(&self) -> Decimal {
        self.as_decimal()
    }
}

////////////////////////////////////////////////////////////////////////////////
// C API
////////////////////////////////////////////////////////////////////////////////
#[cfg(feature = "ffi")]
#[no_mangle]
pub extern "C" fn quantity_new(value: f64, precision: u8) -> Quantity {
    // SAFETY: Assumes `value` and `precision` were properly validated
    Quantity::new(value, precision).unwrap()
}

#[cfg(feature = "ffi")]
#[no_mangle]
pub extern "C" fn quantity_from_raw(raw: u64, precision: u8) -> Quantity {
    Quantity::from_raw(raw, precision)
}

#[cfg(feature = "ffi")]
#[no_mangle]
pub extern "C" fn quantity_as_f64(qty: &Quantity) -> f64 {
    qty.as_f64()
}

#[cfg(feature = "ffi")]
#[no_mangle]
pub extern "C" fn quantity_add_assign(mut a: Quantity, b: Quantity) {
    a.add_assign(b);
}

#[cfg(feature = "ffi")]
#[no_mangle]
pub extern "C" fn quantity_add_assign_u64(mut a: Quantity, b: u64) {
    a.add_assign(b);
}

#[cfg(feature = "ffi")]
#[no_mangle]
pub extern "C" fn quantity_sub_assign(mut a: Quantity, b: Quantity) {
    a.sub_assign(b);
}

#[cfg(feature = "ffi")]
#[no_mangle]
pub extern "C" fn quantity_sub_assign_u64(mut a: Quantity, b: u64) {
    a.sub_assign(b);
}

////////////////////////////////////////////////////////////////////////////////
// Tests
////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use float_cmp::approx_eq;
    use rust_decimal_macros::dec;

    use super::*;

    #[test]
    #[should_panic(expected = "Condition failed: `precision` was greater than the maximum ")]
    fn test_invalid_precision_new() {
        // Precision out of range for fixed
        let _ = Quantity::new(1.0, 10).unwrap();
    }

    #[test]
    #[should_panic(expected = "Condition failed: `precision` was greater than the maximum ")]
    fn test_invalid_precision_from_raw() {
        // Precision out of range for fixed
        let _ = Quantity::from_raw(1, 10);
    }

    #[test]
    #[should_panic(expected = "Condition failed: `precision` was greater than the maximum ")]
    fn test_invalid_precision_zero() {
        // Precision out of range for fixed
        let _ = Quantity::zero(10);
    }

    #[test]
    fn test_new() {
        let qty = Quantity::new(0.00812, 8).unwrap();
        assert_eq!(qty, qty);
        assert_eq!(qty.raw, 8_120_000);
        assert_eq!(qty.precision, 8);
        assert_eq!(qty.as_f64(), 0.00812);
        assert_eq!(qty.to_string(), "0.00812000");
        assert!(!qty.is_zero());
        assert!(qty.is_positive());
        assert_eq!(qty.as_decimal(), dec!(0.00812000));
        assert!(approx_eq!(f64, qty.as_f64(), 0.00812, epsilon = 0.000001));
    }

    #[test]
    fn test_zero() {
        let qty = Quantity::zero(8);
        assert_eq!(qty.raw, 0);
        assert_eq!(qty.precision, 8);
        assert!(qty.is_zero());
        assert!(!qty.is_positive());
    }

    #[test]
    fn test_from_i64() {
        let qty = Quantity::from(100_000);
        assert_eq!(qty, qty);
        assert_eq!(qty.raw, 100_000_000_000_000);
        assert_eq!(qty.precision, 0);
    }

    #[test]
    fn test_with_maximum_value() {
        let qty = Quantity::new(QUANTITY_MAX, 0).unwrap();
        assert_eq!(qty.raw, 18_446_744_073_000_000_000);
        assert_eq!(qty.to_string(), "18446744073");
    }

    #[test]
    fn test_with_minimum_positive_value() {
        let qty = Quantity::new(0.000000001, 9).unwrap();
        assert_eq!(qty.raw, 1);
        assert_eq!(qty.to_string(), "0.000000001");
    }

    #[test]
    fn test_with_minimum_value() {
        let qty = Quantity::new(QUANTITY_MIN, 9).unwrap();
        assert_eq!(qty.raw, 0);
        assert_eq!(qty.to_string(), "0.000000000");
    }

    #[test]
    fn test_is_zero() {
        let qty = Quantity::zero(8);
        assert_eq!(qty, qty);
        assert_eq!(qty.raw, 0);
        assert_eq!(qty.precision, 8);
        assert_eq!(qty.as_f64(), 0.0);
        assert_eq!(qty.to_string(), "0.00000000");
        assert!(qty.is_zero());
    }

    #[test]
    fn test_precision() {
        let qty = Quantity::new(1.001, 2).unwrap();
        assert_eq!(qty.raw, 1_000_000_000);
        assert_eq!(qty.to_string(), "1.00");
    }

    #[test]
    fn test_new_from_str() {
        let qty = Quantity::from_str("0.00812000").unwrap();
        assert_eq!(qty, qty);
        assert_eq!(qty.raw, 8_120_000);
        assert_eq!(qty.precision, 8);
        assert_eq!(qty.as_f64(), 0.00812);
        assert_eq!(qty.to_string(), "0.00812000");
    }

    #[test]
    fn test_from_str_valid_input() {
        let input = "1000.25";
        let expected_quantity = Quantity::new(1000.25, precision_from_str(input)).unwrap();
        let result = Quantity::from_str(input).unwrap();
        assert_eq!(result, expected_quantity);
    }

    #[test]
    fn test_from_str_invalid_input() {
        let input = "invalid";
        let result = Quantity::from_str(input);
        assert!(result.is_err());
    }

    #[test]
    fn test_add() {
        let quantity1 = Quantity::new(1.0, 0).unwrap();
        let quantity2 = Quantity::new(2.0, 0).unwrap();
        let quantity3 = quantity1 + quantity2;
        assert_eq!(quantity3.raw, 3_000_000_000);
    }

    #[test]
    fn test_sub() {
        let quantity1 = Quantity::new(3.0, 0).unwrap();
        let quantity2 = Quantity::new(2.0, 0).unwrap();
        let quantity3 = quantity1 - quantity2;
        assert_eq!(quantity3.raw, 1_000_000_000);
    }

    #[test]
    fn test_add_assign() {
        let mut quantity1 = Quantity::new(1.0, 0).unwrap();
        let quantity2 = Quantity::new(2.0, 0).unwrap();
        quantity1 += quantity2;
        assert_eq!(quantity1.raw, 3_000_000_000);
    }

    #[test]
    fn test_sub_assign() {
        let mut quantity1 = Quantity::new(3.0, 0).unwrap();
        let quantity2 = Quantity::new(2.0, 0).unwrap();
        quantity1 -= quantity2;
        assert_eq!(quantity1.raw, 1_000_000_000);
    }

    #[test]
    fn test_mul() {
        let quantity1 = Quantity::new(2.0, 1).unwrap();
        let quantity2 = Quantity::new(2.0, 1).unwrap();
        let quantity3 = quantity1 * quantity2;
        assert_eq!(quantity3.raw, 4_000_000_000);
    }

    #[test]
    fn test_equality() {
        assert_eq!(
            Quantity::new(1.0, 1).unwrap(),
            Quantity::new(1.0, 1).unwrap()
        );
        assert_eq!(
            Quantity::new(1.0, 1).unwrap(),
            Quantity::new(1.0, 2).unwrap()
        );
        assert_ne!(
            Quantity::new(1.1, 1).unwrap(),
            Quantity::new(1.0, 1).unwrap()
        );
        assert!(Quantity::new(1.0, 1).unwrap() <= Quantity::new(1.0, 2).unwrap());
        assert!(Quantity::new(1.1, 1).unwrap() > Quantity::new(1.0, 1).unwrap());
        assert!(Quantity::new(1.0, 1).unwrap() >= Quantity::new(1.0, 1).unwrap());
        assert!(Quantity::new(1.0, 1).unwrap() >= Quantity::new(1.0, 2).unwrap());
        assert!(Quantity::new(1.0, 1).unwrap() >= Quantity::new(1.0, 2).unwrap());
        assert!(Quantity::new(0.9, 1).unwrap() < Quantity::new(1.0, 1).unwrap());
        assert!(Quantity::new(0.9, 1).unwrap() <= Quantity::new(1.0, 2).unwrap());
        assert!(Quantity::new(0.9, 1).unwrap() <= Quantity::new(1.0, 1).unwrap());
    }

    #[test]
    fn test_display() {
        use std::fmt::Write as FmtWrite;
        let input_string = "44.12";
        let qty = Quantity::from_str(input_string).unwrap();
        let mut res = String::new();
        write!(&mut res, "{qty}").unwrap();
        assert_eq!(res, input_string);
        assert_eq!(qty.to_string(), input_string);
    }
}
