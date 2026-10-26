:- module(test_prolog2ann, []).

:- use_module('../prolog/prolog2ann').
:- use_module('../prolog/prolog2ann/parse').
:- use_module('../prolog/prolog2ann/normalise').
:- use_module('../prolog/prolog2ann/ground').
:- use_module('../prolog/prolog2ann/translate').
:- use_module('../prolog/prolog2ann/emit').
:- use_module('../prolog/prolog2ann/json_export').
:- use_module('../prolog/prolog2ann/runtime').
:- use_module(library(plunit)).
:- use_module(library(http/json)).
:- use_module(library(lists)).
:- use_module(library(random)).

:- dynamic examples_directory/1.

:- prolog_load_context(directory, TestDirectory),
   directory_file_path(TestDirectory, '../examples', ExamplesDirectory),
   absolute_file_name(ExamplesDirectory, AbsoluteExamples),
   assertz(examples_directory(AbsoluteExamples)).

:- begin_tests(prolog2ann).

test(parse_example) :-
    test_prolog2ann:example(ancestor, File),
    prolog2ann_parse:parse_file(File, Clauses),
    length(Clauses, 9).

test(sigmoid_matches_step_on_examples, [forall(member(Name, [ancestor, reach, even_odd, xor, flies]))]) :-
    test_prolog2ann:example(Name, File),
    example_domain(Name, Options0),
    prolog2ann:convert_file(File, [mode(step)|Options0], Step),
    prolog2ann:convert_file(File, [mode(sigmoid)|Options0], Sigmoid),
    prolog2ann_runtime:run_network_term(Step, StepModel, _, true),
    prolog2ann_runtime:run_network_term(Sigmoid, SigmoidModel, _, true),
    assertion(StepModel == SigmoidModel).

test(sigmoid_weight_below_bound_rejected) :-
    prolog2ann:convert_clauses([p(a)], [], Step),
    prolog2ann_train:sigmoid_min_weight(Step, Min),
    assertion(Min > 0),
    catch(prolog2ann:convert_clauses([p(a)], [mode(sigmoid), weight(0.1)], _),
          error(weight_below_bound(_, _), _), true),
    prolog2ann:convert_clauses([p(a)], [mode(sigmoid), weight(Min)], Net),
    assertion(Net = network(_, _, _, _, _, _, _)).

test(sigmoid_module_emits_and_queries) :-
    tmp_file(prolog2ann_sigmoid, Base),
    atom_concat(Base, '.pl', File),
    prolog2ann:convert_clauses([p(a), (q(X) :- p(X), \+ r(X)), r(b)],
                               [mode(sigmoid)], Net),
    prolog2ann:ann_save(Net, File),
    setup_call_cleanup(
        use_module(File, []),
        ( file_base_name(Base, Module),
          Module:ann_query(q(a), true),
          Module:ann_query(q(b), false),
          assertion(Module:network_meta(mode(sigmoid)))
        ),
        delete_file(File)).

test(sigmoid_training_repairs_corrupted_weight, [nondet]) :-
    Birds = [b1, b2, b3, b4, b5, b6, b7, b8],
    findall(bird(B), member(B, Birds), BirdFacts),
    Clauses = [penguin(b3), (flies(X) :- bird(X), \+ penguin(X))|BirdFacts],
    prolog2ann:convert_clauses(Clauses, [mode(sigmoid)], Net0),
    Net0 = network(Atoms, Rules, Strata, Traces, Neurons, Edges0, Rec),
    Corrupt = edge(in(penguin(b3)), Hidden, Neg),
    memberchk(Corrupt, Edges0),
    Neg < 0,
    Flipped is -Neg,
    select(Corrupt, Edges0, Others),
    Bad = network(Atoms, Rules, Strata, Traces, Neurons,
                  [edge(in(penguin(b3)), Hidden, Flipped)|Others], Rec),
    Labels = [flies(b3)-false, flies(b1)-true, flies(b2)-true, flies(b4)-true,
              flies(b5)-true, flies(b6)-true, flies(b7)-true, flies(b8)-true,
              penguin(b3)-true, penguin(b1)-false, penguin(b2)-false,
              penguin(b4)-false, bird(b1)-true, bird(b2)-true, bird(b3)-true,
              bird(b4)-true, bird(b5)-true, bird(b6)-true, bird(b7)-true,
              bird(b8)-true],
    prolog2ann_train:ann_agreement(Bad, Labels, Before),
    assertion(Before < 1.0),
    prolog2ann:ann_train(Bad, Labels, Trained),
    prolog2ann_train:ann_agreement(Trained, Labels, After),
    assertion(After =:= 1.0).

