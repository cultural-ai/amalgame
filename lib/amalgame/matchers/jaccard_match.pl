:- module(jaccard_match,
	  []).

:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdf_label)).
:- use_module(library(jaccard)).

:- public match/3.
:- multifile amalgame:component/2.

amalgame:component(matcher, jaccard_match(align(uri, uri, provenance), align(uri,uri,provenance),
					      [sourcelabel(uri, [default(skos:definition)]),
					       targetlabel(uri, [default(skos:definition)]),
					       threshold(integer)
					      ])).

match(align(Source, Target, Prov0), align(Source, Target, [Prov|Prov0]), Options) :-
 	rdf_equal(skos:definition, DefaultProp),
	option(threshold(Threshold), Options, 0.0),
 	option(sourcelabel(MatchProp1), Options, DefaultProp),
	option(targetlabel(MatchProp2), Options, DefaultProp),
	(   rdf_has(Source, MatchProp1, SourceLit, SourceProp),
	    rdf_has(Target, MatchProp2, TargetLit, TargetProp),
	    Source \== Target
	->  literal_text(SourceLit, SourceTxt),
	    literal_text(TargetLit, TargetTxt),
	    jaccard_similarity(SourceTxt, TargetTxt, Similarity)
	;   Similarity = 0
	),
	Similarity > Threshold,
 	Prov = [method(jaccard),
		match(Similarity),
		graph([rdf(Source, SourceProp, SourceLit),
		       rdf(Target, TargetProp, TargetLit)])
	       ].
