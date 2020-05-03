:- module(ag_exec_process, [
	      exec_amalgame_process/7,
	      select_result_mapping/4,
	      select_result_scheme/4,
	      specification/7
	  ]).

:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(lists)).

:- use_module(library(semweb/rdf11)).
:- use_module(library(semweb/rdfs)).
:- use_module(library(amalgame/expand_graph)).
:- use_module(library(amalgame/correspondence)).
:- use_module(library(ag_modules/map_merger)).

:- multifile
	exec_amalgame_process/7,
	select_result_mapping/4,
	select_result_scheme/4,
	specification/7.

:- meta_predicate
	timed_call(5, -).

:- table exec_amalgame_process/7 as shared.

:- setting(prolog_flag:stack_limit, integer, 2_147_483_648,
	   'Limits the combined sizes of the Prolog stacks for the current thread.').
:- setting(prolog_flag:shared_table_space, integer, 2_147_483_648,
	   'Space reserved for storing shared answer tables.').

%%	select_result_mapping(+Id, +MapSpec, +Type, -Mapping) is det.
%%	select_result_mapping(+Id, -MapSpec, +Type, +Mapping) is det.
%
%	Mapping is part of (process) result MapSpec as defined by
%	Type.
%
%	@param OutputType is an RDF property
%	@error existence_error(mapping_select)

select_result_mapping(_Id, mapspec(select(Selected, Discarded, Undecided)),
		      OutputType, Mapping) :-
	\+ rdf_equal(amalgame:wasGeneratedBy, OutputType),
	!,
	(   rdf_equal(amalgame:selectedBy, OutputType)
	->  Mapping = Selected
	;   rdf_equal(amalgame:discardedBy, OutputType)
	->  Mapping = Discarded
	;   rdf_equal(amalgame:undecidedBy, OutputType)
	->  Mapping = Undecided
	;   throw(error(existence_error(mapping_selector, OutputType), _))
	),
	(   var(Selected)  -> Selected  = [] ; true),
	(   var(Discarded) -> Discarded = [] ; true),
	(   var(Undecided) -> Undecided = [] ; true).

select_result_mapping(_Id, mapspec(mapping(Mapping)), OutputType, Mapping) :-
	is_list(Mapping),
	rdf_equal(amalgame:wasGeneratedBy, OutputType).


select_result_mapping(Id, mapspec(overlap(List)), P, Mapping) :-
	!,
	rdf_equal(amalgame:wasGeneratedBy, P),
	(   member(Id-Mapping, List)
	->  true
	;   Mapping=[]
	).

select_result_scheme(_Id, vocspec(select(Selected, Discarded, Undecided)),
		      OutputType, Mapping) :-
	\+ rdf_equal(amalgame:wasGeneratedBy, OutputType),
	!,
	(   rdf_equal(amalgame:selectedBy, OutputType)
	->  Mapping = Selected
	;   rdf_equal(amalgame:discardedBy, OutputType)
	->  Mapping = Discarded
	;   rdf_equal(amalgame:undecidedBy, OutputType)
	->  Mapping = Undecided
	;   throw(error(existence_error(vocab_selector, OutputType), _))
	),
	(   var(Selected)  -> Selected  = [] ; true),
	(   var(Discarded) -> Discarded = [] ; true),
	(   var(Undecided) -> Undecided = [] ; true).

select_result_scheme(_Id, vocspec(Scheme), OutputType, vocspec(Scheme)) :-
	rdf_equal(amalgame:wasGeneratedBy, OutputType).

collect_snd_input(Process, Strategy, SecInput):-
	findall(S, rdf(Process, amalgame:secondary_input, S, Strategy), SecInputs),
	maplist(expand_node(Strategy), SecInputs, SecInputNF),
	merger(SecInputNF, SecInput, []).

%%	exec_amalgame_process(+Type,+Process,+Strategy,+Module,-Result,-Time,+Options)
%
%
%	Result is generated by executing Process of Type
%	in Strategy. This is to provide amalgame with a uniform interface to
%	all modules. This predicate is multifile so it is easy to add
%	new modules with different input/output parameters.
%
%       @error existence_error(mapping_process)

