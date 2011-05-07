YUI.add('controls', function(Y) {
	
	var Lang = Y.Lang,
		Node = Y.Node,
		Widget = Y.Widget;
	
	var NODE_CONTROLS = Y.all(".control"),
		NODE_INPUT_CONTROLS = Y.all("#select .control"),
		NODE_INPUT = Y.one("#input"),
		NODE_SOURCE = Y.one("#source"),
		NODE_TARGET = Y.one("#target"),
		NODE_INPUT_BTN = Y.one("#inputbtn"),
		NODE_SOURCE_BTN = Y.one("#sourcebtn"),
		NODE_TARGET_BTN = Y.one("#targetbtn");
	
	function Controls(config) {
		Controls.superclass.constructor.apply(this, arguments);
	}
	Controls.NAME = "controls";
	Controls.ATTRS = {
		srcNode: {
			value: null
		},
		selected: {
			value: null
		}
	};
	
	Y.extend(Controls, Y.Base, {
		initializer: function(config) {
			var instance = this,
				content = this.get("srcNode");
			
			// the control sets can be toggled
			Y.all(".control-set .hd").on("click", function(e) {
				console.log(e);
				e.currentTarget.get("parentNode").toggleClass("active");
			});
			
			// The list of amalgame modules make an accordion
			Y.all(".module-list").plug(Y.Plugin.NodeAccordion, { 
				multiple:false
			});

			NODE_CONTROLS.each( function(node) {
				node.one(".control-submit").on("click", this._onControlSubmit, this, node);
			}, this);
			
			this._toggleControls();
			
			// the match control has two additional buttons
			// to set the source and target
			Y.on("click", this._valueSet, NODE_INPUT_BTN, this, "input");
			Y.on("click", this._valueSet, NODE_SOURCE_BTN, this, "source");
	      	Y.on("click", this._valueSet, NODE_TARGET_BTN, this, "target");
			
			// toggle the controls when selected is changed
			this.after('selectedChange', this._toggleControls, this);
		},
				
		_onControlSubmit : function(e, node) {
			var content = this.get("srcNode"),
				input = NODE_INPUT.get("value"),
				source = NODE_SOURCE.get("value"),
				target = NODE_TARGET.get("value"),
				selected = this.get("selected"),
				data = this._getFormData(node);
			
			// The input is selected base on the type of the control
			// which is stored as a CSS class
			if(node.hasClass("match")) {
				if(input) {
					data.input = input;
				}
				else if(source&&target) {
					data.source = source;
					data.target = target;
				} else {
					return "no input available";
				}
			}
			else if(selected) {
				data.input = selected.uri;
			} else {
				return "no input";
			}
			
			this.fire("submit", {data:data});

		},
		
		_getFormData : function(form) {
			var data = {};
			// get the values of all HTML input fields
			form.all("input").each(function(input) {
				var name = input.get("name"),
					value = input.get("value");
				if(name&&value&&input.get("type")!=="button") {
					data[name] = value;
				}
			});
			// get the values of the selected options
			form.all("select").each(function(select) {
				var name = select.get("name"),
					index = select.get('selectedIndex'),
					value = select.get("options").item(index).get("value")
				if(value) {
					data[name] = value;
				}
			});
			
			return data;
		},
		
		_toggleControls : function() {
			var selected = this.get("selected"),
				type = selected ? selected.type : "";
			// We only show the controls for the active type
			NODE_INPUT_CONTROLS.each(function(node) {
				if(type&&node.hasClass(type)) {
					node.removeClass("disabled");
				} else {
					node.addClass("disabled");
				}
			});
			
			// enable input select when a vocabulary is selected
			NODE_INPUT_BTN.setAttribute("disabled", true);
			NODE_SOURCE_BTN.setAttribute("disabled", true);
			NODE_TARGET_BTN.setAttribute("disabled", true);
			if(type=="vocab") {
				NODE_SOURCE_BTN.removeAttribute("disabled");
				NODE_TARGET_BTN.removeAttribute("disabled");
			} else if(type=="mapping") {
				NODE_INPUT_BTN.removeAttribute("disabled");
			}
			
			// enable matcher submit when both source and target have a value
			if(NODE_INPUT.get("value")||
				(NODE_SOURCE.get("value")&&NODE_TARGET.get("value"))) {
				Y.all("#match .control-submit").removeAttribute("disabled");
			} else {
				Y.all("#match .control-submit").setAttribute("disabled", true);
			}
		},
		
		_valueSet : function(e, which) {
			var selected =  this.get("selected");
			if(selected) {
				Y.one("#"+which+'Label').set("value", selected.label);
				Y.one("#"+which).set("value", selected.uri);
				this._toggleControls();
     		}
			if(which=="input") {
				Y.one("#sourceLabel").set("value", "");
				Y.one("#source").set("value", "");
				Y.one("#targetLabel").set("value", "");
				Y.one("#target").set("value", "");
			} else {
				Y.one("#inputLabel").set("value", "");
				Y.one("#input").set("value", "");
			}
		}
		
	});
	
	Y.Controls = Controls;
	
}, '0.0.1', { requires: ['node,event','anim','gallery-node-accordion']});