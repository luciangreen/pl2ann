# Design decisions

## Finite and typed domains

`domain(Type, Values)` and `range(Type, Low, High)` declarations name value
sets. The domain file associates a type with predicate argument positions
using `type(Predicate/Arity, Position, Type)`. Variables collect constraints
from all their occurrences in a clause and use the intersection of those
domains; untyped variables use the sorted global union of source constants and
domain values. This explicit mapping avoids inferring types from predicate
names or data.

Facts and other source terms already ground remain in the network even when
their constants are outside a declared argument type. The type restriction
applies to variable assignments, not to validation or filtering of source
facts.

## Bounded compound and list terms

Compound and list values are generated only from functors already present in
predicate arguments in the source. `term_depth(N)` (CLI `--term-depth N`)
bounds nesting, counting atoms and variables as depth zero and each compound
layer as one; the default is zero for backwards-compatible function-free
grounding. Fixed source structures deeper than the bound are errors with their
source location, while substitutions that would produce deeper atoms are
excluded. The Herbrand-base limit remains a separate cap on represented atoms.
This is a finite syntactic term universe, not unrestricted Prolog term
evaluation.

## Unsupported terms

Terms outside the configured depth and unsupported built-ins are rejected
rather than partially grounded.

Supported arithmetic expressions are limited to integer literals, variables,
and `+`, `-`, `*`, `//`, `mod`, and `rem`. Other expression shapes are rejected
during parsing with the source location instead of being treated as a failed
grounding assignment.

## Verification universe

`ann_verify/3` derives values from the network's ground atom base and combines
them with constants in the source before grounding. Type-directed verification
uses `ann_verify/4` with the original `domain(File)` option; the CLI exposes the
same option as `verify SOURCE NETWORK.pl --domain FILE`.

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

## Bipolar tanh mode

`--mode tanh` scales every edge weight and hidden/output threshold by a positive
W and labels those neurons with the bipolar `tanh` activation. The runtime
classifies an activation as active when it is above zero, which is equivalent
to comparing the pre-activation weighted sum with the scaled threshold. This
preserves the step-mode least model for every positive scale. `--weight auto`
uses W = 1.0; explicit non-positive values are rejected. Tanh mode is not
currently trainable, and no separate saturation guarantee is claimed.
