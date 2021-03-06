/**********************************************************************
*
* atof util
*
* Copyright (c) 2019 Dario Deledda. All rights reserved.
* Use of this source code is governed by an MIT license
* that can be found in the LICENSE file.
*
* This file contains utilities for convert a string in a f64 variable
* IEEE 754 standard is used
*
* Know limitation:
* - limited to 18 significant digits
*
* The code is inspired by:
* Grzegorz Kraszewski krashan@teleinfo.pb.edu.pl
* URL: http://krashan.ppa.pl/articles/stringtofloat/
* Original license: MIT
*
**********************************************************************/
module strconv

union Float64u {
mut:
	f f64
	u u64 = u64(0)
}

/**********************************************************************
*
* 96 bit operation utilities
* Note: when u128 will be available these function can be refactored
*
**********************************************************************/

// right logical shift 96 bit
fn lsr96(s2 u32, s1 u32, s0 u32) (u32,u32,u32) {
	mut r0 := u32(0)
	mut r1 := u32(0)
	mut r2 := u32(0)
	r0 = (s0>>1) | ((s1 & u32(1))<<31)
	r1 = (s1>>1) | ((s2 & u32(1))<<31)
	r2 = s2>>1
	return r2,r1,r0
}

// left logical shift 96 bit
fn lsl96(s2 u32, s1 u32, s0 u32) (u32,u32,u32) {
	mut r0 := u32(0)
	mut r1 := u32(0)
	mut r2 := u32(0)
	r2 = (s2<<1) | ((s1 & (u32(1)<<31))>>31)
	r1 = (s1<<1) | ((s0 & (u32(1)<<31))>>31)
	r0 = s0<<1
	return r2,r1,r0
}

// sum on 96 bit
fn add96(s2 u32, s1 u32, s0 u32, d2 u32, d1 u32, d0 u32) (u32,u32,u32) {
	mut w := u64(0)
	mut r0 := u32(0)
	mut r1 := u32(0)
	mut r2 := u32(0)
	w = u64(s0) + u64(d0)
	r0 = u32(w)
	w >>= 32
	w += u64(s1) + u64(d1)
	r1 = u32(w)
	w >>= 32
	w += u64(s2) + u64(d2)
	r2 = u32(w)
	return r2,r1,r0
}

// subtraction on 96 bit
fn sub96(s2 u32, s1 u32, s0 u32, d2 u32, d1 u32, d0 u32) (u32,u32,u32) {
	mut w := u64(0)
	mut r0 := u32(0)
	mut r1 := u32(0)
	mut r2 := u32(0)
	w = u64(s0) - u64(d0)
	r0 = u32(w)
	w >>= 32
	w += u64(s1) - u64(d1)
	r1 = u32(w)
	w >>= 32
	w += u64(s2) - u64(d2)
	r2 = u32(w)
	return r2,r1,r0
}

/**********************************************************************
*
* Constants
*
**********************************************************************/


const (
//
// f64 constants
//
	DIGITS = 18
	DOUBLE_PLUS_ZERO = u64(0x0000000000000000)
	DOUBLE_MINUS_ZERO = u64(0x8000000000000000)
	DOUBLE_PLUS_INFINITY = u64(0x7FF0000000000000)
	DOUBLE_MINUS_INFINITY = u64(0xFFF0000000000000)
	//
	// parser state machine states
	//
	fsm_a = 0
	fsm_b = 1
	fsm_c = 2
	fsm_d = 3
	fsm_e = 4
	fsm_f = 5
	fsm_g = 6
	fsm_h = 7
	fsm_i = 8
	FSM_STOP = 9
	//
	// Possible parser return values.
	//
	parser_ok = 0 // parser finished OK
	parser_pzero = 1 // no digits or number is smaller than +-2^-1022
	parser_mzero = 2 // number is negative, module smaller
	parser_pinf = 3 // number is higher than +HUGE_VAL
	parser_minf = 4 // number is lower than -HUGE_VAL
	//
	// char constants
	// Note: Modify these if working with non-ASCII encoding
	//
	DPOINT = `.`
	PLUS = `+`
	MINUS = `-`
	ZERO = `0`
	NINE = `9`
	TEN = u32(10)
)
/**********************************************************************
*
* Utility
*
**********************************************************************/

