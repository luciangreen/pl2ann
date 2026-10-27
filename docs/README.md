# Using prolog2ann

## Requirements and quickstart

- SWI-Prolog 9.x
- Run commands from the repository root. The CLI adds this checkout's
  `prolog/` directory to SWI-Prolog's library path.

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

The query command prints `ancestor(ann,dee): true`; a ground atom not in the
least model prints `false`. Verification prints a success message when the
source and generated network have the same least model. Otherwise it reports
atoms missing from the network and unexpected network atoms, and exits with
status 1. The generated module uses the packaged `prolog2ann/runtime` library,
but does not load or need the source program.

## Typed finite domains

`domain(Type, Values)` and `range(Type, Low, High)` declare named finite value
sets. Associate predicate argument positions with those sets using
`type(Predicate/Arity, Position, Type)`. Variables constrained by multiple
typed positions use the intersection of those domains. A variable with no
typed occurrence keeps the global-universe behavior.

```prolog
% people_domain.pl
domain(person, [ann, bob]).
domain(color, [blue, red]).
range(n, 0, 4).
type(parent/2, 1, person).
type(parent/2, 2, person).
type(shade/1, 1, color).
type(number/1, 1, n).
```

In this declaration, variables in `parent/2` range over `ann` and `bob`;
variables in `shade/1` range over `blue` and `red`; and variables in `number/1`
range over integers 0 through 4. If a source variable occurs in both a
`person` and a `color` position, it can only take values present in both
domains. Facts already written in the source are retained as written.

For type-directed source verification, pass the same domain file:

```sh
swipl bin/prolog2ann.pl verify examples/ancestor.pl build/net_ancestor.pl \
  --domain examples/ancestor_domain.pl
```

The CLI verification `--domain` option and library `ann_verify/4` ensure
verification uses the same typed grounding schema as conversion. The
three-argument `ann_verify/3` remains available for networks whose domain
schema is not type-directed.

The XOR acceptance example exercises finite grounding, equality, stratified
negation, pattern queries, and source/network verification:

```sh
swipl bin/prolog2ann.pl convert examples/xor.pl --mode step \
  --out build/net_xor.pl --module net_xor
swipl bin/prolog2ann.pl query build/net_xor.pl "xor(0, 1)"
swipl bin/prolog2ann.pl query build/net_xor.pl "xor(0, 0)"
swipl bin/prolog2ann.pl verify examples/xor.pl build/net_xor.pl
```

The first query returns `true`, the second returns `false`, and verification
checks the complete finite least model.

The cyclic reachability example can be converted and checked independently:

```sh
swipl bin/prolog2ann.pl convert examples/reach.pl --mode step \
  --out build/net_reach.pl --module net_reach
swipl bin/prolog2ann.pl query build/net_reach.pl "reach(a, a)"
swipl bin/prolog2ann.pl verify examples/reach.pl build/net_reach.pl
```

The graph contains a cycle, so the least model includes `reach(a,a)`,
`reach(b,b)`, and `reach(c,c)` as well as the paths between distinct vertices.

The other supported acceptance examples can also be checked end to end:

```sh
swipl bin/prolog2ann.pl convert examples/even_odd.pl \
  --domain examples/even_odd_domain.pl --mode step \
  --out build/net_even_odd.pl --module net_even_odd
swipl bin/prolog2ann.pl query build/net_even_odd.pl "even(4)"
swipl bin/prolog2ann.pl verify examples/even_odd.pl build/net_even_odd.pl

swipl bin/prolog2ann.pl convert examples/flies.pl --mode step \
  --out build/net_flies.pl --module net_flies
swipl bin/prolog2ann.pl query build/net_flies.pl "flies(pingu)"
swipl bin/prolog2ann.pl verify examples/flies.pl build/net_flies.pl
```