test(train_rejects_step_network) :-
    prolog2ann:convert_clauses([p(a)], [], Net),
    catch(prolog2ann:ann_train(Net, [p(a)-true], _),
          error(domain_error(sigmoid_network, step), _), true).

test(reject_cut_with_source_line) :-
    test_prolog2ann:example(cut, File),
    catch(prolog2ann_parse:parse_file(File, _), Error, true),
    assertion(nonvar(Error)),
    assertion(Error = error(unsupported_construct(!), file(File, 1))).

test(reject_unsupported_arithmetic_with_source_line) :-
    tmp_file(prolog2ann_arithmetic, File),
    setup_call_cleanup(
        open(File, write, Stream, [encoding(utf8)]),
        ( write(Stream, 'p(X) :- X is foo(1).'), nl(Stream) ),
        close(Stream)),
    setup_call_cleanup(
        true,
        ( catch(prolog2ann_parse:parse_file(File, _), Error, true),
          assertion(nonvar(Error)),
          assertion(Error = error(unsupported_construct(_), file(File, 1)))
        ),
        delete_file(File)).

test(reject_non_stratified_negation) :-
    Parsed = [ clause(p(X), \+ q(X), [], sample, 1),
               clause(q(X), p(X), [], sample, 2)
             ],
    catch(prolog2ann_normalise:normalise(Parsed, _), Error, true),
    assertion(nonvar(Error)),
    assertion(Error = error(non_stratified_negation(Cycle), file(sample, 1))),
    assertion(memberchk(p/1, Cycle)).

test(reject_win_acceptance_example) :-
    test_prolog2ann:example(win, File),
    prolog2ann_parse:parse_file(File, Parsed),
    catch(prolog2ann_normalise:normalise(Parsed, _), Error, true),
    assertion(Error = error(non_stratified_negation([win/1]), file(File, 4))).

test(acceptance_examples_verify_least_models) :-
    forall(member(Name-Domain,
                 [ ancestor-ancestor_domain,
                   reach-none,
                   even_odd-even_odd_domain,
                   xor-none,
                   flies-none
                 ]),
           test_prolog2ann:verify_example(Name, Domain)).

test(randomized_programs_verify_least_models) :-
    set_random(seed(20261021)),
    forall(between(1, 200, Seed),
           test_prolog2ann:verify_random_program(Seed)).

test(grounding_limit) :-
    test_prolog2ann:example(ancestor, File),
    test_prolog2ann:example(ancestor_domain, Domain),
    prolog2ann_parse:parse_file(File, Parsed),
    prolog2ann_normalise:normalise(Parsed, Normalised),
    prolog2ann_ground:read_domain(Domain, Values),
    catch(prolog2ann_ground:ground_program(Normalised, Values, _, 1, _), Error, true),
    assertion(nonvar(Error)),
    assertion(Error = error(herbrand_base_limit(_, 1), _)).

test(finite_domain_required_for_variables) :-
    Parsed = [clause(p(X), true, [], sample, 1)],
    prolog2ann_normalise:normalise(Parsed, Normalised),
    catch(prolog2ann_ground:ground_program(Normalised, [], _, 10000, _), Error, true),
    assertion(nonvar(Error)),
    assertion(Error = error(finite_domain_required, _)).

test(translation_includes_weighted_neurons) :-
    prolog2ann:convert_clauses([p(a), (q(X) :- p(X))],
                               [domain_values([a])],
                               network(_, _, _, _, Neurons, Edges, Recurrent)),
    assertion(memberchk(neuron(hidden(2), hidden, step, 0.5), Neurons)),
    assertion(memberchk(edge(in(p(a)), hidden(2), 1.0), Edges)),
    assertion(memberchk(edge(hidden(2), out(q(a)), 1.0), Edges)),
    assertion(memberchk(recurrent(out(p(a)), in(p(a))), Recurrent)).

test(weighted_network_facts_drive_runtime) :-
    tmp_file(weighted_runtime_probe, Output),
    test_prolog2ann:write_weighted_probe(Output),
    load_files(Output, []),
    setup_call_cleanup(
        true,
        ( prolog2ann_runtime:run_network(
              weighted_runtime_probe, Atoms, _, true),
          assertion(Atoms == [p(a)]),
          prolog2ann_runtime:ann_query(
              weighted_runtime_probe, q(a), false)
        ),
        ( unload_file(Output),
          ( exists_file(Output) -> delete_file(Output) ; true )
        )).

