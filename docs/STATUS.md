# Implementation status against `pr1.txt`

The converter supports bipolar `tanh` execution alongside step and sigmoid
modes. The project remains an in-progress subset of the v1 brief; passing
current tests does not mean all acceptance requirements are complete.

| Requirement | Status |
| --- | --- |
| FR-1 | Implemented — `domain/2` and `range/3` define named sets, and `type(Predicate/Arity, Position, Type)` constrains variables at predicate positions; untyped variables use the global universe |
| FR-2 | Partial — unsupported constructs are rejected with source locations; compound/list terms are accepted with an explicit depth bound, but unsupported syntax diagnostics are not exhaustive |
| FR-3 | Implemented — negative dependency cycles report predicate indicators |
| FR-4 | Implemented — grounded atom limit defaults to 10,000 and is configurable |
| FR-5 | Implemented — exact step, scaled sigmoid, and bipolar tanh modes |
| FR-6 | Partial — generated modules run without source in a fresh process, but require the `prolog2ann/runtime` library; the pack is not yet published |
| FR-7 | Implemented for emitted networks — ground queries |
| FR-8 | Implemented for emitted networks — matching active atoms |
| FR-9 | Implemented for the supported subset — stratified weighted-neuron fixpoints and configurable step limits |
| FR-10 | Partial — sigmoid backpropagation and saving work on ground-network weights; training does not generalise across instances of a source clause |
| FR-11 | Implemented — extracts represented ground rules from step-mode network terms or loaded generated modules |
| FR-12 | Implemented for grounded network clauses — input, hidden, and output traces include source file and line |
| FR-13 | Implemented — JSON exports atoms, neurons, edges, recurrent links, and traces for step, sigmoid, and tanh modes |

## Remaining work

1. Finish diagnostics for all unsupported syntax. Bounded-term generation now
   has a configurable `--term-limit` budget checked before each depth layer;
   tests cover combinatorial growth and higher-arity constructors. Explicit
   compound/list domain values are checked against `--term-depth`.
2. Verify the sigmoid weight bound against the cited CILP paper. The current
   fan-in-dependent bound is derived and explicitly not claimed as the published
   formula. Tanh execution is implemented, but tanh training is not.
3. Complete the training acceptance criterion for held-out examples and
   cross-instance generalisation. Current training updates individual grounded
   clause weights.
4. Finish release readiness: publish/installable pack versioning and archive
   packaging. Generated output is now checked for byte-for-byte determinism,
   and a fresh-process smoke test verifies it runs without the source file
   when the runtime library is available.

## Tests and examples

Run the full PlUnit suite from the repository root:

```sh
swipl -q -s test/run_tests.pl
```

Run the documented ancestor conversion, query, and equivalence check:

```sh
mkdir -p build
swipl bin/prolog2ann.pl convert examples/ancestor.pl \
  --domain examples/ancestor_domain.pl --mode step \
  --out build/net_ancestor.pl --module net_ancestor \
  --json build/net_ancestor.json
swipl bin/prolog2ann.pl query build/net_ancestor.pl "ancestor(ann, dee)"
swipl bin/prolog2ann.pl verify examples/ancestor.pl build/net_ancestor.pl \
  --domain examples/ancestor_domain.pl
```

`--domain FILE` may also be supplied to `verify` when conversion used
type-directed domains. The domain file supports declarations such as
`type(parent/2, 1, person).`; see [`README.md`](README.md#typed-finite-domains)
for the syntax and semantics.

Bounded compound/list conversion accepts `--term-depth N` and
`--term-limit N` (default 100,000 generated candidates plus initial universe
values). The term budget is checked before allocating each constructor layer;
`--limit N` separately caps grounded atoms. Tests
`higher_arity_constructors_generate_bounded_terms` and
`combinatorial_term_generation_respects_budget` cover these bounds.

For another supported activation, repeat conversion with
`--mode sigmoid --weight auto` or `--mode tanh`; sigmoid rejects a supplied
weight below its current derived bound, while tanh accepts any positive
weight and defaults to `1.0`. The suite checks step/sigmoid/tanh least-model
agreement on the five acceptance examples (`ancestor`, `reach`, `even_odd`,
`xor`, and `flies`), plus parsing and diagnostics, finite grounding limits,
recursion, negation, JSON and module emission, training, extraction,
verification, deterministic module output, fresh-process module loading, and
200 deterministic randomized equivalence cases. See
[`README.md`](README.md) for runnable commands and the feature-to-test index.

The acceptance cases in `pr1.txt` that are not represented by the current
supported subset must not be considered complete merely because this suite
passes. Bounded term support uses `--term-depth N` and is tested for recursive
compounds and lists, higher-arity constructors, combinatorial generation
limits, and rejection of explicit domain values that exceed the configured
depth. Exhaustive diagnostics for unsupported syntax, the cited sigmoid-bound
proof, held-out training generalisation, and release packaging remain open.
