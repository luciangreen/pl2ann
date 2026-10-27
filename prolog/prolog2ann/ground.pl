:- module(prolog2ann_ground,
          [ ground_program/5,
            ground_program_typed/7,
            ground_program_typed/8,
          ground_program_typed/9,
          read_domain/2,
          read_domain_schema/3
          ]).

:- use_module(library(lists)).
:- use_module(library(error)).

%! read_domain(+File, -Values) is det.
%
% Read finite values from domain/2 and range/3 declarations.
read_domain(File, Values) :-
    read_domain_schema(File, TypeDomains, _),
    findall(Domain, member(_-Domain, TypeDomains), Domains),
    append(Domains, Values0),
    sort(Values0, Values).

%! read_domain_schema(+File, -TypeDomains, -PositionTypes) is det.
%
% Read named finite domains and predicate-position type declarations.
read_domain_schema(File, TypeDomains, PositionTypes) :-
    setup_call_cleanup(
        open(File, read, Stream, [encoding(utf8)]),
        read_domain_terms(Stream, Terms),
        close(Stream)),
    (   forall(member(Term, Terms), valid_domain_term(Term))
    ->  true
    ;   throw(error(domain_error(finite_domain_declaration, File), _))
    ),
    findall(Type,
            ( member(Term, Terms), term_domain(Term, Type, _) ),
            Types0),
    sort(Types0, Types),
    findall(Type-Values,
            ( member(Type, Types),
              findall(Value,
                      ( member(Term, Terms),
                        term_domain(Term, Type, Values0),
                        member(Value, Values0)
                      ),
                      Values0),
              sort(Values0, Values)
            ),
            TypeDomains),
    (   forall(member(Term, Terms),
               valid_type_reference(Term, TypeDomains))
    ->  true
    ;   throw(error(domain_error(finite_domain_declaration, File), _))
    ),
    findall(Predicate/Arity-Position-Type,
            member(type(Predicate/Arity, Position, Type), Terms),
            PositionTypes0),
    sort(PositionTypes0, PositionTypes).

%! read_domain_terms(+Stream, -Terms) is det.
%
% Read all declarations from a domain file.
read_domain_terms(Stream, Terms) :-
    read_term(Stream, Term, [syntax_errors(error)]),
    ( Term == end_of_file -> Terms = []
    ; Terms = [Term|Rest], read_domain_terms(Stream, Rest)
    ).

%! valid_domain_term(+Term) is semidet.
%
% Validate one finite domain/2 or ascending integer range/3 declaration.
valid_domain_term(domain(_, Values)) :-
    is_list(Values),
    maplist(finite_value, Values).
valid_domain_term(range(_, Low, High)) :-
    integer(Low),
    integer(High),
    Low =< High.
valid_domain_term(type(Predicate/Arity, Position, Type)) :-
    atom(Predicate),
    integer(Arity),
    Arity >= 0,
    integer(Position),
    Position >= 1,
    Position =< Arity,
    atom(Type).

%! term_domain(+Declaration, -Type, -Values) is semidet.
%
% Extract one named value set from a domain/2 or range/3 declaration.
term_domain(domain(Type, Values), Type, Values).
term_domain(range(Type, Low, High), Type, Values) :-
    findall(Value, between(Low, High, Value), Values).

%! valid_type_reference(+Declaration, +TypeDomains) is semidet.
%
% Ensure every positional type declaration refers to a declared domain.
valid_type_reference(type(_, _, Type), TypeDomains) :-
    memberchk(Type-_, TypeDomains),
    !.
valid_type_reference(type(_, _, _), _) :-
    !,
    fail.
valid_type_reference(_, _).

%! finite_value(+Value) is semidet.
%
% Domain members must be ground finite terms.
finite_value(Value) :-
    (   atomic(Value)
    ;   compound(Value),
        ground(Value)
    ).

