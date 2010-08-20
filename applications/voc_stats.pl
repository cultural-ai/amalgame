:- module(voc_stats,
	  [
	   % HTTP entry points:
	   http_list_skos_vocs/1
	  ]).

:- use_module(library(http/http_dispatch)).
:- use_module(library(http/html_write)).
:- use_module(library(semweb/rdf_db)).
:- use_module(components(label)).

:- use_module('../skos/vocabularies').

:- http_handler(amalgame(list_skos_vocs),     http_list_skos_vocs,     []).

%%	http_list_skos_vocs(+Request) is det.
%
%	HTTP handler returning an HTML page listing of all skos vocabularies with statistics.

http_list_skos_vocs(_Request) :-
	reply_html_page(cliopatria(default),
			[title('SKOS vocabularies'),
			 style('#skosvoctable { border-collapse: collapse; border: solid #CCCCCC; }'),
			 style('#skosvoctable td, th { border-left: solid #CCCCCC; }'),
			 style('#finalrow td { border-top: solid #AAAAAA; }')
			],
			[ h4('SKOS concept schemes in the RDF store'),
			  \show_schemes
			]).


show_schemes -->
	{
	 skos_statistics(Schemes)
	},
	html(
	     table([
		    id(skosvoctable)],
		   [
		    tr([
			th('IRI'),
			th('Name'),
			th('# Concepts'),
			th('# prefLabels'),
			th('# altLabels'),
			th('Example concept')
		       ]),
		    \show_schemes(Schemes, [0, 0, 0])
		   ])
	    ).

show_schemes([], [C, P, A]) -->
	html(tr([id(finalrow)],
		[
		 td(''),
		 td('Total'),
		 td([style('text-align: right')],C),
		 td([style('text-align: right')],P),
		 td([style('text-align: right')],A),
		 td('')
		])).
show_schemes([H:Stats|Tail], [C,P,A]) -->
	{
	 member(numberOfConcepts(CCount), Stats),
	 member(numberOfPrefLabels(PCount), Stats),
	 member(numberOfAltLabels(ACount), Stats),
	 NewC is C + CCount,
	 NewP is P + PCount,
	 NewA is A + ACount,
	 (rdf_has(Example, skos:inScheme, H)
	 ->  true
	 ;   Example = '-'
	 ),
	 (rdf_has(H, dcterms:rights, RightsO)
	 ->  text_of_literal(RightsO, Rights)
	 ;   Rights = '-'
	 )
	},
	html(tr([
		 td(\rdf_link(H, [resource_format(plain)])),
		 td(\rdf_link(H, [resource_format(label)])),
		 td([style('text-align: right')],CCount),
		 td([style('text-align: right')],PCount),
		 td([style('text-align: right')],ACount),
		 td(\rdf_link(Example)),
		 td(Rights)
		])),
	show_schemes(Tail, [NewC, NewP, NewA]).