test(neuron_traceability_covers_all_layers) :-
    prolog2ann:convert_clauses([p(a), (q(X) :- p(X))],
                               [domain_values([a])],
                               network(_, _, _, Traces, Neurons, _, _)),
    forall(member(neuron(Neuron, _, _, _), Neurons),
           assertion(member(trace(Neuron, _, '<memory>', 1), Traces))),
    assertion(memberchk(trace(in(p(a)), 1, '<memory>', 1), Traces)),
    assertion(memberchk(trace(out(p(a)), 1, '<memory>', 1), Traces)),
    assertion(memberchk(trace(in(p(a)), 2, '<memory>', 1), Traces)),
    assertion(memberchk(trace(out(q(a)), 2, '<memory>', 1), Traces)).

test(stratified_negation_and_query) :-
    test_prolog2ann:example(flies, File),
    prolog2ann_parse:parse_file(File, Parsed),
    prolog2ann_normalise:normalise(Parsed, Normalised),
    prolog2ann_ground:ground_program(Normalised, [], Ground, 10000, Atoms),
    prolog2ann_translate:translate(Ground, Atoms, Network),
    test_prolog2ann:temporary_network(Network, Module, Path),
    setup_call_cleanup(
        true,
        ( prolog2ann_runtime:ann_query(Module, flies(tweety), true),
          prolog2ann_runtime:ann_query(Module, flies(pingu), false),
          prolog2ann_runtime:ann_query_all(Module, flies(X), Solutions),
          assertion(Solutions == [flies(polly), flies(tweety)]),
          assertion(var(X))
        ),
        ( unload_file(Path), delete_file(Path) )).

test(xor_acceptance_and_equivalence) :-
    test_prolog2ann:example(xor, File),
    prolog2ann:convert_file(File, [], Network),
    prolog2ann:ann_verify(File, Network, equivalent),
    test_prolog2ann:temporary_network(Network, Module, Path),
    setup_call_cleanup(
        true,
        ( prolog2ann_runtime:ann_query(Module, xor(0, 1), true),
          prolog2ann_runtime:ann_query(Module, xor(1, 0), true),
          prolog2ann_runtime:ann_query(Module, xor(0, 0), false),
          prolog2ann_runtime:ann_query(Module, xor(1, 1), false),
          prolog2ann_runtime:ann_query_all(Module, xor(X, Y), Solutions),
          assertion(var(X)),
          assertion(var(Y)),
          assertion(Solutions == [xor(0, 1), xor(1, 0)])
        ),
        ( unload_file(Path), delete_file(Path) )).

test(mutual_recursion_with_integer_range) :-
    test_prolog2ann:example(even_odd, File),
    test_prolog2ann:example(even_odd_domain, Domain),
    prolog2ann_parse:parse_file(File, Parsed),
    prolog2ann_normalise:normalise(Parsed, Normalised),
    prolog2ann_ground:read_domain(Domain, Values),
    prolog2ann_ground:ground_program(Normalised, Values, Ground, 10000, Atoms),
    prolog2ann_translate:translate(Ground, Atoms, Network),
    test_prolog2ann:temporary_network(Network, Module, Path),
    setup_call_cleanup(
        true,
        ( prolog2ann_runtime:ann_query(Module, even(4), true),
          prolog2ann_runtime:ann_query(Module, odd(3), true),
          prolog2ann_runtime:ann_query(Module, even(3), false)
        ),
        ( unload_file(Path), delete_file(Path) )).

test(bounded_arithmetic_and_comparisons) :-
    prolog2ann:convert_clauses(
        [ (calculated(X) :- (X is 2 + 2, X =< 4)),
          (eligible(Y) :- (Y < 3, Y =\= 1))
        ],
        [domain_values([0, 1, 2, 3, 4])],
        Network),
    test_prolog2ann:temporary_network(Network, Module, Path),
    setup_call_cleanup(
        true,
        ( prolog2ann_runtime:ann_query(Module, calculated(4), true),
          prolog2ann_runtime:ann_query(Module, calculated(3), false),
          prolog2ann_runtime:ann_query(Module, eligible(0), true),
          prolog2ann_runtime:ann_query(Module, eligible(1), false),
          prolog2ann_runtime:ann_query(Module, eligible(2), true),
          prolog2ann_runtime:ann_query(Module, eligible(4), false)
        ),
        ( unload_file(Path), delete_file(Path) )).

