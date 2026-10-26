# Design decisions

## Current finite universe

All variables are grounded over the sorted union of atomic constants found in
the source and values declared with `domain/2` or `range/3`. The `Type` and
`Name` arguments are retained as declaration labels but are not associated
with predicate positions yet. This is the simplest deterministic finite
universe until typed-domain inference is specified.

## Unsupported terms

Nested compound and list arguments are rejected rather than partially
grounded. The v1 brief allows those terms only with a configured depth/length
bound, and no such bound is implemented yet.

Supported arithmetic expressions are limited to integer literals, variables,
and `+`, `-`, `*`, `//`, `mod`, and `rem`. Other expression shapes are rejected
during parsing with the source location instead of being treated as a failed
grounding assignment.

## Verification universe

`ann_verify/3` does not take a domain file. It derives values from the network's
ground atom base and combines them with constants in the source before
grounding. This checks the source against the exact finite base represented by
the generated network without requiring the original domain file.

## Sigmoid weight bound

Sigmoid mode is not enabled until its bound can be attributed accurately.
Under the logistic activation and the brief's single-neuron threshold
\((m-\tfrac12)W\), the AND-neuron margin is \(W/2\), so achieving error at most
\(\epsilon\) requires \(W \ge 2\ln((1-\epsilon)/\epsilon)\). This is a derived
saturation bound under those assumptions, not a verified formula from
d'Avila Garcez and Zaverucha (1999); it does not establish a bound for an
entire recurrent network with OR aggregation.

## Sigmoid mode and training (implemented)

`--mode sigmoid` scales every weight and hidden/output threshold of the step
network by W and marks hidden and output neurons `sigmoid`. With `--weight
auto` (default) W is the minimum bound rounded up to two decimals; a smaller
user-supplied W is rejected with `error(weight_below_bound(W, Min), _)`, and the
chosen W is logged. The bound is the derived one above, made fan-in dependent:
with k the largest clause body size or number of clauses sharing a head,
\(\epsilon = 1/(2(k+1))\) and \(W = 2\ln((1-\epsilon)/\epsilon)\). It is not the
published CILP formula and has not been checked against the paper.

The runtime reads sigmoid neurons out at 0.5 (equivalently, weighted sum above
threshold), so sigmoid fixpoints equal step-mode fixpoints; this is tested on
all five acceptance examples. Training (`ann_train/3,4`) is backpropagation of
the cross-entropy error of an atom's output neuron through its hidden neurons,
using the network's current thresholded model as input (one T_P step). It
stops early when all examples are classified correctly. Weights belong to
ground clauses, so training does not generalise to other ground instances of
the same source clause. `ann_extract/2` remains step-mode only.
