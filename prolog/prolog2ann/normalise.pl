:- module(prolog2ann_normalise, [normalise/2]).

:- use_module(library(lists)).

%! normalise(+ParsedClauses, -NormalisedClauses) is det.
%
% Split disjunctions into clauses, classify body literals, and reject
% dependencies whose negation constraints cannot be stratified.
normalise(Parsed, Normalised) :-
    findall(Normal, (member(Clause, Parsed), expand_clause(Clause, Normal)), Expanded),
    stratify(Expanded, Strata),
    maplist(attach_stratum(Strata), Expanded, Normalised).

%! expand_clause(+ParsedClause, -NormalClause) is nondet.
%
% Expand a parsed clause into one normalized clause per disjunctive branch.
expand_clause(clause(Head, Body, Names, File, Line), normal(Head, Positive,
              Negative, Builtins, Names, File, Line)) :-
    body_alternatives(Body, Alternatives),
    member(Alternative, Alternatives),
    flatten_body(Alternative, Literals),
    classify_literals(Literals, Positive, Negative, Builtins).

%! body_alternatives(+Body, -Alternatives) is det.
%
% Split a disjunctive body into its alternative branches.
body_alternatives((A ; B), Alternatives) :-
    !,
    body_alternatives(A, As),
    body_alternatives(B, Bs),
    append(As, Bs, Alternatives).
body_alternatives(Body, [Body]).

%! flatten_body(+Body, -Literals) is det.
%
% Flatten conjunctions into an ordered list of literals.
flatten_body((A, B), Literals) :-
    !,
    flatten_body(A, As),
    flatten_body(B, Bs),
    append(As, Bs, Literals).
flatten_body(true, []) :- !.
flatten_body(Body, [Body]).

%! classify_literals(+Literals, -Positive, -Negative, -Builtins) is det.
%
% Partition body literals into positive calls, negated calls, and built-ins.
classify_literals([], [], [], []).
classify_literals([Literal|Rest], Positive, Negative, Builtins) :-
    (   Literal = (\+ Goal)
    ->  Positive = PosRest, Negative = [Goal|NegRest], Builtins = BuiltRest
    ;   builtin_literal(Literal)
    ->  Positive = PosRest, Negative = NegRest, Builtins = [Literal|BuiltRest]
    ;   Positive = [Literal|PosRest], Negative = NegRest, Builtins = BuiltRest
    ),
    classify_literals(Rest, PosRest, NegRest, BuiltRest).

%! builtin_literal(?Literal) is semidet.
%
% Recognize supported goals that are evaluated during grounding.
builtin_literal(true).
builtin_literal(fail).
builtin_literal(false).
builtin_literal(_ < _).
builtin_literal(_ > _).
builtin_literal(_ =< _).
builtin_literal(_ >= _).
builtin_literal(_ =:= _).
builtin_literal(_ =\= _).
builtin_literal(_ = _).
builtin_literal(_ \= _).
builtin_literal(_ is _).
builtin_literal(in_domain(_, _)).

%! attach_stratum(+Strata, +NormalClause, -GroundClause) is det.
%
% Attach the stratum assigned to the clause's head predicate.
attach_stratum(Strata, normal(H, P, N, B, Names, File, Line),
               ground_clause(H, P, N, B, Names, File, Line, Stratum)) :-
    predicate_indicator(H, PI),
    memberchk(PI-Stratum, Strata).

%! stratify(+Clauses, -Strata) is det.
%
% Assign predicate strata or throw a source-located negative-cycle error.
stratify(Clauses, Strata) :-
    findall(PI, (member(normal(H, _, _, _, _, _, _), Clauses),
                 predicate_indicator(H, PI)), Heads0),
    sort(Heads0, Heads),
    length(Heads, Count),
    findall(dep(HeadPI, BodyPI, Sign, File, Line),
            (member(normal(H, Pos, Neg, _, _, File, Line), Clauses),
             predicate_indicator(H, HeadPI),
             ( member(B, Pos), predicate_indicator(B, BodyPI), Sign = positive
             ; member(B, Neg), predicate_indicator(B, BodyPI), Sign = negative
             )), Dependencies),
    initial_strata(Heads, Initial),
    relax_strata(Count, Dependencies, Initial, Strata),
    satisfies_strata(Dependencies, Strata),
    !.