%! ground_program(+Normalised, +DomainValues, -GroundClauses, +Limit, -Atoms) is det.
%
% Instantiate variables over the finite universe, pre-evaluate supported
% built-ins, and enforce the Herbrand-base size limit.
ground_program(Normalised, DomainValues, GroundClauses, Limit, Atoms) :-
    ground_program_typed(Normalised, DomainValues, [], [], GroundClauses,
                         Limit, 0, Atoms).

%! ground_program_typed(+Normalised, +DomainValues, +TypeDomains,
%!                      +PositionTypes, -GroundClauses, +Limit, -Atoms) is det.
%
% Ground variables over their intersected positional types, using the global
% universe for variables without a type constraint.
ground_program_typed(Normalised, DomainValues, TypeDomains, PositionTypes,
                     GroundClauses, Limit, Atoms) :-
    ground_program_typed(Normalised, DomainValues, TypeDomains, PositionTypes,
                         GroundClauses, Limit, 0, Atoms).

%! ground_program_typed(+Normalised, +DomainValues, +TypeDomains,
%!                      +PositionTypes, -GroundClauses, +Limit, +TermDepth,
%!                      -Atoms) is det.
%
% As ground_program_typed/7, allowing recursively generated compound values up
% to TermDepth. Zero retains the function-free behavior.
ground_program_typed(Normalised, DomainValues, TypeDomains, PositionTypes,
                     GroundClauses, Limit, TermDepth, Atoms) :-
    ground_program_typed(Normalised, DomainValues, TypeDomains, PositionTypes,
                         GroundClauses, Limit, TermDepth, 100000, Atoms).

%! ground_program_typed(+Normalised, +DomainValues, +TypeDomains,
%!                      +PositionTypes, -GroundClauses, +Limit, +TermDepth,
%!                      +TermLimit, -Atoms) is det.
%
% As ground_program_typed/8, bounding initial universe values and the total
% number of generated constructor candidates by TermLimit.
ground_program_typed(Normalised, DomainValues, TypeDomains, PositionTypes,
                     GroundClauses, Limit, TermDepth, TermLimit, Atoms) :-
    must_be(nonneg, TermDepth),
    must_be(positive_integer, TermLimit),
    validate_domain_value_depths(DomainValues, TermDepth),
    validate_template_depths(Normalised, TermDepth),
    source_values(Normalised, SourceValues),
    append(DomainValues, SourceValues, AtomicValues0),
    sort(AtomicValues0, AtomicValues),
    source_constructors(Normalised, Constructors),
    bounded_universe(AtomicValues, Constructors, TermDepth, TermLimit,
                     Universe),
    require_finite_universe(Normalised, Universe),
    findall(Ground,
            ( member(Clause, Normalised),
              ground_clause(Clause, Universe, TypeDomains, PositionTypes,
                            TermDepth, Ground)
            ),
            GroundClauses),
    findall(Atom,
            ( member(ground_clause(H, Pos, Neg, _, _, _, _, _), GroundClauses),
              ( Atom = H ; member(Atom, Pos) ; member(Atom, Neg) )
            ),
            Atoms0),
    sort(Atoms0, Atoms),
    length(Atoms, Size),
    (   Size =< Limit
    ->  true
    ;   throw(error(herbrand_base_limit(Size, Limit), _))
    ).

%! require_finite_universe(+Clauses, +Universe) is det.
%
% Reject variable-bearing clauses when no finite grounding values exist.
require_finite_universe(Clauses, []) :-
    member(ground_clause(Head, Positive, Negative, Builtins, _, _, _, _),
           Clauses),
    term_variables(Head-Positive-Negative-Builtins, [_|_]),
    !,
    throw(error(finite_domain_required, _)).
require_finite_universe(_, _).

