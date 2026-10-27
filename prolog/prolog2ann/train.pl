:- module(prolog2ann_train,
          [ sigmoid_network/3,
            tanh_network/3,
            sigmoid_min_weight/2,
            ann_train/3,
            ann_train/4,
            ann_save/2,
            ann_agreement/3
          ]).

:- use_module(library(lists)).
:- use_module(library(error)).
:- use_module(library(apply)).
:- use_module(library(option)).
:- use_module(library(filesex)).
:- use_module('emit').
:- use_module('runtime').

%! sigmoid_min_weight(+Network, -MinWeight) is det.
%
% Minimum scale W for a step-mode network: with k the maximum of any clause's
% body size and the number of clauses sharing a head, take
% epsilon = 1/(2(k+1)) and W = 2 ln((1-epsilon)/epsilon). This is the
% derived saturation bound recorded in docs/DECISIONS.md, not the published
% CILP formula.
sigmoid_min_weight(network(_, Rules, _, _, _, _, _), MinWeight) :-
    findall(N, ( member(rule(_, P, Neg, _), Rules),
                 length(P, A), length(Neg, B), N is A + B ), BodySizes),
    findall(N, ( member(rule(Head, _, _, _), Rules),
                 aggregate_all(count, member(rule(Head, _, _, _), Rules), N) ),
            HeadCounts),
    append([[1], BodySizes, HeadCounts], Sizes),
    max_list(Sizes, K),
    Epsilon is 1 / (2 * (K + 1)),
    MinWeight is 2 * log((1 - Epsilon) / Epsilon).

%! sigmoid_network(+StepNetwork, +Weight, -SigmoidNetwork) is det.
%
% Scale weights and thresholds by Weight (auto or a float at least the bound)
% and switch hidden and output neurons to the logistic activation. The chosen
% value is reported with print_message/2.
sigmoid_network(Network, Weight, Scaled) :-
    Network = network(Atoms, Rules, Strata, Traces, Neurons, Edges, Recurrent),
    sigmoid_min_weight(Network, Min),
    (   Weight == auto
    ->  W is ceiling(Min * 100) / 100
    ;   number(Weight)
    ->  (   Weight >= Min
        ->  W is float(Weight)
        ;   throw(error(weight_below_bound(Weight, Min), _))
        )
    ;   throw(error(type_error(weight, Weight), _))
    ),
    print_message(informational, format('sigmoid weight W = ~4f (minimum ~4f)', [W, Min])),
    maplist(scale_neuron(W), Neurons, ScaledNeurons),
    maplist(scale_edge(W), Edges, ScaledEdges),
    Scaled = network(Atoms, Rules, Strata, Traces, ScaledNeurons, ScaledEdges,
                     Recurrent).

scale_neuron(_, neuron(Id, input, A, T), neuron(Id, input, A, T)) :- !.
scale_neuron(W, neuron(Id, Layer, _, T0), neuron(Id, Layer, sigmoid, T)) :-
    T is T0 * W.

scale_edge(W, edge(F, T, W0), edge(F, T, W1)) :-
    W1 is W0 * W.

%! tanh_network(+StepNetwork, +Weight, -TanhNetwork) is det.
%
% Scale a step-mode network by a positive Weight (or 1.0 for auto) and use
% bipolar tanh activations. A zero output corresponds to the step threshold.
tanh_network(Network, Weight, Scaled) :-
    (   Weight == auto
    ->  W = 1.0
    ;   number(Weight), Weight > 0
    ->  W is float(Weight)
    ;   number(Weight)
    ->  throw(error(domain_error(positive_weight, Weight), _))
    ;   throw(error(type_error(weight, Weight), _))
    ),
    Network = network(Atoms, Rules, Strata, Traces, Neurons, Edges, Recurrent),
    maplist(scale_tanh_neuron(W), Neurons, ScaledNeurons),
    maplist(scale_edge(W), Edges, ScaledEdges),
    Scaled = network(Atoms, Rules, Strata, Traces, ScaledNeurons, ScaledEdges,
                     Recurrent).

scale_tanh_neuron(_, neuron(Id, input, Activation, Threshold),
                  neuron(Id, input, Activation, Threshold)) :- !.
scale_tanh_neuron(W, neuron(Id, Layer, _, Threshold0),
                  neuron(Id, Layer, tanh, Threshold)) :-
    Threshold is Threshold0 * W.

%! ann_agreement(+Network, +Examples, -Fraction) is det.
%
% Fraction of Atom-Label examples (Label true or false) on which the network's
% thresholded fixpoint agrees.
ann_agreement(Network, Examples, Fraction) :-
    network_model(Network, Model),
    length(Examples, Total),
    include(correct(Model), Examples, Right),
    length(Right, N),
    (   Total =:= 0 -> Fraction = 1.0 ; Fraction is N / Total ).

correct(Model, Atom-Label) :-
    (   memberchk(Atom, Model) -> Label == true ; Label == false ).

network_model(Network, Model) :-
    run_network_term(Network, Model, Steps, Reached),
    (   Reached == true -> true ; throw(error(no_fixpoint(Steps), _)) ).

%! ann_train(+Network, +Examples, -Trained) is det.
%
% Same as ann_train/4 with default options.
ann_train(Network, Examples, Trained) :-
    ann_train(Network, Examples, [], Trained).