The `even_odd` conversion requires its bounded integer range. The `flies`
example demonstrates stratified negation, so `flies(pingu)` is false while
`flies(tweety)` and `flies(polly)` are true. The `win` and `cut` examples are
negative cases exercised by the PlUnit suite: `win.pl` must report its
non-stratified predicate cycle, and `cut.pl` must report `unsupported_construct(!)`
with a source line. Unsupported database updates (`assert`/`retract`), collection
predicates (`findall`), I/O, meta-calls, conditionals, and compound negated
goals are also rejected as `unsupported_construct(Construct)` errors with the
source file and line. The parser diagnostic matrix is runnable as part of the
full suite with `swipl -q -s test/run_tests.pl`.

The converter accepts `--limit N` to cap the grounded Herbrand base (default
10,000 atoms) and `--steps N` to set the maximum closure rounds for each
stratum in the emitted runtime (default: base size + 1). Both values must be
positive integers. For example, use `--steps 20` before `--out` to generate a
network with a per-stratum limit of 20. If a stratum has not reached a fixpoint
within its limit, `ann_run/3` returns `Reached = false` and query predicates
raise `error(no_fixpoint(Steps), _)`.

Compound and list arguments are opt-in with `--term-depth N` (or
`term_depth(N)` in `convert_file/3` and `convert_clauses/3`). The default is
zero, which preserves function-free input. At a positive depth, the converter
generates finite ground terms from compound functors in the source, including
the list constructor, up to that nesting depth. Terms deeper than the bound in
a fixed source fact or rule are rejected with a source-located
`term_depth_exceeded(Actual, Limit)` error; substitutions that would exceed
the bound are omitted. `--term-limit N` (or `term_limit(N)` in the library
options) separately caps the initial universe values plus all constructor
candidates generated across depth layers; it defaults to 100,000. The cap is
checked before each Cartesian-product layer is allocated, and failures report
`term_generation_limit(Required, Limit)`. This construction-work budget
includes candidates later deduplicated; `--limit N` remains the separate cap
on grounded atoms. Use the same `--term-depth` value with verification, and
provide a sufficient `--term-limit` if conversion used a larger budget:

```sh
cat > build/terms.pl <<'EOF'
p(a).
p(f(X)) :- p(X).
EOF
swipl bin/prolog2ann.pl convert build/terms.pl --term-depth 2 \
  --term-limit 100000 \
  --out build/net_terms.pl --module net_terms
swipl bin/prolog2ann.pl query build/net_terms.pl "p(f(f(a)))"
swipl bin/prolog2ann.pl verify build/terms.pl build/net_terms.pl \
  --term-depth 2
```

The configured depth is applied to terms inside predicate arguments; atoms and
variables have depth zero, and each compound/list layer adds one. Constructors
not present in the source are not invented. Term generation can grow
combinatorially, especially for higher-arity constructors, so start with a
small depth. `--term-limit` bounds construction work before allocation and
`--limit` caps the resulting network's atom base.

Named domains may also supply explicit ground compound/list values:

```prolog
domain(term, [node(a), [a, b]]).
type(item/1, 1, term).
```

Convert and verify programs using these declarations with `--term-depth 2`;
the positional type restricts `item/1` variables to the listed values. The
depth bound applies to explicit domain values as well as generated terms:
`node(a)` and `[a, b]` have depth 1, and conversion rejects either value with
`term_depth_exceeded(Actual, Limit)` if the configured bound is too small.

The CLI also supports `--module NAME` to choose the generated module name.
`convert` accepts `--mode step`, `--mode sigmoid`, or `--mode tanh`. For the
sigmoid mode, `--weight auto` chooses the documented fan-in-dependent bound;
an explicit weight below the bound is rejected. Tanh mode uses bipolar
activations (`tanh(sum - threshold)`) and reads outputs as active when their
activation is above zero. Its weight defaults to `1.0`; any explicit weight
must be positive. Tanh mode preserves the step network's Boolean fixpoint.

