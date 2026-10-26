:- module(prolog2ann_ground,
          [ ground_program/5,
            ground_program/6,
            read_domain/2,
            read_domain/3,
            domain_declarations/3
          ]).

:- use_module(library(lists)).

%! read_domain(+File, -Values) is det.
%
% Read finite values from domain/2 and range/3 declarations.
read_domain(File, Values) :-
    read_domain(File, Values, _).

%! read_domain(+File, -Values, -TypeDomains) is det.
%
% Read finite values and named domains from domain/2 and range/3 declarations.
read_domain(File, Values, TypeDomains) :-
    setup_call_cleanup(
        open(File, read, Stream, [encoding(utf8)]),
        read_domain_terms(Stream, Terms),
        close(Stream)),
    domain_declarations(Terms, Values, TypeDomains).

%! domain_declarations(+Declarations, -Values, -TypeDomains) is det.
%
% Validate and expand a list of domain/2 and range/3 declarations.
domain_declarations(Terms, Values, TypeDomains) :-
    (   forall(member(Term, Terms), valid_domain_term(Term))
    ->  true
    ;   throw(error(domain_error(finite_domain_declaration, Terms), _))
    ),
    findall(Value,
            ( member(Term, Terms),
              ( Term = domain(_, Items), member(Value, Items)
              ; Term = range(_, Low, High), integer(Low), integer(High),
                Low =< High, between(Low, High, Value)
              )),
            Values0),
    sort(Values0, Values),
    named_domains(Terms, TypeDomains).

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
valid_domain_term(domain(Type, Values)) :-
    atomic(Type),
    is_list(Values),
    maplist(finite_value, Values).
valid_domain_term(range(Type, Low, High)) :-
    atomic(Type),
    integer(Low),
    integer(High),
    Low =< High.

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
    ground_program(Normalised, DomainValues, [], GroundClauses, Limit, Atoms).