%! ann_train(+Network, +Examples, +Options, -Trained) is det.
%
% Backpropagation on a sigmoid-mode network. Examples is a list of Atom-Label
% with Label true or false. Each epoch computes the network's thresholded
% fixpoint and, for every example, backpropagates the cross-entropy error of
% the atom's output neuron through its hidden neurons (one step of the
% immediate-consequence operator; weights of other atoms are untouched).
% Options: epochs(N, default 500), rate(R, default 0.5). Training stops early
% once every example is classified correctly.
ann_train(Network, Examples, Options, Trained) :-
    must_be(list, Examples),
    forall(member(E, Examples), valid_example(E)),
    option(epochs(Epochs), Options, 500),
    must_be(nonneg, Epochs),
    option(rate(Rate), Options, 0.5),
    must_be(number, Rate),
    (   Rate > 0
    ->  true
    ;   throw(error(domain_error(positive_learning_rate, Rate), _))
    ),
    require_sigmoid(Network),
    train_loop(Epochs, Rate, Examples, Network, Trained).

valid_example(Atom-Label) :-
    must_be(ground, Atom),
    must_be(oneof([true, false]), Label),
    !.
valid_example(E) :- throw(error(type_error(example, E), _)).

require_sigmoid(network(_, _, _, _, Neurons, _, _)) :-
    (   memberchk(neuron(_, output, sigmoid, _), Neurons) -> true
    ;   throw(error(domain_error(sigmoid_network, step), _))
    ).

train_loop(0, _, _, Network, Network) :- !.
train_loop(Epochs, Rate, Examples, Network0, Network) :-
    (   ann_agreement(Network0, Examples, 1.0)
    ->  Network = Network0
    ;   network_model(Network0, Model),
        foldl(train_example(Model, Rate), Examples, Network0, Network1),
        Left is Epochs - 1,
        train_loop(Left, Rate, Examples, Network1, Network)
    ).

train_example(Model, Rate, Atom-Label, Network0, Network) :-
    Network0 = network(Atoms, Rules, Strata, Traces, Neurons0, Edges0, Rec),
    (   Label == true -> Y = 1.0 ; Y = 0.0 ),
    findall(Id-Ins,
            ( member(edge(hidden(Id), out(Atom), _), Edges0),
              findall(B-X,
                      ( member(edge(in(B), hidden(Id), _), Edges0),
                        ( memberchk(B, Model) -> X = 1.0 ; X = 0.0 )
                      ), Ins)
            ), Hidden),
    (   Hidden == [], \+ memberchk(neuron(out(Atom), _, _, _), Neurons0)
    ->  Network = Network0
    ;   forward(Hidden, Atom, Neurons0, Edges0, Acts, OutAct),
        DeltaOut is OutAct - Y,
        foldl(update_hidden(Atom, DeltaOut, Rate, Acts), Hidden,
              Neurons0-Edges0, Neurons1-Edges1),
        update_threshold(out(Atom), DeltaOut, Rate, Neurons1, Neurons2),
        Network = network(Atoms, Rules, Strata, Traces, Neurons2, Edges1, Rec)
    ).

forward(Hidden, Atom, Neurons, Edges, Acts, OutAct) :-
    findall(Id-H,
            ( member(Id-Ins, Hidden),
              neuron_threshold(hidden(Id), Neurons, T),
              findall(S, ( member(B-X, Ins),
                           edge_weight(in(B), hidden(Id), Edges, Wt),
                           S is Wt * X ), Ss),
              sum_list(Ss, Sum),
              H is 1 / (1 + exp(-(Sum - T)))
            ), Acts),
    neuron_threshold(out(Atom), Neurons, TO),
    findall(S, ( member(Id-H, Acts),
                 edge_weight(hidden(Id), out(Atom), Edges, Wt),
                 S is Wt * H ), Ss),
    sum_list(Ss, SumO),
    Z is SumO - TO,
    OutAct is 1 / (1 + exp(-Z)).

update_hidden(Atom, DeltaOut, Rate, Acts, Id-Ins, Neurons0-Edges0,
              Neurons-Edges) :-
    memberchk(Id-H, Acts),
    edge_weight(hidden(Id), out(Atom), Edges0, V),
    DeltaH is DeltaOut * V * H * (1 - H),
    OutStep is -Rate * DeltaOut * H,
    adjust_edge(hidden(Id), out(Atom), OutStep, Edges0, Edges1),
    foldl(update_input(Id, DeltaH, Rate), Ins, Edges1, Edges),
    update_threshold(hidden(Id), DeltaH, Rate, Neurons0, Neurons).

update_input(Id, DeltaH, Rate, B-X, Edges0, Edges) :-
    Step is -Rate * DeltaH * X,
    adjust_edge(in(B), hidden(Id), Step, Edges0, Edges).

% Thresholds act as negative biases, so the gradient step has the opposite sign.
update_threshold(Id, Delta, Rate, Neurons0, Neurons) :-
    select(neuron(Id, L, A, T0), Neurons0, Rest),
    !,
    T is T0 + Rate * Delta,
    Neurons = [neuron(Id, L, A, T)|Rest].
update_threshold(_, _, _, Neurons, Neurons).

neuron_threshold(Id, Neurons, T) :-
    memberchk(neuron(Id, _, _, T), Neurons).

edge_weight(F, T, Edges, W) :-
    memberchk(edge(F, T, W), Edges).

adjust_edge(F, T, Delta, Edges0, [edge(F, T, W)|Rest]) :-
    select(edge(F, T, W0), Edges0, Rest),
    !,
    W is W0 + Delta.

%! ann_save(+Network, +File) is det.
%
% Write a network (for example one returned by ann_train/3) in the generated
% module format; the module name is the file's base name.
ann_save(Network, File) :-
    file_base_name(File, Base),
    file_name_extension(Module, _, Base),
    emit_network(File, Module, Network).
