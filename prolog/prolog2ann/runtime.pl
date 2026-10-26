:- module(prolog2ann_runtime,
          [ ann_query/3,
            ann_query_all/3,
            run_network/4,
            run_network_term/4
          ]).

:- use_module(library(lists)).

%! ann_query(+Module, +GroundGoal, -Truth) is det.
%
% Query a generated network for a ground atom; Truth is true or false.
ann_query(Module, Goal, Truth) :-
    ( ground(Goal) -> true ; throw(error(instantiation_error, _)) ),
    run_network(Module, Atoms, Steps, Reached),
    ( Reached == true -> true ; throw(error(no_fixpoint(Steps), _)) ),
    ( memberchk(Goal, Atoms) -> Truth = true ; Truth = false ).

%! ann_query_all(+Module, +Pattern, -Solutions) is det.
%
% Return all active ground atoms matching Pattern, in standard order.
ann_query_all(Module, Pattern, Solutions) :-
    run_network(Module, Atoms, Steps, Reached),
    ( Reached == true -> true ; throw(error(no_fixpoint(Steps), _)) ),
    findall(Atom,
            ( member(Atom, Atoms),
              copy_term(Pattern, PatternCopy),
              PatternCopy = Atom
            ),
            Solutions0),
    sort(Solutions0, Solutions).

%! run_network(+Module, -Atoms, -Steps, -ReachedFixpoint) is det.
%
% Evaluate strata in order; each positive stratum runs to a least fixpoint.
% Steps counts successful closure rounds and the final no-change round.
run_network(Module, Atoms, Steps, Reached) :-
    module_facts(Module, Atom, network_atom(Atom), AtomList0),
    sort(AtomList0, Base),
    module_facts(Module, Stratum, network_stratum(Stratum), Strata0),
    sort(Strata0, Strata),
    module_facts(Module, neuron(Id, Layer, Activation, Threshold),
                 neuron(Id, Layer, Activation, Threshold), Neurons),
    module_facts(Module, edge(From, To, Weight),
                 edge(From, To, Weight), Edges),
    module_facts(Module, recurrent(From, To),
                 recurrent(From, To), Recurrent),
    module_step_limit(Module, Base, Limit),
    run_strata(Strata, Module, [], Base, Limit, Neurons, Edges, Recurrent,
               Model, Steps, Reached),
    Atoms = Model.

%! run_network_term(+Network, -Atoms, -Steps, -ReachedFixpoint) is det.
%
% Evaluate an in-memory network/7 term (step or sigmoid mode) as run_network/4
% does for a generated module. Sigmoid neurons are read out at 0.5 and bipolar
% tanh neurons at zero.
run_network_term(network(Base0, Rules, Strata0, _, Neurons, Edges, Recurrent),
                 Atoms, Steps, Reached) :-
    sort(Base0, Base),
    sort(Strata0, Strata),
    length(Base, BaseSize),
    Limit is BaseSize + 1,
    run_strata(Strata, rules(Rules), [], Base, Limit, Neurons, Edges,
               Recurrent, Atoms, Steps, Reached).

%! module_facts(+Module, ?Template, +Goal, -Facts) is det.
%
% Collect facts from a generated module, treating an absent predicate as empty.
module_facts(Module, Template, Goal, Facts) :-
    functor(Goal, Name, Arity),
    (   current_predicate(Module:Name/Arity)
    ->  findall(Template, Module:Goal, Facts)
    ;   Facts = []
    ).

%! module_step_limit(+Module, +Base, -Limit) is det.
%
% Use the generated module's configured limit or derive one from its atom base.
module_step_limit(Module, Base, Limit) :-
    (   current_predicate(Module:network_step_limit/1),
        Module:network_step_limit(Configured)
    ->  Limit = Configured
    ;   length(Base, BaseSize),
        Limit is BaseSize + 1
    ).

%! run_strata(+Strata, +Module, +Lower, +Base, +Limit, +Neurons, +Edges,
%            +Recurrent, -Model, -Steps, -Reached) is det.
%
% Close each stratum in order and stop if a configured limit is exhausted.
run_strata([], _, Model, _, _, _, _, _, Model, 0, true).
run_strata([Stratum|Rest], Module, Lower, Base, Limit, Neurons, Edges,
           Recurrent, Model, Steps, Reached) :-
    close_stratum(Module, Stratum, Lower, Base, Limit, Neurons, Edges,
                  Recurrent, Closed, Used, Reached0),
    (   Reached0 == true
    ->  run_strata(Rest, Module, Closed, Base, Limit, Neurons, Edges,
                   Recurrent, Model, Remaining, Reached),
        Steps is Used + Remaining
    ;   Model = Closed,
        Steps = Used,
        Reached = false
    ).