// NOTE: Modify these if working with non-ASCII encoding
fn is_digit(x byte) bool {
	return (x >= ZERO && x <= NINE) == true
}

fn is_space(x byte) bool {
	return ((x >= 0x89 && x <= 0x13) || x == 0x20) == true
}

fn is_exp(x byte) bool {
	return (x == `E` || x == `e`) == true
}

/**********************************************************************
*
* Support struct
*
**********************************************************************/

// The structure is filled by parser, then given to converter.
pub struct PrepNumber {
pub mut:
	negative bool=false // 0 if positive number, 1 if negative
	exponent int=0 // power of 10 exponent
	mantissa u64=u64(0) // integer mantissa
}
/**********************************************************************
*
* String parser
* NOTE: #TOFIX need one char after the last char of the number
*
**********************************************************************/

// parser return a support struct with all the parsing information for the converter
fn parser(s string) (int,PrepNumber) {
	mut state := fsm_a
	mut digx := 0
	mut c := ` ` // initial value for kicking off the state machine
	mut result := parser_ok
	mut expneg := false
	mut expexp := 0
	mut i := 0
	mut pn := PrepNumber{
	}
	for state != FSM_STOP {
		match state {
			// skip starting spaces
			fsm_a {
				if is_space(c) == true {
					c = s[i++]
				}
				else {
					state = fsm_b
				}
			}
			// check for the sign or point
			fsm_b {
				state = fsm_c
				if c == PLUS {
					c = s[i++]
					//i++
				}
				else if c == MINUS {
					pn.negative = true
					c = s[i++]
				}
				else if is_digit(c) {
				}
				else if c == DPOINT {
				}
				else {
					state = FSM_STOP
				}
			}
			// skip the inital zeros
			fsm_c {
				if c == ZERO {
					c = s[i++]
				}
				else if c == DPOINT {
					c = s[i++]
					state = fsm_d
				}
				else {
					state = fsm_e
				}
			}
			// reading leading zeros in the fractional part of mantissa
			fsm_d {
				if c == ZERO {
					c = s[i++]
					if pn.exponent > -2147483647 {
						pn.exponent--
					}
				}
				else {
					state = fsm_f
				}
			}
			// reading integer part of mantissa
			fsm_e {
				if is_digit(c) {
					if digx < DIGITS {
						pn.mantissa *= 10
						pn.mantissa += u64(c - ZERO)
						digx++
					}
					else if pn.exponent < 2147483647 {
						pn.exponent++
					}
					c = s[i++]
				}
				else if c == DPOINT {
					c = s[i++]
					state = fsm_f
				}
				else {
					state = fsm_f
				}
			}
			// reading fractional part of mantissa
			fsm_f {
				if is_digit(c) {
					if digx < DIGITS {
						pn.mantissa *= 10
						pn.mantissa += u64(c - ZERO)
						pn.exponent--
						digx++
					}
					c = s[i++]
				}
				else if is_exp(c) {
					c = s[i++]
					state = fsm_g
				}
				else {
					state = fsm_g
				}
			}
			// reading sign of exponent
			fsm_g {
				if c == PLUS {
					c = s[i++]
				}
				else if c == MINUS {
					expneg = true
					c = s[i++]
				}
				state = fsm_h
			}
			// skipping leading zeros of exponent
			fsm_h {
				if c == ZERO {
					c = s[i++]
				}
				else {
					state = fsm_i
				}
			}
			// reading exponent digits
			fsm_i {
				if is_digit(c) {
					if expexp < 214748364 {
						expexp *= 10
						expexp += int(c - ZERO)
					}
					c = s[i++]
				}
				else {
					state = FSM_STOP
				}
			}
			else {
			}}
		// C.printf("len: %d i: %d str: %s \n",s.len,i,s[..i])
		if i >= s.len {
			state = FSM_STOP
		}
	}
	if expneg {
		expexp = -expexp
	}
	pn.exponent += expexp
	if pn.mantissa == 0 {
		if pn.negative {
			result = parser_mzero
		}
		else {
			result = parser_pzero
		}
	}
	else if (pn.exponent > 309) {
		if pn.negative {
			result = parser_minf
		}
		else {
			result = parser_pinf
		}
	}
	else if pn.exponent < -328 {
		if pn.negative {
			result = parser_mzero
		}
		else {
			result = parser_pzero
		}
	}
	return result,pn
}

