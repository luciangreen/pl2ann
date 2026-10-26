:- module(prolog2ann_parse, [parse_file/2]).

:- use_module(library(lists)).

%! parse_file(+File, -Clauses) is det.
%
% Read a source file into clause/5 terms while retaining variable names,
% source file, and starting line for diagnostics.
parse_file(File, Clauses) :-
    setup_call_cleanup(
        open(File, read, Stream, [encoding(utf8)]),
        read_clauses(Stream, File, Clauses),
        close(Stream)).

%! read_clauses(+Stream, +File, -Clauses) is det.
%
% Read and validate clauses, preserving their variable names and source lines.
read_clauses(Stream, File, Clauses) :-
    read_term(Stream, Term,
              [variable_names(Names), syntax_errors(error),
               term_position(TermPosition)]),
    (   Term == end_of_file
    ->  Clauses = []
    ;   stream_position_data(line_count, TermPosition, Line),
        validate_clause(Term, File, Line, Head, Body),
        Clauses = [clause(Head, Body, Names, File, Line)|Rest],
        read_clauses(Stream, File, Rest)
    ).

%! validate_clause(+Term, +File, +Line, -Head, -Body) is det.
%
% Split a source term into a supported head and body and validate both.
validate_clause((Head :- Body), File, Line, Head, Body) :-
    !,
    validate_goal(Body, File, Line),
    validate_head(Head, File, Line).
validate_clause(Head, File, Line, Head, true) :-
    validate_head(Head, File, Line).

%! validate_head(+Head, +File, +Line) is det.
%
% Reject heads that are not ordinary predicates with simple arguments.
validate_head(Head, File, Line) :-
    (   callable(Head),
        Head \= (_ :- _),
        functor(Head, Name, Arity),
        \+ reserved_head(Name, Arity),
        supported_predicate_arguments(Head)
    ->  true
    ;   throw(error(unsupported_construct(Head), file(File, Line)))
    ).

%! validate_goal(+Goal, +File, +Line) is det.
%
% Recursively validate conjunctions, disjunctions, negation, and supported
% predicate or built-in goals; throw a source-located error otherwise.
validate_goal((A, B), File, Line) :-
    !,
    validate_goal(A, File, Line),
    validate_goal(B, File, Line).
validate_goal((A ; B), File, Line) :-
    !,
    validate_goal(A, File, Line),
    validate_goal(B, File, Line).
validate_goal(\+ Goal, File, Line) :-
    (   Goal = (_, _)
    ;   Goal = (_ ; _)
    ),
    !,
    throw(error(unsupported_construct(negated_compound_goal), file(File, Line))).
validate_goal(\+ Goal, File, Line) :-
    !,
    validate_goal(Goal, File, Line).
validate_goal(Goal, File, Line) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    (   unsupported_goal(Name, Arity, Construct)
    ->  throw(error(unsupported_construct(Construct), file(File, Line)))
    ;   supported_builtin(Name, Arity)
    ->  validate_builtin_goal(Goal, File, Line)
    ;   predicate_property(system:Goal, built_in)
    ->  throw(error(unsupported_construct(Goal), file(File, Line)))
    ;   supported_predicate_arguments(Goal)
    ->  true
    ;   throw(error(unsupported_construct(compound_term), file(File, Line)))
    ),
    !.
validate_goal(Goal, File, Line) :-
    throw(error(unsupported_construct(Goal), file(File, Line))).

%! reserved_head(+Name, +Arity) is semidet.
%
% True when a predicate indicator is reserved for Prolog syntax.
reserved_head(Name, Arity) :-
    memberchk(Name/Arity, [(:-)/1, (:-)/2, (!)/0]).