%! close_stratum(+Module, +Stratum, +Current, +Base, +Limit, +Neurons,
%               +Edges, +Recurrent, -Model, -Steps, -Reached) is det.
%
% Compute one stratum's closure using the lower-stratum model as input.
close_stratum(Module, Stratum, Current, Base, Limit, Neurons, Edges,
              Recurrent, Model, Steps, Reached) :-
    close_round(1, Module, Stratum, Current, Base, Limit, Neurons, Edges,
                Recurrent, Model, Steps, Reached).

%! close_round(+Step, +Module, +Stratum, +Current, +Base, +Limit, +Neurons,
%             +Edges, +Recurrent, -Model, -Steps, -Reached) is det.
%
% Apply one immediate-consequence round and detect stability or limit exhaustion.
close_round(Step, Module, Stratum, Current, Base, Limit, Neurons, Edges,
            Recurrent, Model, Steps, Reached) :-
    applicable_heads(Module, Stratum, Current, Neurons, Edges, Recurrent, Heads),
    append(Current, Heads, Combined),
    sort(Combined, Next),
    (   Next == Current
    ->  Model = Current,
        Steps = Step,
        Reached = true
    ;   Step >= Limit
    ->  Model = Next,
        Steps = Step,
        Reached = false
    ;   NextStep is Step + 1,
        close_round(NextStep, Module, Stratum, Next, Base, Limit, Neurons,
                    Edges, Recurrent, Model, Steps, Reached)
    ).

%! applicable_heads(+Module, +Stratum, +Current, +Neurons, +Edges, +Recurrent,
%                  -Heads) is det.
%
% Collect output atoms activated by the weighted neurons in this stratum.
applicable_heads(Module, Stratum, Current, Neurons, Edges, Recurrent, Heads) :-
    fired_hidden(Neurons, Edges, Recurrent, Current, Hidden),
    findall(Head,
            ( rule_head(Module, Stratum, Head),
              output_fires(Head, Neurons, Edges, Hidden)
            ),
            Heads0),
    sort(Heads0, Heads).

rule_head(rules(Rules), Stratum, Head) :-
    !,
    member(rule(Head, _, _, Stratum), Rules).
rule_head(Module, Stratum, Head) :-
    Module:network_rule(Head, _, _, Stratum).

%! fired_hidden(+Neurons, +Edges, +Recurrent, +Current, -Hidden) is det.
%
% Evaluate each step-mode hidden neuron from its weighted active inputs.
fired_hidden(Neurons, Edges, Recurrent, Current, Hidden) :-
    findall(Id,
            ( member(neuron(hidden(Id), hidden, Activation, Threshold), Neurons),
              memberchk(Activation, [step, sigmoid, tanh]),
              weighted_input_sum(hidden(Id), Edges, Recurrent, Current, Sum),
              Sum > Threshold
            ),
            Hidden).

%! weighted_input_sum(+Neuron, +Edges, +Recurrent, +Current, -Sum) is det.
%
% Sum weights from input neurons whose recurrent source is active.
weighted_input_sum(Neuron, Edges, Recurrent, Current, Sum) :-
    findall(Weight,
            ( member(edge(in(Atom), Neuron, Weight), Edges),
              memberchk(recurrent(out(Atom), in(Atom)), Recurrent),
              memberchk(Atom, Current)
            ),
            Weights),
    sum_weights(Weights, 0, Sum).

%! output_fires(+Atom, +Neurons, +Edges, +Hidden) is semidet.
%
% Evaluate an output neuron's weighted incoming hidden activations.
output_fires(Atom, Neurons, Edges, Hidden) :-
    memberchk(neuron(out(Atom), output, Activation, Threshold), Neurons),
    memberchk(Activation, [step, sigmoid, tanh]),
    findall(Weight,
            ( member(edge(hidden(Id), out(Atom), Weight), Edges),
              memberchk(Id, Hidden)
            ),
            Weights),
    sum_weights(Weights, 0, Sum),
    Sum > Threshold.

%! sum_weights(+Weights, +Total, -Sum) is det.
%
% Sum a list of neuron edge weights.
sum_weights([], Total, Total).
sum_weights([Weight|Rest], Total0, Sum) :-
    Total is Total0 + Weight,
    sum_weights(Rest, Total, Sum).
