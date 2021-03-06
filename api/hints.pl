:- module(ag_hints, []).

:- use_module(library(option)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_json)).
:- use_module(library(semweb/rdf11)).
:- use_module(library(semweb/rdfs)).
:- use_module(library(semweb/rdf_label)).
:- use_module(library(amalgame/ag_strategy)).
:- use_module(library(amalgame/ag_stats)).
:- use_module(library(amalgame/mapping_graph)).

:- http_handler(amalgame(data/hint), http_json_hint, []).

%%	http_json_hint(+Request) is det.
%
%	Return a json term Hint that represents an textual hint for the
%	user. The hint describes a potential next step to extend the
%	current alignment Strategy, given the most recent action and
%	current focus node.
%	In addition to the textual representation the Hint object also
%	contains sufficient machine-readable data so that the javascript
%	user interface can fire the associated event and execute the
%	hint automatically if requested by the user.

http_json_hint(Request) :-
	http_parameters(Request,
			[ strategy(Strategy,
				   [uri,
				    description('URI of an alignment strategy')]),
			  lastAction(LastAction,
			       [optional(true),
				description('Context: Previous action done')]),
			  focus(Focus,
			       [ uri,
				 description('Context: Node that is currently in focus in the builder'),
				 optional(true)
			       ])
			]),

	% cannot give proper hints if the focus node has not yet been computed:
	(   ground(Focus)
	->  node_stats(Strategy, Focus, _, [compute(true)])
	;   true
	),

	% first try a hint based on the focus node, if that fails, try without focus:
	(   find_hint(Strategy, [focus(Focus), lastAction(LastAction)], Hint)
	->  true
	;   find_hint(Strategy, [focus(_), lastAction(LastAction)], Hint)
	->  true
	;   Hint = json([])
	),
	reply_json(Hint).


%%	find_hint(+Strategy, +Context, -Hint) is nondet.
%
%	The predicate is implemented by a number of alternatives, each
%	representing a different phase in the strategy.

%       Initial phase: no mappings created, no vocab selected.
%	Focus is on the strategy node. Advise to select the smallest
%	vocab FIX ME: Assumes only two vocabs are being aligned.

find_hint(Strategy, Context, Hint) :-
	option(focus(Focus), Context),
	Focus == Strategy,
	\+ rdf(_, rdf:type, amalgame:'Mapping',Strategy),
	!,
	strategy_vocabulary(Strategy, Voc1),
	strategy_vocabulary(Strategy, Voc2),
	Voc1 \== Voc2,
	node_stats(Strategy, Voc1, Voc1Stats, []),
	node_stats(Strategy, Voc2, Voc2Stats, []),
	option(totalCount(Count1), Voc1Stats),
	option(totalCount(Count2), Voc2Stats),
	(   Count1 < Count2
	->  Source = Voc1, Target = Voc2
	;   Source = Voc2, Target = Voc1
	),
	rdf_display_label(Source, L1),
	rdf_display_label(Target, L2),
	format(atom(Text), 'Step 1: analyze. Vocabulary ~w is smaller than vocabulary ~w.  Maybe you should click on the first to set it as the source of your next step: generating new correspondences.', [L1, L2]),
	Hint = json([
		   event(nodeSelect),
		   data(json([
			    focus(Source),
			    uri(Source),
			    lastAction(current),
			    newVal(json([uri(Source), type(vocab), label(L1)])),
			    strategy(Strategy)
			])
		       ),
		   text(Text)
	       ]
		   ).

find_hint(Strategy, Context, Hint) :-
	% If there are no mappings yet, and the focus is a vocabulary.
	% advise an exact label match using the focus as the source
	\+ rdf(_, rdf:type, amalgame:'Mapping',Strategy),
	option(focus(Focus), Context),
	strategy_vocabulary(Strategy, Focus),
	!,
	strategy_vocabulary(Strategy, Target),
	Focus \== Target,
	rdf_equal(Match, amalgame:'ExactLabelMatcher'),
	rdf_display_label(Match, Label),
	rdf_display_label(Focus, L1),
	rdf_display_label(Target, L2),
	format(atom(Text), 'Step 2a: Generate correspondences.  Hint: maybe you\'d like to try a simple label Matcher like ~w to generate your first mapping from ~w to ~w', [Label, L1, L2]),
	Hint =	json([
		    event(submit),
		    data(json([
			     lastAction(generate),
			     focus(Focus),
			     process(Match),
			     source(Focus),
			     target(Target),
			     strategy(Strategy)
			      ])),
		    text(Text)
		     ]).