For an independent installation of an emitted module, install `prolog2ann` as
a SWI-Prolog pack or include the package's `prolog/` directory on SWI-Prolog's
library path. Generated modules export `ann_query/2`, `ann_query_all/2`, and
`ann_run/3`. `ann_query/2` requires a ground goal and returns true or false;
`ann_query_all/2` accepts a pattern and returns its active ground instances in
standard order; `ann_run/3` returns the active atoms, number of rounds, and
whether every stratum reached a fixpoint.

To check an emitted module in a separate SWI-Prolog process without loading its
source program, first run the ancestor quickstart above, then run:

```sh
swipl -q -p library="$PWD/prolog" \
  -g "load_files('build/net_ancestor.pl', []), net_ancestor:ann_query(ancestor(ann, dee), true), halt"
```

The `-p` option points the fresh process to this checkout's runtime library.
For a pack installation, install the `prolog2ann` pack and omit `-p`; the
pack is not published as a release yet. The suite also checks that two
conversions with identical inputs produce byte-identical generated modules.

## Supported behavior

- Facts and definite clauses with variables ranging over a finite set of
  constants or explicitly bounded compound/list terms.
- Direct and mutual recursion, conjunction, and disjunction (split into
  separate clauses).
- Stratified negation as failure; negative dependency cycles are rejected and
  reported with the involved predicate indicators.
- Finite integer domains declared by `range(Name, Low, High).`; supported
  comparisons and bounded `is/2` arithmetic are evaluated before translation.
  Integer expressions accept variables, integer literals, and `+`, `-`, `*`,
  `//`, `mod`, and `rem`; unsupported arithmetic expressions are rejected with
  a source-located `unsupported_construct` error.
- Optional named domains in the form `domain(Type, [value, ...])` or
  `range(Type, Low, High)`. Positional `type(Predicate/Arity, Position, Type)`
  declarations restrict variables appearing at those predicate positions;
  constraints on a shared variable intersect. Variables without a typed
  occurrence use the global universe. Domain values can be atomic, or ground
  compound/list terms when a sufficient `--term-depth` is set.
- A configurable maximum Herbrand-base size (default 10,000).
- Optional finite compound/list grounding with `--term-depth N`; the default
  depth is zero and preserves function-free behavior. `--term-limit N` bounds
  initial universe values and constructor candidates before allocation
  (default 100,000).
- Step, sigmoid, and bipolar tanh Prolog networks with ground queries, pattern
  queries, and fixpoint step reporting, evaluated from their weighted neuron,
  edge, and recurrent-link facts. The default per-stratum limit is base size + 1;
  unsuccessful query runs raise `error(no_fixpoint(Steps), _)`.
- Inspectable input, hidden, and output neuron facts, weighted edges,
  recurrent links, and source traces mapping input/output neurons to clauses
  mentioning their atoms and hidden neurons to their originating clauses;
  optional JSON export of the selected mode.
- Source locations on parse-time unsupported-construct errors.
- Source-equivalence verification for a `network/7` term or a loaded generated
  module, returning `equivalent` or `mismatch(Missing, Unexpected)`. Use
  `ann_verify/4` or CLI `verify ... --domain FILE` for typed-domain programs.
- Step-mode extraction via `ann_extract/2`, reconstructing the network's
  represented ground clauses from either a `network/7` term or a loaded
  generated module.
- Optional runtime fixpoint step limit, set at conversion time with
  `--step-limit N` (or `step_limit(N)` in `convert_file/3` options). If omitted,
  each stratum uses the default Herbrand-base size + 1. `ann_run/3` reports
  `ReachedFixpoint = false` when the configured limit is reached, and query
  predicates raise `error(no_fixpoint(Steps), _)`.

`--limit N` is a separate conversion-time cap on the grounded Herbrand base
(default 10,000); it is not a runtime step limit. The CLI supports:

- `convert SOURCE [--domain FILE] [--mode step|sigmoid|tanh] [--weight auto|W] [--limit N] [--step-limit N] --out FILE [--module NAME] [--json FILE]`
- `query NETWORK.pl "ground_goal"`
- `verify SOURCE NETWORK.pl [--domain FILE]`