test(cyclic_reachability_reaches_fixpoint) :-
    test_prolog2ann:example(reach, File),
    prolog2ann:convert_file(File, [], Network),
    prolog2ann:ann_verify(File, Network, equivalent),
    test_prolog2ann:temporary_network(Network, Module, Path),
    setup_call_cleanup(
        true,
        ( prolog2ann_runtime:ann_query(Module, reach(a, a), true),
          prolog2ann_runtime:ann_query(Module, reach(a, c), true),
          prolog2ann_runtime:ann_query(Module, reach(d, d), false),
          prolog2ann_runtime:run_network(Module, _, Steps, true),
          Network = network(Atoms, _, _, _, _, _, _),
          length(Atoms, BaseSize),
          assertion(Steps =< BaseSize + 1),
          prolog2ann_runtime:ann_query_all(Module, reach(a, Y), Solutions),
          assertion(var(Y)),
          assertion(Solutions == [reach(a, a), reach(a, b), reach(a, c)])
        ),
        ( unload_file(Path), delete_file(Path) )).

test(convert_file_creates_output) :-
    test_prolog2ann:example(ancestor, File),
    test_prolog2ann:example(ancestor_domain, Domain),
    tmp_file(prolog2ann, Output),
    setup_call_cleanup(
        true,
        ( prolog2ann:convert_file(File, [domain(Domain), out(Output), module(test_generated)], _),
          exists_file(Output),
          setup_call_cleanup(
              true,
              ( load_files(Output, []),
                test_generated:ann_query(ancestor(ann, dee), true)
              ),
              unload_file(Output))
        ),
        ( exists_file(Output) -> delete_file(Output) ; true )).

test(export_json_network_representation) :-
    prolog2ann:convert_clauses([p(a), (q(X) :- p(X))],
                               [domain_values([a])],
                               Network),
    tmp_file(prolog2ann_json, Output),
    setup_call_cleanup(
        true,
        ( prolog2ann:ann_export_json(Output, Network),
          setup_call_cleanup(
              open(Output, read, Stream, [encoding(utf8)]),
              json_read_dict(Stream, Json),
              close(Stream)),
          assertion(Json.mode == "step"),
          assertion(member(_{id: "out(q(a))",
                             layer: "output",
                             activation: "step",
                             threshold: 0.5},
                           Json.neurons)),
          assertion(member(_{from: "in(p(a))",
                             to: "hidden(2)",
                             weight: 1.0},
                           Json.edges)),
          assertion(member(_{from: "out(p(a))",
                             to: "in(p(a))"},
                           Json.recurrent)),
          assertion(memberchk(_{neuron: "hidden(2)",
                                clause: 2,
                                file: "<memory>",
                               line: 1},
                              Json.traces)),
          assertion(memberchk(_{neuron: "in(p(a))",
                               clause: 1,
                               file: "<memory>",
                               line: 1},
                              Json.traces)),
          assertion(memberchk(_{neuron: "out(q(a))",
                               clause: 2,
                               file: "<memory>",
                               line: 1},
                              Json.traces))
        ),
        ( exists_file(Output) -> delete_file(Output) ; true )).

test(convert_file_creates_json_output) :-
    test_prolog2ann:example(ancestor, File),
    test_prolog2ann:example(ancestor_domain, Domain),
    tmp_file(prolog2ann_json, Output),
    setup_call_cleanup(
        true,
        ( prolog2ann:convert_file(File, [domain(Domain), json(Output)], _),
          exists_file(Output),
          setup_call_cleanup(
              open(Output, read, Stream, [encoding(utf8)]),
              json_read_dict(Stream, Json),
              close(Stream)),
          assertion(Json.mode == "step"),
          assertion(Json.neurons \= [])
        ),
        ( exists_file(Output) -> delete_file(Output) ; true )).

test(configured_runtime_step_limit) :-
    test_prolog2ann:example(ancestor, File),
    test_prolog2ann:example(ancestor_domain, Domain),
    tmp_file(prolog2ann, Output),
    setup_call_cleanup(
        true,
        ( prolog2ann:convert_file(
              File,
              [domain(Domain), out(Output), module(test_generated_limited),
               step_limit(1)],
              _),
          load_files(Output, []),
          test_generated_limited:ann_run(_, Steps, Reached),
          assertion(Steps =:= 1),
          assertion(Reached == false),
          catch(test_generated_limited:ann_query(ancestor(ann, dee), _),
                Error,
                true),
          assertion(nonvar(Error)),
          assertion(Error = error(no_fixpoint(1), _))
        ),
        ( unload_file(Output),
          ( exists_file(Output) -> delete_file(Output) ; true )
        )).

