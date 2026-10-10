# systolic-array-matmul

[![simulation](https://github.com/me-in-git/systolic-array-matmul/actions/workflows/sim.yml/badge.svg)](https://github.com/me-in-git/systolic-array-matmul/actions/workflows/sim.yml)

Parameterized NxN output-stationary systolic array for matrix multiply, in SystemVerilog.

- A flows left to right, B flows top to bottom, each PE accumulates one C element
- inputs are skewed so A[i][k] and B[k][j] meet at PE(i,j) on the same cycle
- default N=4, signed 8-bit inputs, 18-bit accumulators
- `done` goes high 3N cycles after `start` (12 at N=4)

Load A row by row (`load_a`) and B column by column (`load_b`), pulse `start`, read `c_data` when `done` pulses.

## Tests

```
make test      # N=4
make sweep     # N=2,3,4,5,6,8
```

Results are compared against a software matrix multiply.

```
N=2: 6 cycles from start, 32 checks
N=4: 12 cycles from start, 128 checks
N=8: 24 cycles from start, 512 checks
```
