:- module(am_vocstats,
          [
	   is_vocabulary/2,
	   voc_property/2,
	   voc_clear_stats/1
          ]).

:- use_module(library(semweb/rdfs)).
:- use_module(library(semweb/rdf_db)).

:- use_module(library(amalgame/map)).
:- use_module(library(amalgame/ag_provenance)).
:- use_module(library(amalgame/vocabulary)).

/** <module> Compute and cache vocabulary-oriented properties and statistics.

Currently supported statistical properties include:
* version(Literal)
* format(oneof([skos,skosxl,null]))
* numberOfConcepts(xsd:int)
* numberOfPrefLabels(xsd:int)
* numberOfAltLabels(xsd:int)
* numberOfMappedConcepts(xsd:int)
* numberOfHomonyms(label_property, xsd:int)
* languages(list)
* languages(label_property, list)

@author Jacco van Ossenbruggen
*/

:- dynamic
	voc_stats_cache/2.

:- rdf_meta
	children(r,r,t,t),
	has_child(r,r,-),
	voc_property(r, -),
	voc_languages(r,-),
	voc_languages(r,r,-),
	voc_languages_used(r,r,-),
	count_homonyms(r,r,-).

voc_property(Voc, P) :-
	rdf_global_term(P, PG),
	(   voc_stats_cache(Voc, PG)
	->  true
	;   voc_ensure_stats(Voc, PG)
	).

assert_voc_prop(Voc, M) :-
	assert(voc_stats_cache(Voc, M)).


voc_clear_stats(all) :-
	retractall(voc_stats_cache(_,_)),
	rdf_unload_graph(vocstats),
	print_message(informational, map(cleared, 'vocabulary statistics', all_vocs, all)).

voc_clear_stats(Voc) :-
	retractall(voc_stats_cache(Voc, _)),
	print_message(informational, map(cleared, 'vocabulary statistics', Voc, all)).


is_vocabulary(Voc, Format):-
	ground(Voc),!,
	(   voc_stats_cache(Voc, format(Format))
	->  true
	;   voc_ensure_stats(Voc, format(Format))
	).

is_vocabulary(Voc, Format):-
	var(Voc),
	findall(V-F, voc_ensure_stats(V,format(F)), _),
	!,
	voc_stats_cache(Voc, format(Format)).

voc_ensure_stats(Voc, format(Format)) :-
	rdfs_individual_of(Voc, skos:'ConceptScheme'),
	\+ rdf(Voc, amalgame:wasGeneratedBy, _),
	(   voc_stats_cache(Voc, format(Format))
	->  true
	;   voc_find_format(Voc, Format),
	    assert(voc_stats_cache(Voc, format(Format)))
	).

voc_ensure_stats(Voc, version(Version)) :-
	(   rdf_has(Voc, owl:versionInfo, literal(Version))
	->  true
	;   rdf(Voc, amalgame:wasGeneratedBy, _)
	->  Version = amalgame_generated
	;   assert_voc_version(Voc, Version)
	->  true
	;   debug(info, 'Failed to ensure version stats for ~', [Voc])
	),!.


voc_ensure_stats(Voc, numberOfConcepts(Count)) :-
	(   count_concepts(Voc, Count) -> true ; Count = 0),
	assert_voc_prop(Voc, numberOfConcepts(Count)).

voc_ensure_stats(Voc, numberOfPrefLabels(Count)) :-
	(   count_prefLabels(Voc, Count) -> true ; Count = 0),
	assert_voc_prop(Voc, numberOfPrefLabels(Count)).

voc_ensure_stats(Voc, numberOfAltLabels(Count)) :-
	(   count_altLabels(Voc, Count) -> true ; Count = 0),
	assert_voc_prop(Voc,numberOfAltLabels(Count)).

voc_ensure_stats(Voc, numberOfMappedConcepts(Count)) :-
	(   count_mapped_concepts(Voc, Count) -> true ; Count = 0),
	assert_voc_prop(Voc, numberOfMappedConcepts(Count)).
voc_ensure_stats(Voc, languages(L)) :-
	(   voc_languages_used(Voc, L) -> true ; L = []),
	assert(voc_stats_cache(Voc, languages(L))).
voc_ensure_stats(Voc, languages(P,L)) :-
	(   voc_languages_used(Voc, P, L) -> true ; L = []),
	assert(voc_stats_cache(Voc, languages(P,L))).
voc_ensure_stats(Voc, numberOfHomonyms(P, Count)) :-
	(   count_homonyms(Voc, P, Count) -> true ; Count = 0),
	assert_voc_prop(Voc, numberOfHomonyms(P, Count)).

voc_ensure_stats(Voc, depth(Stats)) :-
	(  compute_depth_stats(Voc, depth(Stats)) -> true ; Stats = []),
	assert_voc_prop(Voc, depth(Stats)).

%%	assert_voc_version(+Voc, +TargetGraph) is det.
%
%	Assert version of Voc using RDF triples in named graph TargetGraph.

assert_voc_version(Voc, Version) :-
	(   rdf(Voc, amalgame:subSchemeOf, SuperVoc)
	->  assert_subvoc_version(Voc, SuperVoc, Version)
	;   assert_supervoc_version(Voc, Version)
	).

assert_subvoc_version(Voc, SuperVoc, Version) :-
	rdf_has(SuperVoc, owl:versionInfo, Version),
	assert(voc_stats_cache(Voc, version(Version))).

assert_supervoc_version(Voc, Version) :-
	rdf(_, skos:inScheme, Voc, SourceGraph:_),!,
	prov_get_entity_version(Voc, SourceGraph, Version),
	assert(voc_stats_cache(Voc, version(Version))).