test(verify_equivalent_emitted_network) :-
    test_prolog2ann:example(ancestor, File),
    test_prolog2ann:example(ancestor_domain, Domain),
    tmp_file(prolog2ann, Output),
    setup_call_cleanup(
        true,
        ( prolog2ann:convert_file(
              File,
              [domain(Domain), out(Output), module(verified_ancestor)],
              _),
          load_files(Output, []),
          prolog2ann:ann_verify(File, verified_ancestor, Result),
          assertion(Result == equivalent)
        ),
        ( unload_file(Output),
          ( exists_file(Output) -> delete_file(Output) ; true )
        )).

test(verify_reports_model_difference) :-
    test_prolog2ann:example(ancestor, File),
    prolog2ann:convert_clauses([p(a)], [], Network),
    prolog2ann:ann_verify(File, Network, Result),
    Result = mismatch(Missing, Unexpected),
    assertion(Missing \= []),
    assertion(memberchk(p(a), Unexpected)).

test(extract_round_trip_ancestor) :-
    test_prolog2ann:example(ancestor, File),
    test_prolog2ann:example(ancestor_domain, Domain),
    prolog2ann:convert_file(File, [domain(Domain)], Network),
    prolog2ann:ann_extract(Network, Clauses),
    prolog2ann:convert_clauses(Clauses, [], ExtractedNetwork),
    Network = network(Atoms, Rules, Strata, _, _, _, _),
    ExtractedNetwork = network(ExtractedAtoms, ExtractedRules,
                               ExtractedStrata, _, _, _, _),
    assertion(Atoms == ExtractedAtoms),
    assertion(Rules == ExtractedRules),
    assertion(Strata == ExtractedStrata).

test(extract_round_trip_stratified_negation) :-
    test_prolog2ann:example(flies, File),
    prolog2ann:convert_file(File, [], Network),
    prolog2ann:ann_extract(Network, Clauses),
    prolog2ann:convert_clauses(Clauses, [], ExtractedNetwork),
    Network = network(Atoms, Rules, Strata, _, _, _, _),
    ExtractedNetwork = network(ExtractedAtoms, ExtractedRules,
                               ExtractedStrata, _, _, _, _),
    assertion(Atoms == ExtractedAtoms),
    assertion(Rules == ExtractedRules),
    assertion(Strata == ExtractedStrata).

test(extract_from_generated_module) :-
    test_prolog2ann:example(ancestor, File),
    test_prolog2ann:example(ancestor_domain, Domain),
    tmp_file(prolog2ann, Output),
    setup_call_cleanup(
        true,
        ( prolog2ann:convert_file(
              File,
              [domain(Domain), out(Output), module(extracted_generated)],
              Network),
          load_files(Output, []),
          prolog2ann:ann_extract(extracted_generated, Clauses),
          prolog2ann:ann_extract(Network, Expected),
          assertion(Clauses == Expected)
        ),
        ( unload_file(Output),
          ( exists_file(Output) -> delete_file(Output) ; true )
        )).

:- end_tests(prolog2ann).

example_domain(Name, [domain(File)]) :-
    memberchk(Name, [ancestor, even_odd]),
    !,
    atom_concat(Name, '_domain', DomainName),
    example(DomainName, File).
example_domain(_, []).

example(Name, File) :-
    examples_directory(Examples),
    atomic_list_concat([Examples, '/', Name, '.pl'], File).

verify_example(Name, DomainName) :-
    test_prolog2ann:example(Name, File),
    (   DomainName == none
    ->  Options = []
    ;   test_prolog2ann:example(DomainName, DomainFile),
        Options = [domain(DomainFile)]
    ),
    prolog2ann:convert_file(File, Options, Network),
    prolog2ann:ann_verify(File, Network, Result),
    assertion(Result == equivalent).

verify_random_program(Seed) :-
    random_program(Clauses),
    tmp_file(prolog2ann_source, Source),
    tmp_file(prolog2ann_domain, Domain),
    tmp_file(prolog2ann_network, NetworkFile),
    format(atom(Module), 'property_network_~d', [Seed]),
    setup_call_cleanup(
        ( write_program(Source, Clauses),
          write_domain(Domain)
        ),
        ( prolog2ann:convert_file(
              Source,
              [domain(Domain), out(NetworkFile), module(Module)],
              _),
          load_files(NetworkFile, []),
          prolog2ann:ann_verify(Source, Module, Result),
          assertion(Result == equivalent)
        ),
        ( unload_file(NetworkFile),
          delete_file(Source),
          delete_file(Domain),
          delete_file(NetworkFile)
        )).

