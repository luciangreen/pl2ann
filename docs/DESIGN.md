# Design

Conversion is currently split into independently loadable SWI-Prolog modules:

1. `parse.pl` reads clauses and retains variable names, file names, and source
   lines. It rejects unsupported built-ins and nested compound arguments.
2. `normalise.pl` expands disjunctions, separates positive, negative, and
   built-in literals, and checks the predicate dependency graph for
   stratification.
3. `ground.pl` combines source constants with optional domain values, applies
   explicit predicate-position type constraints to variables, evaluates
   supported comparisons and arithmetic, and enforces the atom limit.
4. `translate.pl` builds a deterministic network model from the ground
   clauses, including input/output/hidden neuron facts, weighted edges,
   recurrent links, and source trace facts.
5. `emit.pl` serializes a Prolog module. `runtime.pl` evaluates each stratum's
   weighted input, hidden, and output neurons with recurrent links to a least
   fixpoint and provides query APIs.

The initial implementation prioritizes exact, finite step-mode answers. The
runtime evaluates the explicit step-mode neuron, edge, and recurrent-link
representation. Symbolic ground rules remain in the emitted module to identify
predicate strata and support verification and extraction. The output is
independent of the source program but imports the generic runtime library.

Typed variables use the intersection of named domain values associated with
their predicate positions. Variables without a declared positional type use
the global universe. A variable-free program can still be converted without a
domain file; a program with variables needs source constants or explicit
finite domain values.
