#pragma once

#include "stdint.h"

void _cdecl x86_div64_32(uint64_t dividend, uint32_t divisor, uint32_t* quotientOut, uint64_t* remainderOut);

void _cdecl x86_VideoWriteCharTeletype(char c, uint8_t page);