/* Shared in-memory ABI. These records are never serialized to a .bin file. */
.equ CATALOG_DATA, 0
.equ CATALOG_COUNT, 8
.equ CATALOG_BYTES, 16
.equ CATALOG_SIZE, 24
.equ ISOTOPE_Z, 0
.equ ISOTOPE_N, 8
.equ ISOTOPE_A, 16
.equ ISOTOPE_SYMBOL, 24
.equ ISOTOPE_HALF_LIFE, 32
.equ ISOTOPE_K, 40
.equ ISOTOPE_SORT_KEY, 48
.equ ISOTOPE_RESERVED, 56
.equ ISOTOPE_SIZE, 64