find_hint(Strategy, Context, Hint) :-
	option(focus(Focus), Context),
	Focus == Strategy,
	!, % this is typically the case for a reloaded strategy, when no mappings have been expanded yet. We expand a random endpoint mapping.
	is_endpoint(Strategy, Mapping),
	map_nickname(Strategy, Mapping, Nickname),
	map_localname(Strategy, Mapping, Localname),
	format(atom(Text),
	       'Step 1: analyze. You can click on a mapping like \'~w.~w\' to compute its results.',
	       [Nickname, Localname]),
	Hint = json([event(nodeSelect),
		     data(json([focus(Mapping),
				uri(Mapping),
				lastAction(current),
				newVal(json([uri(Mapping), type(mapping)])),
				strategy(Strategy)
			       ])),
		     text(Text)
		    ]).

find_hint(Strategy, Context, Hint) :-
	option(focus(Focus), Context),
	Focus == Strategy,
	needs_disambiguation(Strategy, _, Mapping),
	!,
	% Mmm, current focus is on the strategy node.  Suggest the user focusses on a mapping node that needs work.
	rdf_display_label(Mapping, L),
	format(atom(Text), 'Step 1: analyze.  Click on the node you want to analyze in more detail. Hint:  mapping ~w seems to need some work.', [L]),
	Hint =	json([
		    event(nodeSelect),
		    data(json([
			     lastAction(current),
			     newVal(json([uri(Mapping), type(mapping)])),
			     input(Mapping),
			     strategy(Strategy)
			      ])),
		    text(Text)
		     ]).

find_hint(Strategy, Context, Hint) :-
	% if there are end-point mappings with ambiguous correspondences, advise an ambiguity remover
	option(focus(Focus), Context),
	needs_disambiguation(Strategy, Focus, Mapping),
	!,
	rdf_equal(Process, amalgame:'AritySelect'),
	rdf_display_label(Process, PLabel),
	rdf_display_label(Mapping, MLabel),
	format(atom(Text), 'Step 2b: Partition. Maybe you\'d like to select the non-ambiguous results from node "~w" by running an ~w', [MLabel, PLabel]),
	Hint =	json([
		    event(submit),
		    data(json([
			     lastAction(select),
			     process(Process),
			     input(Mapping),
			     strategy(Strategy)
			      ])),
		    text(Text)
		     ]).
find_hint(Strategy, Context, Hint) :-
	% if focus node has been evaluated, maybe it can be get final status?
	option(focus(Focus), Context),
	ground(Focus),
	rdf(Eval, amalgame:evaluationOf, Focus, Strategy),
	rdf_graph(Eval), % check eval graph ain't empty ...
	rdf(Focus, amalgame:status, Status, Strategy),
	rdf_equal(FinalStatus, amalgame:final),
	FinalStatus \== Status,
	!,
	rdf_global_id(_:Local, Status),
	format(atom(Text), 'Approval: this dataset has been evaluated, if the results were satisfactory, you might want to change the status from \'~p\' to \'final\'.', [Local]),
	Hint = json([
		   event(nodeUpdate),
		   data(json([
			    lastAction(current),
			    uri(Focus),
			    strategy(Strategy),
			    status(FinalStatus)
			     ])),
		   text(Text),
		   focus(Focus)
	       ]).

find_hint(Strategy, Context, Hint) :-
	% if focus node is unambigious, small and not yet evaluated,
	% this might be a good idea to do.
	option(focus(Focus), Context),
	ground(Focus),
	\+ rdf(Focus, amalgame:evaluationOf, _, Strategy),
	hints_mapping_counts(Focus, Strategy, Stats),
	option(totalCount(N), Stats),
	option(mappedSourceConcepts(N), Stats),
	option(mappedTargetConcepts(N), Stats),
	N > 0, N < 51,
	!,
	format(atom(Text), 'Evaluate: this dataset only contains ~w non-ambigious mappings, that is good!  It has not yet been evaluated, however.  Manual inspection could help you decide if the quality is sufficient.', [N]),
	http_link_to_id(http_ag_evaluate, [strategy(Strategy), focus(Focus)],EvalPage),
	Hint =	json([
		    event(evaluate),
		    data(json([
			     lastAction(current),
			     focus(Focus),
			     strategy(Strategy),
			     page(EvalPage)
			      ])),
		    text(Text)
		     ]).