%! ground_program(+Normalised, +DomainValues, +TypeDomains, -GroundClauses,
%!                +Limit, -Atoms) is det.
%
% Ground variables globally unless an in_domain/2 body constraint selects a
% declared named domain.
ground_program(Normalised, DomainValues, TypeDomains, GroundClauses,
               Limit, Atoms) :-
    source_values(Normalised, SourceValues),
    append(DomainValues, SourceValues, Values),
    sort(Values, Universe),
    require_finite_universe(Normalised, Universe, TypeDomains),
    findall(Ground,
            ( member(Clause, Normalised),
              ground_clause(Clause, Universe, TypeDomains, Ground)
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

%! require_finite_universe(+Clauses, +Universe, +TypeDomains) is det.
%
% Reject variable-bearing clauses when no finite grounding values exist.
require_finite_universe(Clauses, [], TypeDomains) :-
    (   member(ground_clause(Head, Positive, Negative, Builtins, _, _, _, _),
               Clauses),
        term_variables(Head-Positive-Negative-Builtins, Variables),
        Variables \= [],
        \+ maplist(variable_has_domain(Builtins, TypeDomains), Variables)
    ->  throw(error(finite_domain_required, _))
    ;   true
    ).
require_finite_universe(_, _, _).

variable_has_domain(Builtins, TypeDomains, Variable) :-
    member(in_domain(Constrained, Type), Builtins),
    Constrained == Variable,
    type_domain_values(TypeDomains, Type, _),
    !.

%! source_values(+Clauses, -Values) is det.
%
% Collect atomic constants used in clauses and built-in expressions.
source_values(Clauses, Values) :-
    findall(Value,
            ( member(ground_clause(H, Pos, Neg, Builtins, _, _, _, _), Clauses),
              ( sub_term(Value, H)
              ; member(Goal, Pos), sub_term(Value, Goal)
              ; member(Goal, Neg), sub_term(Value, Goal)
              ; member(Goal, Builtins),
                source_builtin_value(Goal, Value)
              ),
              atomic(Value)
            ),
            Values).

source_builtin_value(in_domain(_, _), _) :- !, fail.
source_builtin_value(Goal, Value) :-
    sub_term(Value, Goal).

%! ground_clause(+Clause, +Universe, +TypeDomains, -GroundClause) is nondet.
%
% Instantiate the clause variables and retain only assignments satisfying
% every pre-evaluated built-in.
ground_clause(ground_clause(Head, Positive, Negative, Builtins, Names, File,
                            Line, Stratum),
              Universe,
              TypeDomains,
              ground_clause(GHead, GPositive, GNegative, [], Names, File,
                            Line, Stratum)) :-
    copy_term(Head-Positive-Negative-Builtins,
              GHead-GPositive-GNegative-GBuiltins),
    term_variables(GHead-GPositive-GNegative-GBuiltins, Variables),
    assign_variables(Variables, Universe, GBuiltins, TypeDomains),
    maplist(evaluate_builtin(TypeDomains), GBuiltins).

%! assign_variables(+Variables, +Universe, +Builtins, +TypeDomains) is nondet.
%
% Bind each variable to its declared domain, or to the global universe when
% no in_domain/2 constraint applies to it.
assign_variables([], _, _, _).
assign_variables([Variable|Rest], Universe, Builtins, TypeDomains) :-
    variable_values(Variable, Builtins, TypeDomains, Universe, Values),
    member(Value, Values),
    Variable = Value,
    assign_variables(Rest, Universe, Builtins, TypeDomains).

variable_values(Variable, Builtins, TypeDomains, Universe, Values) :-
    findall(Type,
            ( member(in_domain(Constrained, Type), Builtins),
              Constrained == Variable
            ),
            Types),
    (   Types == []
    ->  Values = Universe
    ;   maplist(type_domain_values(TypeDomains), Types, Domains),
        Domains = [First|Rest],
        foldl(intersect_values, Rest, First, Values)
    ).

type_domain_values(TypeDomains, Type, Values) :-
    (   memberchk(type_domain(Type, Values), TypeDomains)
    ->  true
    ;   throw(error(existence_error(domain_type, Type), _))
    ).

intersect_values(Values, Acc, Intersection) :-
    intersection(Acc, Values, Intersection).

%! evaluate_builtin(+TypeDomains, +Goal) is semidet.
%
% Evaluate a supported comparison, unification, or arithmetic goal.
evaluate_builtin(_, true) :- !.
evaluate_builtin(_, fail) :- !, fail.
evaluate_builtin(_, false) :- !, fail.
evaluate_builtin(_, A < B) :- !, integer_expression(A, X), integer_expression(B, Y), X < Y.
evaluate_builtin(_, A > B) :- !, integer_expression(A, X), integer_expression(B, Y), X > Y.
evaluate_builtin(_, A =< B) :- !, integer_expression(A, X), integer_expression(B, Y), X =< Y.
evaluate_builtin(_, A >= B) :- !, integer_expression(A, X), integer_expression(B, Y), X >= Y.
evaluate_builtin(_, A =:= B) :- !, integer_expression(A, X), integer_expression(B, Y), X =:= Y.
evaluate_builtin(_, A =\= B) :- !, integer_expression(A, X), integer_expression(B, Y), X =\= Y.
evaluate_builtin(_, A = B) :- !, A = B.
evaluate_builtin(_, A \= B) :- !, A \= B.
evaluate_builtin(TypeDomains, in_domain(_, Type)) :-
    !,
    memberchk(type_domain(Type, _), TypeDomains).
evaluate_builtin(_, Variable is Expression) :-
    integer_expression(Expression, Value),
    Variable = Value.

named_domains(Terms, TypeDomains) :-
    findall(Type,
            ( member(Term, Terms),
              domain_type(Term, Type)
            ),
            Types0),
    sort(Types0, Types),
    maplist(named_domain(Terms), Types, TypeDomains).

domain_type(domain(Type, _), Type).
domain_type(range(Type, _, _), Type).

named_domain(Terms, Type, type_domain(Type, Values)) :-
    findall(Value,
            ( member(Term, Terms),
              ( Term = domain(Type, Items), member(Value, Items)
              ; Term = range(Type, Low, High), between(Low, High, Value)
              )
            ),
            Values0),
    sort(Values0, Values).

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