%! source_values(+Clauses, -Values) is det.
%
% Collect atomic constants used in clauses and built-in expressions.
source_values(Clauses, Values) :-
    findall(Value,
            ( member(ground_clause(H, Pos, Neg, Builtins, _, _, _, _), Clauses),
              ( sub_term(Value, H)
              ; member(Goal, Pos), sub_term(Value, Goal)
              ; member(Goal, Neg), sub_term(Value, Goal)
              ; member(Goal, Builtins), sub_term(Value, Goal)
              ),
              atomic(Value)
            ),
            Values).

%! validate_template_depths(+Clauses, +Limit) is det.
%
% Reject fixed compound structure that already exceeds the configured bound.
validate_template_depths([], _).
validate_template_depths(
        [ground_clause(Head, Positive, Negative, _, _, File, Line, _)|Rest],
        Limit) :-
    append([Head|Positive], Negative, Atoms),
    (   member(Atom, Atoms),
        atom_compound_depth(Atom, Depth),
        Depth > Limit
    ->  throw(error(term_depth_exceeded(Depth, Limit), file(File, Line)))
    ;   validate_template_depths(Rest, Limit)
    ).

%! validate_domain_value_depths(+Values, +Limit) is det.
%
% Reject explicit compound values that exceed the configured term depth.
validate_domain_value_depths([], _).
validate_domain_value_depths([Value|Rest], Limit) :-
    term_depth(Value, Depth),
    (   Depth =< Limit
    ->  validate_domain_value_depths(Rest, Limit)
    ;   throw(error(term_depth_exceeded(Depth, Limit), _))
    ).

%! source_constructors(+Clauses, -Constructors) is det.
%
% Find compound functors used in predicate arguments, not predicate calls.
source_constructors(Clauses, Constructors) :-
    findall(Name/Arity,
            ( member(ground_clause(Head, Positive, Negative, _, _, _, _, _),
                     Clauses),
              append([Head|Positive], Negative, Atoms),
              member(Atom, Atoms),
              Atom =.. [_|Arguments],
              member(Argument, Arguments),
              sub_term(Term, Argument),
              compound(Term),
              functor(Term, Name, Arity)
            ),
            Constructors0),
    sort(Constructors0, Constructors).

%! bounded_universe(+AtomicValues, +Constructors, +Depth, +TermLimit,
%!                  -Universe) is det.
%
% Construct all ground terms from source functors through the requested depth,
% subject to a cumulative candidate-generation budget.
bounded_universe(AtomicValues, _, 0, TermLimit, AtomicValues) :-
    length(AtomicValues, InitialCount),
    require_term_generation_limit(InitialCount, TermLimit),
    !.
bounded_universe(AtomicValues, Constructors, Depth, TermLimit, Universe) :-
    length(AtomicValues, InitialCount),
    require_term_generation_limit(InitialCount, TermLimit),
    bounded_universe(1, Depth, Constructors, AtomicValues, InitialCount,
                     TermLimit, Universe).

bounded_universe(CurrentDepth, MaximumDepth, _, Values, _, _, Values) :-
    CurrentDepth > MaximumDepth,
    !.
bounded_universe(CurrentDepth, MaximumDepth, Constructors, Values0, Work0,
                 TermLimit, Values) :-
    generated_terms(Constructors, Values0, CurrentDepth, Work0, TermLimit,
                    Terms, Work),
    append(Values0, Terms, Values1),
    sort(Values1, Values2),
    NextDepth is CurrentDepth + 1,
    bounded_universe(NextDepth, MaximumDepth, Constructors, Values2, Work,
                     TermLimit, Values).