find_hint(Strategy, Context, Hint) :-
	% if focus node is unambigious and large maybe we should take a sample?
	option(focus(Focus), Context),
	ground(Focus),
	is_endpoint(Strategy, Focus),
	hints_mapping_counts(Focus, Strategy, Stats),
	option(totalCount(N), Stats),
	option(mappedSourceConcepts(N), Stats),
	option(mappedTargetConcepts(N), Stats),
	N > 50,
	!,
	rdf_equal(Process, amalgame:'Sampler'),
	format(atom(Text), 'Step 2b: Partition. This dataset contains ~w unambigious mappings, that is good!  You might want to take a random sample to look at in more detail', [N]),
	Hint =	json([
		    event(submit),
		    data(json([
			     lastAction(select),
			     process(Process),
			     input(Focus),
			     strategy(Strategy)
			      ])),
		    text(Text)
		     ]).

find_hint(Strategy, Context, Hint) :-
	option(focus(Focus), Context),
	is_known_to_be_disambiguous(Strategy, Focus, Mapping),
	http_link_to_id(http_ag_evaluate, [strategy(Strategy), focus(Mapping)],EvalPage),
	format(atom(Text), 'Evaluate: ~p contains ambiguous mappings.  Maybe you can select the good ones after looking at what is causing the problem.', [Mapping]),
	Hint =	json([
		    event(evaluate),
		    data(json([
			     lastAction(current),
			     focus(Mapping),
			     strategy(Strategy),
			     page(EvalPage)
			      ])),
		    text(Text)
		     ]).


/*
 todo: if more than one mapping is in need for disambiguation,
 select the one closest to focus node
*/
needs_disambiguation(Strategy, Focus, Mapping) :-
	rdf_equal(amalgame:'AritySelect', AritySelect),
	% Beware: findall below is needed to prevent deadlocks later in mapping_counts!
	findall(Mapping,
		(is_endpoint(Strategy, Mapping), % looking for endpoint mappings
		 \+ is_result_of_process_type(Mapping, AritySelect) % not already resulting from ar.select
		),
		Endpoints0),
	!,

	(   memberchk(Focus, Endpoints0)
	->  Endpoints = [Focus|Endpoints0]
	;   fail % Endpoints = Endpoints0
	),
	member(Mapping, Endpoints),
	hints_mapping_counts(Mapping, Strategy, Stats),
	option(totalCount(N), Stats),
	option(mappedSourceConcepts(SC), Stats),
	option(mappedTargetConcepts(TC), Stats),
	(   N \= SC; N \= TC ).

is_known_to_be_disambiguous(Strategy, Focus, Focus) :-
	rdf_has(Focus, amalgame:discardedBy, Process),
	rdfs_individual_of(Process, amalgame:'AritySelect'),
	is_endpoint(Strategy, Focus).

%%	is_endpoint(+Strategy, ?Mapping) is nondet.
%
%	Evaluates to true if Mapping is a mapping that is
%	the output of some process in Strategy
%	but not the input of some other
%	process in Strategy.
%

is_endpoint(Strategy, Mapping) :-
	rdf(Mapping, rdf:type, amalgame:'Mapping', Strategy),
	(   rdf(_Process, amalgame:input, Mapping, Strategy)
	->  forall(rdf(Process, amalgame:input, Mapping, Strategy),
	       (   rdfs_individual_of(Process,amalgame:'EvaluationProcess')
	       )
	      )
	;   true
	).

%%	is_result_of_process_type(?Mapping, ?Type) is nondet.
%
%	Evaluates to true if Mappings was generated by a process of
%	type Type.
%
is_result_of_process_type(Mapping, Type) :-
	rdf_has(Mapping, amalgame:wasGeneratedBy, Process),
	rdfs_individual_of(Process, Type).


% These are variants that just take things from the cache but
% never expand/compute something.

hints_mapping_counts(Id, Strategy, Stats) :-
	node_stats(Strategy, Id, Stats, [compute(false)]).
