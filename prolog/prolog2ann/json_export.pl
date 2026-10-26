:- module(prolog2ann_json_export, [export_json/2]).

:- use_module(library(http/json)).
:- use_module(library(lists)).

%! export_json(+File, +Network) is det.
%
% Write the inspectable step-, sigmoid-, or tanh-mode network as JSON.
export_json(File,
            network(Atoms, _, _, Traces, Neurons, Edges, Recurrent)) :-
    maplist(term_json, Atoms, JsonAtoms),
    maplist(neuron_json, Neurons, JsonNeurons),
    maplist(edge_json, Edges, JsonEdges),
    maplist(recurrent_json, Recurrent, JsonRecurrent),
    maplist(trace_json, Traces, JsonTraces),
    network_mode(Neurons, Mode),
    Dict = _{mode: Mode,
             atoms: JsonAtoms,
             neurons: JsonNeurons,
             edges: JsonEdges,
             recurrent: JsonRecurrent,
             traces: JsonTraces},
    setup_call_cleanup(
        open(File, write, Stream, [encoding(utf8)]),
        ( json_write_dict(Stream, Dict, [width(0)]),
          nl(Stream)
        ),
        close(Stream)).

network_mode(Neurons, Mode) :-
    (   memberchk(neuron(_, output, Activation, _), Neurons),
        memberchk(Activation, [sigmoid, tanh])
    ->  atom_string(Activation, Mode)
    ;   Mode = "step"
    ).

%! atom_json(+Atom, -String) is det.
%
% Convert an atom to its JSON string value.
atom_json(Term, String) :-
    atom_string(Term, String).

%! term_json(+Term, -String) is det.
%
% Serialize a Prolog term as quoted, stable text for JSON output.
term_json(Term, String) :-
    term_string(Term, String, [quoted(true), numbervars(true)]).

%! neuron_json(+Neuron, -Dict) is det.
%
% Convert a neuron record to the documented JSON object shape.
neuron_json(neuron(Id, Layer, Activation, Threshold),
            _{id: IdString,
              layer: LayerString,
              activation: ActivationString,
              threshold: Threshold}) :-
    term_json(Id, IdString),
    atom_json(Layer, LayerString),
    atom_json(Activation, ActivationString).

%! edge_json(+Edge, -Dict) is det.
%
% Convert a weighted edge record to JSON.
edge_json(edge(From, To, Weight),
          _{from: FromString, to: ToString, weight: Weight}) :-
    term_json(From, FromString),
    term_json(To, ToString).

%! recurrent_json(+Link, -Dict) is det.
%
% Convert a recurrent link record to JSON.
recurrent_json(recurrent(From, To),
               _{from: FromString, to: ToString}) :-
    term_json(From, FromString),
    term_json(To, ToString).

%! trace_json(+Trace, -Dict) is det.
%
% Convert a neuron-to-source trace record to JSON.
trace_json(trace(Neuron, Clause, File, Line),
           _{neuron: NeuronString,
             clause: Clause,
             file: FileString,
             line: Line}) :-
    term_json(Neuron, NeuronString),
    atom_json(File, FileString).