%! generated_terms(+Constructors, +Universe, +Depth, +Work, +TermLimit,
%!                 -Terms, -Work) is det.
%
% Generate one depth layer after checking its Cartesian-product size.
generated_terms(Constructors, Universe, Depth, Work0, TermLimit, Terms, Work) :-
    PreviousDepth is Depth - 1,
    BeforePreviousDepth is Depth - 2,
    include(term_within_depth(PreviousDepth), Universe, EligibleValues),
    include(term_within_depth(BeforePreviousDepth), Universe,
            PreviousValues),
    length(EligibleValues, EligibleCount),
    length(PreviousValues, PreviousCount),
    findall(Count,
            ( member(_/Arity, Constructors),
              integer_power(EligibleCount, Arity, AllTerms),
              integer_power(PreviousCount, Arity, PreviousTerms),
              Count is AllTerms - PreviousTerms
            ),
            Counts),
    sum_list(Counts, CandidateCount),
    Work is Work0 + CandidateCount,
    require_term_generation_limit(Work, TermLimit),
    findall(Term,
            ( member(Name/Arity, Constructors),
              length(Arguments, Arity),
              maplist(member_value(EligibleValues), Arguments),
              Term =.. [Name|Arguments],
              term_depth(Term, Depth)
            ),
            Terms0),
    sort(Terms0, Terms).

term_within_depth(Limit, Term) :-
    term_depth(Term, Depth),
    Depth =< Limit.

integer_power(Base, Exponent, Power) :-
    integer_power(Exponent, Base, 1, Power).

integer_power(0, _, Power, Power) :-
    !.
integer_power(Exponent, Base, Accumulator, Power) :-
    Exponent > 0,
    NextAccumulator is Accumulator * Base,
    NextExponent is Exponent - 1,
    integer_power(NextExponent, Base, NextAccumulator, Power).

require_term_generation_limit(Count, Limit) :-
    (   Count =< Limit
    ->  true
    ;   throw(error(term_generation_limit(Count, Limit), _))
    ).

member_value(Values, Value) :-
    member(Value, Values).

%! atom_compound_depth(+Atom, -Depth) is det.
%
% Measure the deepest term within any predicate argument.
atom_compound_depth(Atom, Depth) :-
    Atom =.. [_|Arguments],
    maplist(term_depth_value, Arguments, Depths),
    ( Depths == [] -> Depth = 0 ; max_list(Depths, Depth) ).

term_depth_value(Term, Depth) :-
    term_depth(Term, Depth).

%! term_depth(+Term, -Depth) is det.
%
% Atoms and variables have depth zero; each compound layer adds one.
term_depth(Term, 0) :-
    ( var(Term) ; atomic(Term) ),
    !.
term_depth(Term, Depth) :-
    Term =.. [_|Arguments],
    maplist(term_depth_value, Arguments, Depths),
    max_list(Depths, ChildDepth),
    Depth is ChildDepth + 1.

%! ground_clause(+Clause, +Universe, -GroundClause) is nondet.
%
% Instantiate the clause variables and retain only assignments satisfying
% every pre-evaluated built-in.
ground_clause(ground_clause(Head, Positive, Negative, Builtins, Names, File,
                            Line, Stratum),
              Universe, TypeDomains, PositionTypes, TermDepth,
              ground_clause(GHead, GPositive, GNegative, [], Names, File,
                            Line, Stratum)) :-
    copy_term(Head-Positive-Negative-Builtins,
              GHead-GPositive-GNegative-GBuiltins),
    term_variables(GHead-GPositive-GNegative-GBuiltins, Variables),
    append([GHead|GPositive], GNegative, ClauseAtoms),
    variable_domains(Variables, ClauseAtoms,
                     TypeDomains, PositionTypes, Universe, Domains),
    assign_variables(Variables, Domains),
    maplist(within_atom_depth(TermDepth),
            [GHead|GPositive]),
    maplist(within_atom_depth(TermDepth), GNegative),
    maplist(evaluate_builtin, GBuiltins).

within_atom_depth(Limit, Atom) :-
    atom_compound_depth(Atom, Depth),
    Depth =< Limit.

%! assign_variables(+Variables, +Domains) is nondet.
%
% Bind each variable to one member of its finite domain.
assign_variables([], _).
assign_variables([Variable|Rest], [Domain|Domains]) :-
    member(Value, Domain),
    Variable = Value,
    assign_variables(Rest, Domains).