stratify(Clauses, _) :-
    findall(dep(HeadPI, BodyPI, Sign, File, Line),
            ( member(normal(H, Pos, Neg, _, _, File, Line), Clauses),
              predicate_indicator(H, HeadPI),
              ( member(B, Pos), predicate_indicator(B, BodyPI), Sign = positive
              ; member(B, Neg), predicate_indicator(B, BodyPI), Sign = negative
              )), Dependencies),
    member(dep(Head, Body, negative, File, Line), Dependencies),
    dependency_path(Body, Head, Dependencies, [Body], Path),
    sort([Head, Body|Path], Cycle),
    throw(error(non_stratified_negation(Cycle), file(File, Line))).

%! initial_strata(+Predicates, -Strata) is det.
%
% Initialize every predicate at stratum zero.
initial_strata([], []).
initial_strata([PI|Rest], [PI-0|Strata]) :-
    initial_strata(Rest, Strata).

%! relax_strata(+Iterations, +Dependencies, +Current, -Strata) is det.
%
% Repeatedly raise predicate levels until all dependencies are satisfied.
relax_strata(0, _, Strata, Strata) :- !.
relax_strata(Iterations, Dependencies, Current, Strata) :-
    relax_once(Dependencies, Current, Next, Changed),
    (   Changed == true
    ->  Remaining is Iterations - 1,
        relax_strata(Remaining, Dependencies, Next, Strata)
    ;   Strata = Next
    ).

%! relax_once(+Dependencies, +Current, -Updated, -Changed) is det.
%
% Apply one ordered pass of positive and negative stratum constraints.
relax_once([], Strata, Strata, false).
relax_once([dep(Head, Body, Sign, _, _)|Rest], Current, Strata, Changed) :-
    memberchk(Head-HeadLevel, Current),
    (   memberchk(Body-BodyLevel, Current)
    ->  true
    ;   BodyLevel = 0
    ),
    (Sign == negative -> Required is BodyLevel + 1 ; Required = BodyLevel),
    (   Required > HeadLevel
    ->  replace_level(Head, Required, Current, Updated),
        Changed0 = true
    ;   Updated = Current,
        Changed0 = false
    ),
    relax_once(Rest, Updated, Strata, Changed1),
    (   (Changed0 == true ; Changed1 == true)
    ->  Changed = true
    ;   Changed = false
    ).

%! satisfies_strata(+Dependencies, +Strata) is semidet.
%
% Check that every dependency observes its required stratum ordering.
satisfies_strata([], _).
satisfies_strata([dep(Head, Body, Sign, _, _)|Rest], Strata) :-
    memberchk(Head-HeadLevel, Strata),
    (memberchk(Body-BodyLevel, Strata) -> true ; BodyLevel = 0),
    (Sign == negative -> Required is BodyLevel + 1 ; Required = BodyLevel),
    HeadLevel >= Required,
    satisfies_strata(Rest, Strata).

%! dependency_path(+From, +To, +Dependencies, +Seen, -Path) is nondet.
%
% Find a dependency path from From to To without revisiting seen predicates.
dependency_path(From, To, _, _, [From]) :-
    From == To,
    !.
dependency_path(From, To, Dependencies, Seen, [From|Path]) :-
    member(dep(From, Next, _, _, _), Dependencies),
    \+ memberchk(Next, Seen),
    dependency_path(Next, To, Dependencies, [Next|Seen], Path).

%! replace_level(+Predicate, +Level, +Strata, -Updated) is det.
%
% Replace the level associated with one predicate indicator.
replace_level(PI, Level, [PI-_|Rest], [PI-Level|Rest]) :- !.
replace_level(PI, Level, [Other|Rest], [Other|Updated]) :-
    replace_level(PI, Level, Rest, Updated).

%! predicate_indicator(+Callable, -Indicator) is det.
%
% Return the name/arity indicator of a callable term.
predicate_indicator(Term, Name/Arity) :-
    functor(Term, Name, Arity).