exec_amalgame_process(Class, Process, Strategy, Module, MapSpec, Time, Options) :-
	rdfs_subclass_of(Class, amalgame:'MappingPartitioner'),
	!,
	collect_snd_input(Process, Strategy, SecInput),
	MapSpec = mapspec(select(Selected, Discarded, Undecided)),
	once(rdf(Process, amalgame:input, InputId, Strategy)),
	expand_node(Strategy, InputId, MappingIn),
	timed_call(Module:selecter(MappingIn, Selected, Discarded, Undecided,
				   [snd_input(SecInput)|Options]), Time).
exec_amalgame_process(Type, Process, Strategy, Module, MapSpec, Time, Options) :-
	rdfs_subclass_of(Type, amalgame:'CandidateGenerator'),
	!,
	collect_snd_input(Process, Strategy, SecInput),
	rdf(Process, amalgame:source, Source, Strategy),
	rdf(Process, amalgame:target, Target, Strategy),
	expand_node(Strategy, Source, SourceSpec),
	expand_node(Strategy, Target, TargetSpec),
	timed_call(Module:matcher(SourceSpec, TargetSpec, Mapping0,
				  [snd_input(SecInput)|Options]), Time),
	merge_provenance(Mapping0, Mapping),
	MapSpec = mapspec(mapping(Mapping)).
exec_amalgame_process(Class, Process, Strategy, Module, VocSpec, Time, Options) :-
	rdfs_subclass_of(Class, amalgame:'VocabPartitioner'),
	!,
	once(rdf(Process, amalgame:input, Input, Strategy)),
	findall(S, rdf_has(Process, amalgame:secondary_input, S), Ss),
	VocSpec = vocspec(select(SelectedA, DiscardedA, UndecidedA)),
	vocab_spec(Strategy, Input, InputVocspec),
	timed_call(Module:selecter(InputVocspec, Selected, Discarded, Undecided,
				   [snd_input(Ss), strategy(Strategy)|Options]), Time),
	plain_ord_list_to_assoc(Selected, SelectedA),
	plain_ord_list_to_assoc(Discarded, DiscardedA),
	plain_ord_list_to_assoc(Undecided, UndecidedA).
exec_amalgame_process(Class, Process, Strategy, Module, MapSpec, Time, Options) :-
	rdfs_subclass_of(Class, amalgame:'MapMerger'),
	!,
	findall(Input, rdf(Process, amalgame:input, Input, Strategy), Inputs),
	maplist(expand_node(Strategy), Inputs, Expanded),
	timed_call(Module:merger(Expanded, Result, Options), Time),
	MapSpec = mapspec(mapping(Result)).
exec_amalgame_process(Class, Process, Strategy, Module, MapSpec, Time, Options) :-
	rdfs_subclass_of(Class, amalgame:'OverlapComponent'),
	!,
	findall(Input, rdf(Process, amalgame:input, Input, Strategy), Inputs),
	% We need the ids, not the values in most analyzers
	timed_call(Module:analyzer(Inputs, Process, Strategy, Result, Options), Time),
	MapSpec = mapspec(Result). % Result = overlap([..]).
exec_amalgame_process(Class, Process,_,_, _, _, _) :-
	throw(error(existence_error(mapping_process, [Class, Process]), _)).

specification(Class, Process, Strategy, Module, VocSpec, Time, Options) :-
	rdfs_subclass_of(Class, amalgame:'VocabPartitioner'),
	!,
	once(rdf(Process, amalgame:input, Input, Strategy)),
	findall(S, rdf_has(Process, amalgame:secondary_input, S), Ss),
	VocSpec = vocspec(select(Selected, Discarded, Undecided)),
	vocab_spec(Strategy, Input, InputVocspec),
	timed_call(Module:specifier(InputVocspec, Selected, Discarded, Undecided,
				   [snd_input(Ss), strategy(Strategy)|Options]), Time).
timed_call(Goal, Time) :-
	thread_self(Me),
        thread_statistics(Me, cputime, T0),
	call(Goal),
	thread_statistics(Me, cputime, T1),
        Time is T1 - T0.

dummy_value(K, K-null).

plain_ord_list_to_assoc(List, Assoc) :-
	maplist(dummy_value, List, Pairs),
	ord_list_to_assoc(Pairs, Assoc).