random_program(Clauses) :-
    findall(Fact,
            ( member(Predicate, [p, q]),
              member(Constant, [a, b, c, d, e]),
              random_between(0, 3, Choice),
              Choice =:= 0,
              Fact =.. [Predicate, Constant]
            ),
            RandomFacts),
    random_between(1, 8, RuleCount),
    random_rules(RuleCount, Rules),
    random_recursive_rule(RecursiveRule),
    random_negative_rule(NegativeRule),
    append([[p(a)|RandomFacts], [RecursiveRule, NegativeRule], Rules],
           Clauses).

random_rules(0, []) :-
    !.
random_rules(Count, [Rule|Rest]) :-
    random_rule(Rule),
    Remaining is Count - 1,
    random_rules(Remaining, Rest).

random_rule((Head :- Body)) :-
    random_element([r, s, t, u], HeadPredicate),
    Head =.. [HeadPredicate, Variable],
    random_between(1, 2, BodyLength),
    random_body(BodyLength, Variable, Body).

random_recursive_rule((Head :- Head)) :-
    random_element([r, s, t, u], Predicate),
    Head =.. [Predicate, _].

random_negative_rule((Head :- \+ Goal)) :-
    random_element([r, s, t, u], HeadPredicate),
    random_element([p, q], BodyPredicate),
    Head =.. [HeadPredicate, Variable],
    Goal =.. [BodyPredicate, Variable].

random_body(1, Variable, Literal) :-
    !,
    random_literal(Variable, Literal).
random_body(Length, Variable, (Literal, Rest)) :-
    random_literal(Variable, Literal),
    Remaining is Length - 1,
    random_body(Remaining, Variable, Rest).

random_literal(Variable, Literal) :-
    random_between(1, 5, Choice),
    (   Choice =< 2
    ->  random_element([p, q], Predicate)
    ;   random_element([r, s, t, u], Predicate)
    ),
    Goal =.. [Predicate, Variable],
    (   Choice =:= 2
    ->  Literal = (\+ Goal)
    ;   Literal = Goal
    ).

random_element(Elements, Element) :-
    length(Elements, Length),
    random_between(1, Length, Index),
    nth1(Index, Elements, Element).

write_program(File, Clauses) :-
    setup_call_cleanup(
        open(File, write, Stream, [encoding(utf8)]),
        forall(member(Clause, Clauses),
               ( write_term(Stream, Clause, [quoted(true), numbervars(true)]),
                 write(Stream, '.'),
                 nl(Stream)
               )),
        close(Stream)).

write_domain(File) :-
    setup_call_cleanup(
        open(File, write, Stream, [encoding(utf8)]),
        ( write(Stream, 'domain(constants, [a, b, c, d, e]).'),
          nl(Stream)
        ),
        close(Stream)).

temporary_network(Network, Module, Path) :-
    tmp_file(prolog2ann, Path),
    Module = test_generated_network,
    prolog2ann_emit:emit_network(Path, Module, Network),
    load_files(Path, []).

write_weighted_probe(File) :-
    Terms = [ (:- module(weighted_runtime_probe, [])),
              (:- use_module(library(prolog2ann/runtime))),
              network_atom(p(a)),
              network_atom(q(a)),
              network_rule(p(a), [], [], 0),
              network_rule(q(a), [p(a)], [], 0),
              network_stratum(0),
              neuron(out(p(a)), output, step, 0.5),
              neuron(out(q(a)), output, step, 0.5),
              neuron(hidden(1), hidden, step, -0.5),
              neuron(hidden(2), hidden, step, 0.5),
              edge(hidden(1), out(p(a)), 1.0),
              edge(in(p(a)), hidden(2), 0.0),
              edge(hidden(2), out(q(a)), 1.0),
              recurrent(out(p(a)), in(p(a))),
              recurrent(out(q(a)), in(q(a)))
            ],
    setup_call_cleanup(
        open(File, write, Stream, [encoding(utf8)]),
        forall(member(Term, Terms),
               ( write_term(Stream, Term, [quoted(true)]),
                 write(Stream, '.'),
                 nl(Stream)
               )),
        close(Stream)).