The `--json FILE` option writes a JSON object containing `mode`, `atoms`,
`neurons` (IDs, layers, activations, and thresholds), `edges` (source, target,
and weight), `recurrent` links, and source `traces`. The library also exports
`ann_export_json(+File, +Network)` for exporting a network returned by
`convert_file/3` or `convert_clauses/3`. JSON describes the selected network
mode (`step`, `sigmoid`, or `tanh`).

For example, exporting the network for the single fact `p(a).` produces this
shape:

```json
{
  "mode": "step",
  "atoms": ["p(a)"],
  "neurons": [
    {"id": "in(p(a))", "layer": "input", "activation": "linear", "threshold": 0.0},
    {"id": "out(p(a))", "layer": "output", "activation": "step", "threshold": 0.5},
    {"id": "hidden(1)", "layer": "hidden", "activation": "step", "threshold": -0.5}
  ],
  "edges": [
    {"from": "hidden(1)", "to": "out(p(a))", "weight": 1.0}
  ],
  "recurrent": [
    {"from": "out(p(a))", "to": "in(p(a))"}
  ],
  "traces": [
    {"neuron": "hidden(1)", "clause": 1, "file": "<memory>", "line": 1},
    {"neuron": "in(p(a))", "clause": 1, "file": "<memory>", "line": 1},
    {"neuron": "out(p(a))", "clause": 1, "file": "<memory>", "line": 1}
  ]
}
```

Atoms and neuron/edge identifiers are quoted Prolog term strings; numeric
weights, thresholds, clause IDs, and source lines are JSON numbers. A trace's
`clause` identifies a grounded network clause (and the corresponding hidden
neuron), not necessarily the original variable-bearing source clause.

Verification without domain options uses the finite universe represented by
the network's atom base, combined with constants in the source program. For
type-directed grounding, pass the original domain file to `ann_verify/4` or
the CLI `verify --domain` option.

The generated module exports `ann_query/2`, `ann_query_all/2`, and
`ann_run/3`, along with the inspectable neuron, edge, recurrent-link, and trace
facts. The library entry point exports `convert_file/3`, `convert_clauses/3`,
`ann_verify/3`, `ann_export_json/2`, and `ann_extract/2`.

`ann_extract(Network, Clauses)` returns ground facts and rules. The extracted
program preserves represented positive and stratified-negative rules, so it can
be passed to `convert_clauses/3` for round-trip checks. Extraction cannot recover
the original variables, clause order, comments, source locations, domain
declarations, or source formatting. `ann_extract(GeneratedModule, Clauses)` also
accepts a loaded generated step-mode module.

The library module exports `convert_file/3`, `convert_clauses/3`,
`ann_verify/3,4`, `ann_export_json/2`, and `ann_extract/2`. `convert_file/3`
accepts `domain(File)`, `out(File)`, `json(File)`, `module(Name)`,
`mode(step|sigmoid|tanh)`, `weight(auto|W)`, `limit(MaxAtoms)`, and `step_limit(MaxRounds)`.
`convert_clauses/3` accepts `domain_values(Values)`,
`domain_types([Type-Values, ...])`,
`position_types([Predicate/Arity-Position-Type, ...])`,
`mode(step|sigmoid|tanh)`, `weight(auto|W)`, and `limit(MaxAtoms)`. The limits
must be positive integers. Generated modules provide their own `ann_query/2`,
`ann_query_all/2`, and `ann_run/3` predicates;
these query APIs are not exported from the converter library module.

Example bounded input:

```prolog
domain(person, [ann, bob]).
range(n, 0, 4).
type(parent/2, 1, person).
type(parent/2, 2, person).
```

The domain file accepts `domain/2`, `range/3`, and positional `type/3`
declarations. The declared positional types constrain variables explicitly;
the converter does not infer a type from predicate names or source constants.