%! variable_domains(+Variables, +ClauseAtoms, +TypeDomains, +PositionTypes,
%!                 +Universe, -Domains) is det.
%
% Collect and intersect the declared domains for each clause variable.
variable_domains([], _, _, _, _, []).
variable_domains([Variable|Rest], Atoms, TypeDomains, PositionTypes, Universe,
                 [Domain|Domains]) :-
    findall(Values,
            ( member(Atom, Atoms),
              atom_position_type(Atom, Variable, PositionTypes, Type),
              memberchk(Type-Values, TypeDomains)
            ),
            Constraints),
    (   Constraints == []
    ->  Domain = Universe
    ;   intersect_domains(Constraints, Universe, Domain)
    ),
    variable_domains(Rest, Atoms, TypeDomains, PositionTypes, Universe,
                     Domains).

%! atom_position_type(+Atom, +Variable, +PositionTypes, -Type) is nondet.
%
% Find a positional type constraint for a variable occurrence.
atom_position_type(Atom, Variable, [Name/Arity-Position-Type|_], Type) :-
    functor(Atom, Name, Arity),
    arg(Position, Atom, Argument),
    Argument == Variable.
atom_position_type(Atom, Variable, [_|Rest], Type) :-
    atom_position_type(Atom, Variable, Rest, Type).

%! intersect_domains(+Constraints, +Universe, -Domain) is det.
%
% Intersect all typed domain constraints while preserving finite values.
intersect_domains([First|Rest], Universe, Domain) :-
    include(member_of(First), Universe, Initial),
    foldl(intersect_constraint, Rest, Initial, Domain).

member_of(Values, Value) :-
    memberchk(Value, Values).

intersect_constraint(Values, Current, Intersection) :-
    include(member_of(Values), Current, Intersection).

%! evaluate_builtin(+Goal) is semidet.
%
% Evaluate a supported comparison, unification, or arithmetic goal.
evaluate_builtin(true) :- !.
evaluate_builtin(fail) :- !, fail.
evaluate_builtin(false) :- !, fail.
evaluate_builtin(A < B) :- !, integer_expression(A, X), integer_expression(B, Y), X < Y.
evaluate_builtin(A > B) :- !, integer_expression(A, X), integer_expression(B, Y), X > Y.
evaluate_builtin(A =< B) :- !, integer_expression(A, X), integer_expression(B, Y), X =< Y.
evaluate_builtin(A >= B) :- !, integer_expression(A, X), integer_expression(B, Y), X >= Y.
evaluate_builtin(A =:= B) :- !, integer_expression(A, X), integer_expression(B, Y), X =:= Y.
evaluate_builtin(A =\= B) :- !, integer_expression(A, X), integer_expression(B, Y), X =\= Y.
evaluate_builtin(A = B) :- !, A = B.
evaluate_builtin(A \= B) :- !, A \= B.
evaluate_builtin(Variable is Expression) :-
    integer_expression(Expression, Value),
    Variable = Value.

%! integer_expression(+Expression, -Value) is semidet.
%
% Evaluate an integer expression using the supported arithmetic operators.
integer_expression(Expression, Value) :-
    (   integer(Expression)
    ->  Value = Expression
    ;   compound(Expression),
        Expression =.. [Operator, A, B],
        integer_expression(A, X),
        integer_expression(B, Y),
        arithmetic_result(Operator, X, Y, Value)
    ).

%! arithmetic_result(+Operator, +Left, +Right, -Result) is semidet.
%
% Apply one supported binary integer arithmetic operator.
arithmetic_result(+, A, B, Result) :- Result is A + B.
arithmetic_result(-, A, B, Result) :- Result is A - B.
arithmetic_result(*, A, B, Result) :- Result is A * B.
arithmetic_result(//, A, B, Result) :- B =\= 0, Result is A // B.
arithmetic_result(mod, A, B, Result) :- B =\= 0, Result is A mod B.
arithmetic_result(rem, A, B, Result) :- B =\= 0, Result is A rem B.