/**********************************************************************
*
* Converter to the bit form of the f64 number
*
**********************************************************************/

// converter return a u64 with the bit image of the f64 number
fn converter(pn mut PrepNumber) u64 {
	mut binexp := 92
	mut s2 := u32(0) // 96-bit precision integer
	mut s1 := u32(0)
	mut s0 := u32(0)
	mut q2 := u32(0) // 96-bit precision integer
	mut q1 := u32(0)
	mut q0 := u32(0)
	mut r2 := u32(0) // 96-bit precision integer
	mut r1 := u32(0)
	mut r0 := u32(0)
	mask28 := u32(0xF<<28)
	mut result := u64(0)
	// working on 3 u32 to have 96 bit precision
	s0 = u32(pn.mantissa & u64(0x00000000FFFFFFFF))
	s1 = u32(pn.mantissa>>32)
	s2 = u32(0)
	// so we take the decimal exponent off
	for pn.exponent > 0 {
		q2,q1,q0 = lsl96(s2, s1, s0) // q = s * 2
		r2,r1,r0 = lsl96(q2, q1, q0) // r = s * 4 <=> q * 2
		s2,s1,s0 = lsl96(r2, r1, r0) // s = s * 8 <=> r * 2
		s2,s1,s0 = add96(s2, s1, s0, q2, q1, q0) // s = (s * 8) + (s * 2) <=> s*10
		pn.exponent--
		for (s2 & mask28) != 0 {
			q2,q1,q0 = lsr96(s2, s1, s0)
			binexp++
			s2 = q2
			s1 = q1
			s0 = q0
		}
	}
	for pn.exponent < 0 {
		for !((s2 & (u32(1)<<31)) != 0) {
			q2,q1,q0 = lsl96(s2, s1, s0)
			binexp--
			s2 = q2
			s1 = q1
			s0 = q0
		}
		q2 = s2 / TEN
		r1 = s2 % TEN
		r2 = (s1>>8) | (r1<<24)
		q1 = r2 / TEN
		r1 = r2 % TEN
		r2 = ((s1 & u32(0xFF))<<16) | (s0>>16) | (r1<<24)
		r0 = r2 / TEN
		r1 = r2 % TEN
		q1 = (q1<<8) | ((r0 & u32(0x00FF0000))>>16)
		q0 = r0<<16
		r2 = (s0 & u32(0xFFFF)) | (r1<<16)
		q0 |= r2 / TEN
		s2 = q2
		s1 = q1
		s0 = q0
		pn.exponent++
	}
	// C.printf("mantissa before normalization: %08x%08x%08x binexp: %d \n", s2,s1,s0,binexp)
	// normalization, the 28 bit in s2 must the leftest one in the variable
	if s2 != 0 || s1 != 0 || s0 != 0 {
		for (s2 & mask28) == 0 {
			q2,q1,q0 = lsl96(s2, s1, s0)
			binexp--
			s2 = q2
			s1 = q1
			s0 = q0
		}
	}
	// rounding if needed
	/*
	* "round half to even" algorithm
	* Example for f32, just a reminder
	*
	* If bit 54 is 0, round down
	* If bit 54 is 1
	*	If any bit beyond bit 54 is 1, round up
	*	If all bits beyond bit 54 are 0 (meaning the number is halfway between two floating-point numbers)
	*		If bit 53 is 0, round down
	*		If bit 53 is 1, round up
	*/
	/* test case 1 complete
	s2=0x1FFFFFFF
	s1=0xFFFFFF80
	s0=0x0
	*/

	/* test case 1 check_round_bit
	s2=0x18888888
	s1=0x88888880
	s0=0x0
	*/

	/* test case  check_round_bit + normalization
	s2=0x18888888
	s1=0x88888F80
	s0=0x0
	*/

	// C.printf("mantissa before rounding: %08x%08x%08x binexp: %d \n", s2,s1,s0,binexp)
	// s1 => 0xFFFFFFxx only F are rapresented
	nbit := 7
	check_round_bit := u32(1)<<u32(nbit)
	check_round_mask := u32(0xFFFFFFFF)<<u32(nbit)
	if (s1 & check_round_bit) != 0 {
		// C.printf("need round!! cehck mask: %08x\n", s1 & ~check_round_mask )
		if (s1 & ~check_round_mask) != 0 {
			// C.printf("Add 1!\n")
			s2,s1,s0 = add96(s2, s1, s0, 0, check_round_bit, 0)
		}
		else {
			// C.printf("All 0!\n")
			if (s1 & (check_round_bit<<u32(1))) != 0 {
				// C.printf("Add 1 form -1 bit control!\n")
				s2,s1,s0 = add96(s2, s1, s0, 0, check_round_bit, 0)
			}
		}
		s1 = s1 & check_round_mask
		s0 = u32(0)
		// recheck normalization
		if s2 & (mask28<<u32(1)) != 0 {
			// C.printf("Renormalize!!")
			q2,q1,q0 = lsr96(s2, s1, s0)
			binexp--
			s2 = q2
			s1 = q1
			s0 = q0
		}
	}
	// tmp := ( u64(s2 & ~mask28) << 24) | ((u64(s1) + u64(128)) >> 8)
	// C.printf("mantissa after rounding : %08x%08x%08x binexp: %d \n", s2,s1,s0,binexp)
	// C.printf("Tmp result: %016x\n",tmp)
	// end rounding
	// offset the binary exponent IEEE 754
	binexp += 1023
	if binexp > 2046 {
		if pn.negative {
			result = DOUBLE_MINUS_INFINITY
		}
		else {
			result = DOUBLE_PLUS_INFINITY
		}
	}
	else if binexp < 1 {
		if pn.negative {
			result = DOUBLE_MINUS_ZERO
		}
		else {
			result = DOUBLE_PLUS_ZERO
		}
	}
	else if s2 != 0 {
		mut q := u64(0)
		binexs2 := u64(binexp)<<52
		q = (u64(s2 & ~mask28)<<24) | ((u64(s1) + u64(128))>>8) | binexs2
		if pn.negative {
			q |= (u64(1)<<63)
		}
		result = q
	}
	return result
}

/**********************************************************************
*
* Public functions
*
**********************************************************************/

// atof64 return a f64 from a string doing a parsing operation
pub fn atof64(s string) f64 {
	mut pn := PrepNumber{
	}
	mut res_parsing := 0
	mut res  := Float64u{}

	res_parsing,pn = parser(s + ' ') // TODO: need an extra char for now
	// println(pn)
	match res_parsing {
		parser_ok {
			res.u = converter(mut pn)
		}
		parser_pzero {
			res.u = DOUBLE_PLUS_ZERO
		}
		parser_mzero {
			res.u = DOUBLE_MINUS_ZERO
		}
		parser_pinf {
			res.u = DOUBLE_PLUS_INFINITY
		}
		parser_minf {
			res.u = DOUBLE_MINUS_INFINITY
		}
		else {
		}}
	return res.f
}



