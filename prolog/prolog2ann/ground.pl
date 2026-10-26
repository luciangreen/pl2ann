:- module(prolog2ann_ground,
          [ ground_program/5,
            ground_program_typed/7,
            read_domain/2,
            read_domain_schema/3
          ]).

:- use_module(library(lists)).

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
% Domain members must be atomic.
finite_value(Value) :-
    atomic(Value).

%! ground_program(+Normalised, +DomainValues, -GroundClauses, +Limit, -Atoms) is det.
%
% Instantiate variables over the finite universe, pre-evaluate supported
% built-ins, and enforce the Herbrand-base size limit.
ground_program(Normalised, DomainValues, GroundClauses, Limit, Atoms) :-
    ground_program_typed(Normalised, DomainValues, [], [], GroundClauses,
                         Limit, Atoms).

%! ground_program_typed(+Normalised, +DomainValues, +TypeDomains,
%!                      +PositionTypes, -GroundClauses, +Limit, -Atoms) is det.
%
% Ground variables over their intersected positional types, using the global
% universe for variables without a type constraint.
ground_program_typed(Normalised, DomainValues, TypeDomains, PositionTypes,
                     GroundClauses, Limit, Atoms) :-
    source_values(Normalised, SourceValues),
    append(DomainValues, SourceValues, Values),
    sort(Values, Universe),
    require_finite_universe(Normalised, Universe),
    findall(Ground,
            ( member(Clause, Normalised),
              ground_clause(Clause, Universe, TypeDomains, PositionTypes,
                            Ground)
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

%! ground_clause(+Clause, +Universe, -GroundClause) is nondet.
%
% Instantiate the clause variables and retain only assignments satisfying
% every pre-evaluated built-in.
ground_clause(ground_clause(Head, Positive, Negative, Builtins, Names, File,
                            Line, Stratum),
              Universe, TypeDomains, PositionTypes,
              ground_clause(GHead, GPositive, GNegative, [], Names, File,
                            Line, Stratum)) :-
    copy_term(Head-Positive-Negative-Builtins,
              GHead-GPositive-GNegative-GBuiltins),
    term_variables(GHead-GPositive-GNegative-GBuiltins, Variables),
    append([GHead|GPositive], GNegative, ClauseAtoms),
    variable_domains(Variables, ClauseAtoms,
                     TypeDomains, PositionTypes, Universe, Domains),
    assign_variables(Variables, Domains),
    maplist(evaluate_builtin, GBuiltins).

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
