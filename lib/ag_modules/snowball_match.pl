:- module(snowball_match,
	  []).

:- use_module(library(semweb/rdf_db)).
:- use_module(library(semweb/rdf_litindex)).
:- use_module(library(snowball)).
:- use_module(library(lit_distance)).
:- use_module(library(amalgame/vocabulary)).
:- use_module(library(amalgame/candidate)).

:- public amalgame_module/1.
:- public parameter/4.
:- public filter/3.
:- public matcher/4.

amalgame_module(amalgame:'SnowballMatcher').
amalgame_module(amalgame:'SnowballFilter').

parameter(sourcelabel, uri, P,
	  'Property to get label of the source by') :-
	rdf_equal(rdfs:label, P).
parameter(targetlabel, uri, P,
	  'Property to get the label of the target by') :-
	rdf_equal(rdfs:label, P).
parameter(language, atom, '',
	  'Language of source label').
parameter(matchacross_lang, boolean, true,
	  'Allow labels from different language to be matched').
parameter(snowball_language, atom, dutch,
	  'Language to use for stemmer').
parameter(prefix, integer, 4,
	  'Optmise performence by first generating candidates by matching the prefix.Input is an integer for the prefix length.').
parameter(edit_distance, integer, 0,
	  'When >0 allow additional differences between labels').


%%	filter(+MappingsIn, -MappingsOut, +Options)
%
%	Filter mappings based on matching stemmed labels.

filter([], [], _).
filter([C0|Cs], [C|Mappings], Options) :-
	match(C0, C, Options),
	!,
	filter(Cs, Mappings, Options).
filter([_|Cs], Mappings, Options) :-
	filter(Cs, Mappings, Options).

%%	matcher(+Source, +Target, -Mappings, +Options)
%
%	Mappings is a list of matches between instances of Source and
%	Target.

matcher(Source, Target, Mappings, Options) :-
	findall(A, align(Source, Target, A, Options), Mappings0),
	sort(Mappings0, Mappings).

align(Source, Target, Match, Options) :-
	option(prefix(0), Options),
	!,
	vocab_member(S, Source),
	match(align(S,T,[]), Match, Options),
	vocab_member(T, Target).

align(Source, Target, Match, Options) :-
 	prefix_candidate(Source, Target, Match0, Options),
	match(Match0, Match, Options).

match(align(Source, Target, Prov0), align(Source, Target, [Prov|Prov0]), Options) :-
	rdf_equal(rdfs:label,DefaultP),
  	option(snowball_language(Snowball_Language), Options, dutch),
 	option(sourcelabel(MatchProp1), Options, DefaultP),
	option(targetlabel(MatchProp2), Options, DefaultP),
	option(matchacross_lang(MatchAcross), Options, true),
	option(language(Lang),Options, _),
	option(edit_distance(Edit_Distance), Options, 0),

	(   Lang == ''
	->  var(SourceLang)
	;   SourceLang = Lang
	),
	% If we can't match across languages, set target language to source language
	(   MatchAcross == false
	->  TargetLang = SourceLang
	;   true
	),

	rdf_has(Source, MatchProp1, literal(lang(SourceLang, SourceLabel)), SourceProp),

	\+ Source == Target,
	downcase_atom(SourceLabel, SourceLabel0),
	snowball(Snowball_Language, SourceLabel0, SourceStem),
	rdf_has(Target, MatchProp2, literal(lang(TargetLang, TargetLabel)), TargetProp),
	downcase_atom(TargetLabel, TargetLabel0),
	snowball(Snowball_Language, TargetLabel0, TargetStem),
	(   Edit_Distance == 0
	->  TargetStem == SourceStem
	;   literal_distance(SourceStem, TargetStem, Distance),
	    Distance =< Edit_Distance
	),
 	Prov = [method(snowball),
 		graph([rdf(Source, SourceProp, literal(lang(SourceLang, SourceLabel))),
		       rdf(Target, TargetProp, literal(lang(TargetLang, TargetLabel)))])
	       ],
	debug(align_result, 'snowball match: ~p ~p', [Source,Target]).