%! unsupported_goal(+Name, +Arity, -Construct) is semidet.
%
% Classify explicitly unsupported control, database, collection, and I/O goals.
unsupported_goal(!, 0, !) :- !.
unsupported_goal(assert, _, assert) :- !.
unsupported_goal(asserta, _, assert) :- !.
unsupported_goal(assertz, _, assert) :- !.
unsupported_goal(retract, _, retract) :- !.
unsupported_goal(retractall, _, retract) :- !.
unsupported_goal(findall, _, findall) :- !.
unsupported_goal(bagof, _, bagof) :- !.
unsupported_goal(setof, _, setof) :- !.
unsupported_goal(Name, _, io) :-
    memberchk(Name, [write, writeln, read, read_term, open, close, format,
                     see, tell, shell, consult, ensure_loaded]).

%! supported_builtin(+Name, +Arity) is semidet.
%
% Enumerate built-ins that the grounding stage can safely pre-evaluate.
supported_builtin(true, 0).
supported_builtin(fail, 0).
supported_builtin(false, 0).
supported_builtin((<), 2).
supported_builtin((>), 2).
supported_builtin((=<), 2).
supported_builtin((>=), 2).
supported_builtin((=:=), 2).
supported_builtin((=\=), 2).
supported_builtin((=), 2).
supported_builtin((\=), 2).
supported_builtin(is, 2).

%! validate_builtin_goal(+Goal, +File, +Line) is det.
%
% Reject built-in argument shapes that grounding cannot evaluate.
validate_builtin_goal(Goal, File, Line) :-
    (   valid_builtin_goal(Goal)
    ->  true
    ;   throw(error(unsupported_construct(Goal), file(File, Line)))
    ).

%! valid_builtin_goal(+Goal) is semidet.
%
% Check that supported comparisons and arithmetic use supported terms.
valid_builtin_goal(Goal) :-
    (   Goal = (Left is Expression)
    ->  (var(Left) ; integer(Left)),
        integer_expression_term(Expression)
    ;   Goal = (Left < Right)
    ->  integer_expression_term(Left),
        integer_expression_term(Right)
    ;   Goal = (Left > Right)
    ->  integer_expression_term(Left),
        integer_expression_term(Right)
    ;   Goal = (Left =< Right)
    ->  integer_expression_term(Left),
        integer_expression_term(Right)
    ;   Goal = (Left >= Right)
    ->  integer_expression_term(Left),
        integer_expression_term(Right)
    ;   Goal = (Left =:= Right)
    ->  integer_expression_term(Left),
        integer_expression_term(Right)
    ;   Goal = (Left =\= Right)
    ->  integer_expression_term(Left),
        integer_expression_term(Right)
    ;   Goal = (Left = Right)
    ->  simple_argument(Left),
        simple_argument(Right)
    ;   Goal = (Left \= Right)
    ->  simple_argument(Left),
        simple_argument(Right)
    ;   memberchk(Goal, [true, fail, false])
    ).

%! integer_expression_term(+Expression) is semidet.
%
% Accept variables, integers, and the arithmetic operators evaluated at grounding.
integer_expression_term(Expression) :-
    (   var(Expression)
    ->  true
    ;   integer(Expression)
    ->  true
    ;   compound(Expression),
        Expression =.. [Operator, Left, Right],
        memberchk(Operator, [+, -, *, //, mod, rem]),
        integer_expression_term(Left),
        integer_expression_term(Right)
    ).

%! supported_predicate_arguments(+Term) is semidet.
%
% True when each argument is a variable, atomic value, or finite compound term.
supported_predicate_arguments(Term) :-
    Term =.. [_|Arguments],
    maplist(supported_argument, Arguments).

%! supported_argument(+Argument) is semidet.
%
% Accept recursively nested terms; grounding enforces the configured depth.
supported_argument(Argument) :-
    var(Argument),
    !.
supported_argument(Argument) :-
    atomic(Argument),
    !.
supported_argument(Argument) :-
    compound(Argument),
    Argument =.. [_|Arguments],
    Arguments \= [],
    maplist(supported_argument, Arguments).

%! simple_argument(+Argument) is semidet.
%
% Accept one variable or atomic predicate argument.
simple_argument(Argument) :-
    var(Argument),
    !.
simple_argument(Argument) :-
    atomic(Argument).