## Current limitations

This is an in-progress subset of `pr1.txt`, not the v1 acceptance-complete
converter. The global fallback universe is the union of source constants and
values from `domain/2` and `range/3`, extended by source compound constructors
only when `--term-depth` is positive; explicit positional declarations refine
that universe for constrained variables. Arithmetic syntax outside the
supported integer-expression operators is rejected during parsing. Nested
compound/list terms beyond the configured bound, cut, dynamic database operations, I/O,
`findall`/`bagof`/`setof`, and unsupported system built-ins are rejected. Step,
sigmoid, and bipolar tanh modes are implemented. The runtime evaluates the
emitted weighted neuron facts; symbolic ground rules remain in the module for
stratum metadata, verification, and extraction.

Unsupported meta-calls and conditional control flow are rejected explicitly as
`unsupported_construct(meta_call)` and
`unsupported_construct(conditional)`. Other unsupported system goals are
rejected as `unsupported_construct(Goal)`. Parser tests verify these errors
retain the originating file and line; run them with the complete PlUnit command
below.

Trace facts cover input and output neurons for each ground clause in which their
atom appears, and hidden neurons for their corresponding ground clause. Clause
IDs identify the clauses in the grounded network, not original variable-bearing
source clauses. `ann_extract/2` and JSON export are implemented for the current network schema;
extraction returns represented ground rules, not original source text. Sigmoid
training is implemented for per-ground-clause weights, and tanh execution is
implemented but is not trainable. The sigmoid weight bound is derived and has
not been verified against the cited CILP paper. Verification covers least-model agreement
only for programs in the supported finite-domain subset.
Consult
[`STATUS.md`](STATUS.md) for the requirement-by-requirement list.

## Sigmoid and tanh modes; training

```sh
swipl bin/prolog2ann.pl convert examples/flies.pl --mode sigmoid --weight auto \
  --out build/net_flies.pl --module net_flies
swipl bin/prolog2ann.pl query build/net_flies.pl "flies(tweety)"
```

To run the same example with bipolar tanh activation:

```sh
swipl bin/prolog2ann.pl convert examples/flies.pl --mode tanh \
  --out build/net_flies_tanh.pl --module net_flies_tanh \
  --json build/net_flies_tanh.json
swipl bin/prolog2ann.pl query build/net_flies_tanh.pl "flies(tweety)"
swipl bin/prolog2ann.pl verify examples/flies.pl build/net_flies_tanh.pl
```

The emitted module reports `network_meta(mode(tanh))`, and JSON export sets
`"mode": "tanh"`.

In Prolog: `ann_train(Network, [flies(pingu)-false, ...], Trained)` (options
`epochs(N)`, `rate(R)` via `ann_train/4`) and `ann_save(Trained, File)`. Sigmoid
outputs are thresholded at 0.5 and agree with step mode. See `DECISIONS.md` for
the weight bound and training limits.

The default tanh scale is `1.0`; a positive `--weight W` can select another
scale. Both training and `ann_agreement/3` support sigmoid mode only.

## Tests

Run the PlUnit suite from the repository root:

```sh
swipl -q -s test/run_tests.pl
```

The current suite exercises parsing, cut, unsupported arithmetic, database
updates, collection, I/O, meta-call, conditional, and compound-negation
rejection with source lines,
negative-cycle detection, the grounding-size limit, stratified negation,
mutual recursion over a bounded integer range, bounded `is/2` arithmetic and
integer comparisons, cyclic reachability through a fixpoint (including
self-reachability), emitted-module queries and conversion output, JSON export
and its network fields, the optional runtime step limit,
input/hidden/output neuron trace facts, source/network equivalence and mismatch
reporting, and extraction round trips for recursion, stratified negation, and
generated modules. A fixed random seed also generates and verifies 200 bounded
Datalog programs using at most six unary predicates and five constants; the
generated rules include a positive self-cycle and stratified negation. The suite
also verifies complete least-model agreement for the
`ancestor`, `reach`, `even_odd`, `xor`, and `flies` acceptance examples, and
checks rejection of the checked-in `win` non-stratified example. Run all current
PlUnit tests with the command above. The ancestor quickstart exercises
conversion, generated-module querying, source/network verification, and JSON
generation; the `flies`, `even_odd`, and `reach` examples exercise stratified
negation, bounded mutual recursion, and cyclic recursive closure respectively.
The `xor` example exercises stratified negation and verifies all four input
pairs through the finite least model.

