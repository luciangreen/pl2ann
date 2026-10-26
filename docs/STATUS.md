# Implementation status against `pr1.txt`

The converter supports bipolar `tanh` execution alongside step and sigmoid
modes. The project remains an in-progress subset of the v1 brief; passing
current tests does not mean all acceptance requirements are complete.

| Requirement | Status |
| --- | --- |
| FR-1 | Partial — source and optional `domain/2`/`range/3` files are accepted, but all values share one grounding universe |
| FR-2 | Partial — unsupported constructs are rejected with source locations; bounded lists/compound terms are not supported |
| FR-3 | Implemented — negative dependency cycles report predicate indicators |
| FR-4 | Implemented — grounded atom limit defaults to 10,000 and is configurable |
| FR-5 | Implemented — exact step, scaled sigmoid, and bipolar tanh modes |
| FR-6 | Partial — emitted modules do not need the source file, but use the installed `prolog2ann/runtime` package |
| FR-7 | Implemented for emitted networks — ground queries |
| FR-8 | Implemented for emitted networks — matching active atoms |
| FR-9 | Implemented for the supported subset — stratified weighted-neuron fixpoints and configurable step limits |
| FR-10 | Partial — sigmoid backpropagation and saving work on ground-network weights; training does not generalise across instances of a source clause |
| FR-11 | Implemented — extracts represented ground rules from step-mode network terms or loaded generated modules |
| FR-12 | Implemented for grounded network clauses — input, hidden, and output traces include source file and line |
| FR-13 | Implemented — JSON exports atoms, neurons, edges, recurrent links, and traces for step, sigmoid, and tanh modes |

## Remaining work

1. Implement type-aware variable domains and range/binding semantics; currently
   all declared/source constants are combined into one universe.
2. Add bounded list and compound-term grounding, and finish diagnostics for all
   unsupported syntax.
3. Verify the sigmoid weight bound against the cited CILP paper. The current
   fan-in-dependent bound is derived and explicitly not claimed as the published
   formula. Tanh execution is implemented, but tanh training is not.
4. Complete the training acceptance criterion for held-out examples and
   cross-instance generalisation. Current training updates individual grounded
   clause weights.
5. Finish release readiness: pack/version metadata, deterministic packaging,
   and end-to-end checks for an independently installed generated module.

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
swipl bin/prolog2ann.pl verify examples/ancestor.pl build/net_ancestor.pl
```

For another supported activation, repeat conversion with
`--mode sigmoid --weight auto` or `--mode tanh`; sigmoid rejects a supplied
weight below its current derived bound, while tanh accepts any positive
weight and defaults to `1.0`. The suite checks step/sigmoid/tanh least-model
agreement on the five acceptance examples (`ancestor`, `reach`, `even_odd`,
`xor`, and `flies`), plus parsing and diagnostics, finite grounding limits,
recursion, negation, JSON and module emission, training, extraction,
verification, and 200 deterministic randomized equivalence cases. See
[`README.md`](README.md) for runnable commands and the feature-to-test index.

The acceptance cases in `pr1.txt` that are not represented by the current
supported subset must not be considered complete merely because this suite
passes. In particular, typed domains, bounded compound terms, the cited
sigmoid-bound proof, and held-out training generalisation remain open.
