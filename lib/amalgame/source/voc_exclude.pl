:- module(voc_exclude,
	  [
	  ]
	 ).

:- use_module(library(semweb/rdf_db)).
:- use_module(library(amalgame/alignment_graph)).

:- public source_select/3.
:- multifile amalgame:component/2.

:- public concept_selecter/5.
:- public concept_selecter/3.

concept_selecter(SourceVoc, TargetVoc, SelSourceVoc, SelTargetVoc, Options) :-
	get_exclusion_concepts(ExcSrcs, ExcTars, Options),
	findall(S, graph_member(S, SourceVoc), Sources),
	findall(T, graph_member(T, TargetVoc), Targets),

	length(ExcSrcs, NESs),	length(ExcTars, NETs),
	length(Sources, NSs),	length(Targets, NTs),
	NSLeft is NSs - NESs,	NTLeft is NTs - NETs,
	debug(align, 'Excluding ~w sources from ~w, leaving ~w',[NESs, NSs, NSLeft]),
	debug(align, 'Excluding ~w targets from ~w, leaving ~w',[NETs, NTs, NTLeft]),

	sort(Sources, SsSorted),
	sort(Targets, TsSorted),
	sort(ExcSrcs, EsSorted),
	sort(ExcTars, EtSorted),

	ord_subtract(SsSorted, EsSorted, SelSourceVoc),
	ord_subtract(TsSorted, EtSorted, SelTargetVoc).


concept_selecter(SourceAlignment, TargetAlignment, Options) :-
	option(exclude_sources(Exc), Options),!,
	voc_exclude(source, SourceAlignment, Exc, [], TargetAlignment0),
	predsort(alignment_graph:compare_align(targetplus), TargetAlignment0, TargetAlignment).

concept_selecter(SourceAlignment, TargetAlignment, Options) :-
	option(exclude_targets(Exc), Options),!,
	debug(align, 'Running target selector', []),
	predsort(alignment_graph:compare_align(targetplus), SourceAlignment, SourceAlignmentSorted),
	predsort(alignment_graph:compare_align(targetplus), Exc, ExcSorted),
	voc_exclude(target, SourceAlignmentSorted, ExcSorted, [], TargetAlignment0),
	predsort(alignment_graph:compare_align(targetplus), TargetAlignment0, TargetAlignment).

voc_exclude(_Type, L, [], Accum, Result) :- !, append(Accum, L, Result).
voc_exclude(_Type, [], _, Accum, Accum) :- !.
voc_exclude(Type, [A|ATail], [E|ETail], Accum, Result) :-
	compare_align(Type, Order, A, E),
	(   Order == '='
	->  voc_exclude(Type, ATail, [E|ETail], Accum, Result)
	;   Order == '<'
	->  voc_exclude(Type, ATail, [E|ETail], [A|Accum], Result)
	;   Order == '>'
	->  voc_exclude(Type, [A|ATail], ETail, Accum, Result)
	).

get_exclusion_concepts(ExcSrcs, ExcTars, Options) :-
	option(exclude(A), Options),!,
	(   is_list(A)
	->  Alignments =A
	;   e(A, Alignments)
	),
	maplist(align_source, Alignments, ExcSrcs),
	maplist(align_target, Alignments, ExcTars).


get_exclusion_concepts(ExcSrcs, ExcTars, Options) :-
	!,
	option(exclude_sources(ExcSrcs), Options, []),
	option(exclude_targets(ExcTars), Options, []),

amalgame:component(source_select, align_exlude(align_source, uris, [exclude(align_graph)])).

%%	source_select(+Source, +URIs, +Options)
%
%	URIs is a list of sorted Resources, representing all Concepts in
%	Source, excluding the sources in the ExcludeAlignment graph.
%	The latter is passed as an Option:
%	* exclude(ExcludeAlignment)
%

source_select(Source, URIs, Options) :-
	option(exclude(Alignments), Options),
	maplist(align_source, Alignments, Es),
	findall(S, graph_member(S, Source), Ss),
	length(Es, NEs),
	length(Ss, NSs),
	NLeft is NSs - NEs,
	debug(align, 'Excluding ~w alignments from ~w, leaving ~w',[NEs, NSs, NLeft]),
	sort(Ss, SsSorted),
	sort(Es, EsSorted),
	ord_subtract(SsSorted, EsSorted, URIs).

align_source(align(S,_,_), S).
align_target(align(_,T,_), T).