The automated tests are in `test/test_prolog2ann.pl`. These named tests map the
implemented features to the checks run by the command above:

| Feature area | Tests |
| --- | --- |
| Parsing, unsupported syntax, and stratification | `parse_example`, `reject_cut_with_source_line`, `reject_unsupported_construct_families_with_source_lines`, `reject_unsupported_construct_after_first_clause_with_source_line`, `reject_unsupported_arithmetic_with_source_line`, `reject_non_stratified_negation`, `reject_win_acceptance_example` |
| Finite grounding, typed/integer domains, bounded terms, and limits | `grounding_limit`, `finite_domain_required_for_variables`, `typed_domains_restrict_and_intersect_variables`, `mutual_recursion_with_integer_range`, `bounded_arithmetic_and_comparisons`, `compound_terms_respect_configured_depth`, `higher_arity_constructors_generate_bounded_terms`, `combinatorial_term_generation_respects_budget`, `list_terms_are_bounded_by_depth`, `compound_values_in_named_domains`, `compound_domain_values_respect_configured_depth`, `compound_term_depth_overflow_has_source_location` |
| Neurons, weighted execution, and source traces | `translation_includes_weighted_neurons`, `weighted_network_facts_drive_runtime`, `neuron_traceability_covers_all_layers` |
| Queries, recursion, and negation | `stratified_negation_and_query`, `xor_acceptance_and_equivalence`, `cyclic_reachability_reaches_fixpoint` |
| Emission, JSON, and step limits | `convert_file_creates_output`, `export_json_network_representation`, `convert_file_creates_json_output`, `configured_runtime_step_limit` |
| Reproducible packaging and independent runtime loading | `generated_module_is_deterministic`, `generated_module_runs_in_fresh_process_without_source` |
| Verification, extraction, and broad equivalence | `verify_equivalent_emitted_network`, `verify_reports_model_difference`, `extract_round_trip_ancestor`, `extract_round_trip_stratified_negation`, `extract_from_generated_module`, `acceptance_examples_verify_least_models`, `randomized_programs_verify_least_models` |
| Sigmoid training and continuous activations | `sigmoid_matches_step_on_examples`, `sigmoid_module_emits_and_queries`, `sigmoid_training_repairs_corrupted_weight`, `tanh_matches_step_on_examples`, `tanh_module_and_json_report_mode`, `tanh_rejects_nonpositive_weight` |

The GitHub Actions workflow runs this same PlUnit command on Ubuntu after
installing the available SWI-Prolog package. You can run the suite locally with
the command above; the conversion, query, verification, and JSON commands
earlier in this guide are additional end-to-end checks.

Run the ancestor example end to end using the quickstart. To impose a runtime
limit, add `--step-limit 1` to `convert`; then call the generated module's
`ann_run(Atoms, Steps, Reached)` to inspect whether its fixpoint was reached.
The `verify` command accepts the source file and generated network file in
that order. The current extraction API can be exercised from the Prolog top
level after loading `prolog/prolog2ann.pl` and generating or converting a
network: call `prolog2ann:ann_extract(Network, Clauses)` and then
`prolog2ann:convert_clauses(Clauses, [], RoundTripNetwork)`.
Randomized equivalence is covered
by the deterministic 200-program property test above. See
[`STATUS.md`](STATUS.md) for the current requirement-by-requirement status and
the remaining milestones.