count_concepts(Voc, Count) :-
	findall(Concept,
		vocab_member(Concept, Voc),
		Concepts),
	length(Concepts, Count),
	print_message(informational, map(found, 'Concepts', Voc, Count)).

count_prefLabels(Voc, Count) :-
	findall(Label,
		(   vocab_member(Concept, Voc),
		    (	rdf_has(Concept, skos:prefLabel, literal(Label))
		    ;	rdf_has(Concept, skosxl:prefLabel, Label)
		    )
		),
		Labels),
	length(Labels, Count),
	print_message(informational, map(found, 'SKOS preferred labels', Voc, Count)).

count_altLabels(Voc, Count) :-
	findall(Label,
		(   vocab_member(Concept, Voc),
		    (	rdf_has(Concept, skos:altLabel, literal(Label))
		    ;	rdf_has(Concept, skosxl:altLabel, Label)
		    )
		),
		Labels),
	length(Labels, Count),
	print_message(informational, map(found, 'SKOS alternative labels', Voc, Count)).

count_homonyms(Voc, Prop, Count) :-
	findall(Label-Concept,
		(   vocab_member(Concept, Voc),
		    rdf_has(Concept, Prop, literal(Label))
		),
		Labels),
	keysort(Labels, Sorted),
	group_pairs_by_key(Sorted, Grouped),
	include(is_homonym, Grouped, Homonyms),
	length(Homonyms, Count).

is_homonym(_Label-Concepts) :-
	length(Concepts, N), N > 1.

count_mapped_concepts(Voc, Count) :-
	findall(C,
		(   vocab_member(C, Voc),
		    (	has_correspondence_chk(align(C, _, _), _)
		    ;	has_correspondence_chk(align(_, C, _), _)
		    )
                ),
		Concepts),
	sort(Concepts, Sorted),
	length(Sorted, Count),
	print_message(informational, map(found, 'SKOS mapped concepts', Voc, Count)).

voc_languages_used(all, Langs) :-
	findall(L,
		(   rdfs_individual_of(Voc, skos:'ConceptScheme'),
		    voc_languages_used(Voc, L)
		),
		Ls),
	flatten(Ls, Flat),
	sort(Flat, Langs).

voc_languages_used(Voc, Langs) :-
	(   setof(Lang, language_used(Voc, Lang), Langs)
	->  true
	;   Langs = []
	).

voc_languages_used(Voc, Prop, Langs) :-
	(   setof(Lang, language_used(Voc, Prop, Lang), Langs)
	->  true
	;   Langs = []
	).

language_used(Voc, Lang) :-
	vocab_member(Concept, Voc),
	rdf(Concept, _, literal(lang(Lang, _))),
	ground(Lang).

language_used(Voc, Prop, Lang) :-
	vocab_member(Concept, Voc),
	rdf_has(Concept, Prop, literal(lang(Lang, _))),
	ground(Lang).

voc_find_format(Voc, Format) :-
	ground(Voc),
	(   vocab_member(Concept, Voc)
	->  (   rdf_has(Concept, skosxl:prefLabel, _)
	    ->  Format = skosxl
	    ;   rdf_has(Concept, skos:prefLabel, _)
	    ->  Format = skos
	    ;   rdf_has(Concept, skos:altLabel, _)
	    ->  Format = skos
	    ;   Format = null           % no concepts with known labels
	    )
	;   Format = null		% no concepts in the scheme
	).

compute_depth_stats(Voc, Stats) :-
	with_mutex(Voc,
		   (   compute_depth(Voc),
		       findall(D,
			       (   vocab_member(C, Voc),
				   rdf(C, amalgame:depth,
				       literal(type(xsd:int, D)))
			       ), Ds),
		       mean_std(Ds, Mean, Std, _),
		       Stats = depth([mean(Mean),
				standard_deviation(Std)])
		   )).

compute_depth(Voc) :-
	findall(TopConcept,
		(   vocab_member(TopConcept, Voc),
		    \+ parent_child(_, TopConcept, Voc)
		),
		TopConcepts),
	forall(member(C, TopConcepts),
	       compute_depth(C, Voc, 1)
	      ).

compute_depth(Concept, _Voc, _Depth) :-
	rdf(Concept, amalgame:depth, _),
	!. % done already, dual parent & loop detection

compute_depth(Concept, Voc, Depth) :-
	rdf_assert(Concept, amalgame:depth, literal(type(xsd:int, Depth)), vocstats),
	findall(Child,
		(   parent_child(Concept, Child, Voc),
		    vocab_member(Child, Voc)
		),
		Children),
	NewDepth is Depth + 1,
	forall(member(C, Children),
	       compute_depth(C, Voc, NewDepth)
	      ).

parent_child(Parent, Child, Voc) :-
	(   rdf_has(Child, skos:broader, Parent)
	;   rdf_has(Parent, skos:narrower, Child)
	;   fail),
	vocab_member(Child, Voc),
	vocab_member(Parent, Voc).

%%	mean_std(List, Mean, StandardDeviation, Length) is det.
%
%	This recursive version is adapted from the incremental version
%	at:
%	http://stackoverflow.com/questions/895929/how-do-i-determine-the-standard-deviation-stddev-of-a-set-of-values
%
%

mean_std(List, Mean, Std, K) :-
	mean_std_(List, Mean, S, K),
	Std is sqrt(S/K).

mean_std_([Value], Value, 0, 1) :- !.
mean_std_([Value|Tail], Mean, S, K) :-
	!,
	mean_std_(Tail, Tmean, Tstd, Tk),
	K is Tk + 1,
	Mean is Tmean + (Value - Tmean) / K,
	S is Tstd  + (Value - Tmean) * (Value - Mean).






