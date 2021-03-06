(*
 *  Haxe Compiler
 *  Copyright (c)2005-2008 Nicolas Cannasse
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *)
open Type

type package_rule =
	| Forbidden
	| Directory of string
	| Remap of string

type platform =
	| Cross
	| Flash
	| Js
	| Neko
	| Flash9
	| Php
	| Cpp

type pos = Ast.pos

type basic_types = {
	mutable tvoid : t;
	mutable tint : t;
	mutable tfloat : t;
	mutable tbool : t;
	mutable tnull : t -> t;
	mutable tstring : t;
	mutable tarray : t -> t;
}

type context = {
	(* config *)
	version : int;
	mutable display : bool;
	mutable debug : bool;
	mutable verbose : bool;
	mutable foptimize : bool;
	mutable dead_code_elimination : bool;
	mutable platform : platform;
	mutable std_path : string list;
	mutable class_path : string list;
	mutable main_class : Type.path option;
	mutable defines : (string,unit) PMap.t;
	mutable package_rules : (string,package_rule) PMap.t;
	mutable error : string -> pos -> unit;
	mutable warning : string -> pos -> unit;
	mutable load_extern_type : (path -> pos -> Ast.package option) list; (* allow finding types which are not in sources *)
	mutable filters : (unit -> unit) list;
	mutable defines_signature : string option;
	(* output *)
	mutable file : string;
	mutable flash_version : float;
	mutable modules : Type.module_def list;
	mutable main : Type.texpr option;
	mutable types : Type.module_type list;
	mutable resources : (string,string) Hashtbl.t;
	mutable neko_libs : string list;
	mutable php_front : string option;
	mutable php_lib : string option;
	mutable php_prefix : string option;
	mutable swf_libs : (string * (unit -> Swf.swf) * (unit -> ((string list * string),As3hl.hl_class) Hashtbl.t)) list;
	mutable js_gen : (unit -> unit) option;
	(* typing *)
	mutable basic : basic_types;
}

type global_cache = {
	cache_version : int;
	mutable cache_file : string option;
	mutable cached_haxelib : (string list, string list) Hashtbl.t;
	mutable cached_files : (string, float * Ast.package) Hashtbl.t;
}

exception Abort of string * Ast.pos

let display_default = ref false

let cache_version = 1
let global_cache : global_cache option ref = ref None

let create_cache() =
	{
		cache_version = cache_version;
		cache_file = None;
		cached_files = Hashtbl.create 0;
		cached_haxelib = Hashtbl.create 0;
	}

let create v =
	let m = Type.mk_mono() in
	{
		version = v;
		debug = false;
		display = !display_default;
		verbose = false;
		foptimize = true;
		dead_code_elimination = false;
		platform = Cross;
		std_path = [];
		class_path = [];
		main_class = None;
		defines = PMap.add "true" () (if !display_default then PMap.add "display" () PMap.empty else PMap.empty);
		package_rules = PMap.empty;
		file = "";
		types = [];
		filters = [];
		modules = [];
		main = None;
		flash_version = 10.;
		resources = Hashtbl.create 0;
		php_front = None;
		php_lib = None;
		swf_libs = [];
		neko_libs = [];
		php_prefix = None;
		js_gen = None;
		load_extern_type = [];
		defines_signature = None;
		warning = (fun _ _ -> assert false);
		error = (fun _ _ -> assert false);
		basic = {
			tvoid = m;
			tint = m;
			tfloat = m;
			tbool = m;
			tnull = (fun _ -> assert false);
			tstring = m;
			tarray = (fun _ -> assert false);
		};
	}

let clone com =
	let t = com.basic in
	{ com with basic = { t with tvoid = t.tvoid } }

let platforms = [
	Flash;
	Js;
	Neko;
	Flash9;
	Php;
	Cpp
]

let platform_name = function
	| Cross -> "cross"
	| Flash -> "flash"
	| Js -> "js"
	| Neko -> "neko"
	| Flash9 -> "flash9"
	| Php -> "php"
	| Cpp -> "cpp"

let flash_versions = List.map (fun v ->
	let maj = int_of_float v in
	let min = int_of_float (mod_float (v *. 10.) 10.) in
	v, string_of_int maj ^ (if min = 0 then "" else "_" ^ string_of_int min)
) [9.;10.;10.1;10.2;10.3;11.;11.1;11.2]

let defined ctx v = PMap.mem v ctx.defines

let define ctx v =
	ctx.defines <- PMap.add v () ctx.defines;
	let v = String.concat "_" (ExtString.String.nsplit v "-") in
	ctx.defines <- PMap.add v () ctx.defines;
	ctx.defines_signature <- None

let init_platform com pf =
	com.platform <- pf;
	let name = platform_name pf in
	let forbid acc p = if p = name || PMap.mem p acc then acc else PMap.add p Forbidden acc in
	com.package_rules <- List.fold_left forbid com.package_rules (List.map platform_name platforms);
	define com name

let error msg p = raise (Abort (msg,p))

let platform ctx p = ctx.platform = p

let add_filter ctx f =
	ctx.filters <- f :: ctx.filters

let find_file ctx f =
	let rec loop = function
		| [] -> raise Not_found
		| p :: l ->
			let file = p ^ f in
			if Sys.file_exists file then
				file
			else
				loop l
	in
	loop ctx.class_path

let get_full_path f = try Extc.get_full_path f with _ -> f

(* ------------------------- TIMERS ----------------------------- *)

type timer_infos = {
	name : string;
	mutable start : float list;
	mutable total : float;
}

let get_time = Unix.gettimeofday
let htimers = Hashtbl.create 0

let new_timer name =
	try
		let t = Hashtbl.find htimers name in
		t.start <- get_time() :: t.start;
		t
	with Not_found ->
		let t = { name = name; start = [get_time()]; total = 0.; } in
		Hashtbl.add htimers name t;
		t

let curtime = ref []

let close t =
	let start = (match t.start with
		| [] -> assert false
		| s :: l -> t.start <- l; s
	) in
	let dt = get_time() -. start in
	t.total <- t.total +. dt;
	curtime := List.tl !curtime;
	List.iter (fun ct -> ct.start <- List.map (fun t -> t +. dt) ct.start) !curtime

let timer name =
	let t = new_timer name in
	curtime := t :: !curtime;
	(function() -> close t)

let rec close_time() =
	match !curtime with
	| [] -> ()
	| t :: _ -> close t
