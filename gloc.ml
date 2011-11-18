(* Copyright (c) 2011 Ashima Arts. All rights reserved.
 * Author: David Sheets
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *)

open Printf
module A = Arg

open Pp_lib
open Pp
open Esslpp_lex
open Esslpp
open Gloc_lib

module List = struct
    include List
    let unique l =
      let h = Hashtbl.create (List.length l) in
      List.iter (fun v -> Hashtbl.replace h v ()) l;
      Hashtbl.fold (fun k () a -> k::a) h []
end

let gloc_version = (0,1,0)
let gloc_distributor = "Ashima Arts"

let default_lang = { dialect=WebGL;
		     version=(1,0,0);
		     accuracy=Best;
		     bond=Warn }
		     
let exec_state = { preprocess=ref false;
		   compile=ref false;
		   verbose=ref false;
		   linectrl=ref true;
		   output=ref None;
		   inputs=ref [];
		   inlang=ref default_lang;
		   outlang=ref default_lang }

let string_of_dialect = function
  | WebGL -> "webgl"
let with_bond bond = fun lang -> { lang with bond }
let with_dialect = function
  | "webgl" -> (fun lang -> { lang with dialect=WebGL })
  | _ -> (fun lang -> lang)
let set_inlang map = fun () -> exec_state.inlang := (map !(exec_state.inlang))
let set_outlang map = fun () -> exec_state.outlang := (map !(exec_state.outlang))

(* TODO: add per warning check args *)
(* TODO: add partial preprocess (only ambiguous conds with dep macros) *)
(* TODO: add partial preprocess (maximal preprocess without semantic change) *)
(* TODO: make verbose more... verbose *)
let arguments =
  ["-c", A.Set exec_state.compile, "produce glo object";
   "-o", A.String (fun o -> exec_state.output := Some o), "output file";
   (*"-w", A.Unit (set_inlang (with_bond Ignore)), "inhibit all warning messages";*)
   "-E", A.Set exec_state.preprocess, "preprocess output source";
   "-L", A.Clear exec_state.linectrl,
   "disregard incoming line control for errors";
   "-x", A.Symbol (["webgl"],(fun s -> set_inlang (with_dialect s) ())),
   " input language";
   "-t", A.Symbol (["webgl"],(fun s -> set_outlang (with_dialect s) ())),
   " target language";
   "-v", A.Set exec_state.verbose, "verbose compilation or version information";
  ]
let anon_fun arg = exec_state.inputs := arg::!(exec_state.inputs)

let string_of_version (maj,min,rev) = sprintf "%d.%d.%d" maj min rev
let usage_msg = sprintf "gloc version %s (%s)"
  (string_of_version gloc_version)
  gloc_distributor

let () = A.parse arguments anon_fun usage_msg

let string_of_tokpos
    ({span={a={file=af; line=al; col=ac};
	    z={file=zf; line=zl; col=zc}}}) =
  let af,al,zf,zl = if !(exec_state.linectrl)
  then (af.src,al.src,zf.src,zl.src)
  else (af.input,al.input,zf.input,zl.input)
  in if af=zf then
      if al=zl
      then if ac=zc
      then sprintf "File %d, line %d, col %d" af al ac
      else sprintf "File %d, line %d, col %d - %d" af al ac zc
      else sprintf "File %d, l%d c%d - l%d c%d" af al ac zl zc
    else sprintf "F%d l%d c%d - F%d l%d c%d" af al ac zf zl zc

let string_of_error = function
  | UnknownBehavior t ->
      sprintf "%s:\nunknown behavior \"%s\"\n" (string_of_tokpos t) t.v
  | UnterminatedComment t ->
      sprintf "%s:\nunterminated comment\n" (string_of_tokpos t)
  | UnterminatedConditional t ->
      sprintf "%s:\nunterminated conditional \"%s\"\n" (string_of_tokpos t)
	(snd (t.scan t.span.a))
  | UnknownCharacter t ->
      sprintf "%s:\nunknown character '%s'\n" (string_of_tokpos t)
	(snd (t.scan t.span.a))
  | LineContinuationUnsupported t ->
      sprintf "%s:\nline continuation officially unsupported\n" (string_of_tokpos t)
  | InvalidDirectiveLocation t ->
      sprintf "%s:\ninvalid directive location\n" (string_of_tokpos t)
  | InvalidDirective t ->
      sprintf "%s:\ninvalid directive \"%s\"\n" (string_of_tokpos t) t.v
  | InvalidOctal t ->
      sprintf "%s:\ninvalid octal constant \"%s\"\n" (string_of_tokpos t) t.v
  | HolyVersion t ->
      sprintf "%s:\nversion must be first semantic token\n" (string_of_tokpos t)
  | UnsupportedVersion t ->
      sprintf "%s:\nversion %d is unsupported\n" (string_of_tokpos t) t.v
  | InvalidVersionBase t ->
      sprintf "%s:\nversion must be specified in decimal\n" (string_of_tokpos t)
  | InvalidLineBase t ->
      sprintf "%s:\nline control arguments must be specified in decimal\n"
	(string_of_tokpos t)
  | InvalidVersionArg t ->
      sprintf "%s:\ninvalid version argument\n" (string_of_tokpos t)
  | InvalidLineArg t ->
      sprintf "%s:\ninvalid line argument\n" (string_of_tokpos t)
  | MacroArgUnclosed t ->
      sprintf "%s:\nunclosed macro argument list\n" (string_of_tokpos t)
  | MacroArgInnerParenUnclosed t ->
      sprintf "%s:\nunclosed inner parenthesis in macro argument list\n"
	(string_of_tokpos t)
  | MacroArgTooFew (t,a,e) ->
      sprintf "%s:\ntoo few macro arguments: expected %d, got %d\n"
	(string_of_tokpos t) e a
  | MacroArgTooMany (t,a,e) ->
      sprintf "%s:\ntoo many macro arguments: expected %d, got %d\n"
	(string_of_tokpos t) e a
  | ReservedKeyword t ->
      sprintf "%s:\n\"%s\" is a reserved keyword and may not be used\n"
	(string_of_tokpos t) t.v
  | RedefineReservedMacro t ->
      sprintf "%s:\n\"%s\" is a reserved macro and may not be redefined\n"
	(string_of_tokpos t) t.v
  | UndefineReservedMacro t ->
      sprintf "%s:\n\"%s\" is a reserved macro and may not be undefined\n"
	(string_of_tokpos t) t.v
  | ErrorDirective t ->
      sprintf "%s:\n%s\n" (string_of_tokpos t) (snd (t.scan t.span.a))
  | UnsupportedPPOp t ->
      sprintf "%s:\n\"%s\" is not supported in preprocessor expressions\n"
	(string_of_tokpos t) (snd (t.scan t.span.a))
  | FloatUnsupported t ->
      sprintf "%s:\nfloating point is not supported in preprocessor expressions\n"
	(string_of_tokpos t)
  | PPCondExprParseError t ->
      sprintf "%s:\nerror parsing conditional expression \"%s\"\n"
	(string_of_tokpos t) (snd (t.scan t.span.a))
  | exn -> sprintf "Unknown error:\n%s\n" (Printexc.to_string exn)

let string_pperror_of_string_tok st =
  sprintf "%s:\nambiguous preprocessor conditional branch: %s\n"
    (string_of_tokpos st)
    st.v

let builtin_macros = List.fold_left
  (fun map (n,f) -> Env.add n f map)
  Env.empty [
    "__LINE__",(fun e w ->
		  {name=None; args=None;
		   stream=fun _ -> [int_replace_word w w.span.a.line.src]});
    "__FILE__",(fun e w ->
		  {name=None; args=None;
		   stream=fun _ -> [int_replace_word w w.span.a.file.src]});
    "__VERSION__",(fun _ _ -> omacro "__VERSION__" (synth_int (Dec,100)));
    "GL_ES",(fun _ _ -> omacro "GL_ES" (synth_int (Dec,1)))
  ]
;;

let start = {file={src=0;input=0};line={src=1;input=1};col=0} in
let lexbuf = Ulexing.from_utf8_channel stdin in
let parse = MenhirLib.Convert.traditional2revised
  (fun t -> t)
  (fun _ -> Lexing.dummy_pos) (* TODO: fixme? *)
  (fun _ -> Lexing.dummy_pos)
  translation_unit in
let ppexpr = try parse (fun () -> lex !(exec_state.inlang) lexbuf) with
  | err -> eprintf "Uncaught exception:\n%s\n" (Printexc.to_string err);
    eprintf "Fatal: unrecoverable internal parser error (1)\n";
    exit 1
in
let () = if (List.length !errors) > 0
then (List.iter (fun e -> eprintf "%s\n" (string_of_error e))
	(List.rev !errors);
      eprintf "Fatal: unrecoverable parse error (2)\n";
      exit 2)
in
let ppexpr = normalize_ppexpr ppexpr in
let ppl = preprocess_ppexpr {macros=Env.empty;
			     builtin_macros;
			     extensions=Env.empty;
			     inmacros=[]} ppexpr in
let () = if (List.length !errors) > 0 then
    (List.iter (fun e -> eprintf "%s\n" (string_of_error e))
       (List.rev !errors);
     eprintf "Fatal: unrecoverable preprocessor error (3)\n";
     exit 3)
in
let env_collect (f1,f2) vl (env,_) = (f1 env, f2 env)::vl in
let get_inmac env = List.map (fun t -> t.v) env.inmacros in
let get_opmac env = Env.fold (fun s _ l -> s::l) env.macros [] in
let slexpr = if !(exec_state.preprocess)
  then if List.length ppl > 1
  then let o = List.fold_left
	 (fun dl pp -> List.fold_left
	   (fun dl om ->
	     if List.exists (fun m -> om.v=m.v) dl then dl else om::dl)
	   dl (fst pp).inmacros)
	 [] ppl
       in List.iter (fun st -> eprintf "%s\n" (string_pperror_of_string_tok st))
       o;
       eprintf "Fatal: unrecoverable preprocessor divergence (4)\n";
       exit 4
  else match ppl with (_,e)::_ -> e
    | [] -> Chunk { span={a=start;z=start};
		    scan=(fun loc -> (loc,""));
		    comments=([],ref []);
		    v=[] }
  else ppexpr
in
let inmac,opmac = List.split
  (List.fold_left (env_collect (get_inmac,get_opmac))
     [] ppl) in
let product = if !(exec_state.compile)
then
  let outlang = !(exec_state.outlang) in
  let target = (string_of_dialect outlang.dialect,outlang.version) in
    try let glo = Glo.compile target ppexpr
	  ~inmac:(List.unique (List.flatten inmac))
	  ~opmac:(List.unique (List.flatten opmac))
	  (List.map snd ppl) in
      Json_io.string_of_json ~compact:(not !(exec_state.verbose))
	(Glo.json_of_glo glo)
    with err ->
      (error (Essl_lib.EsslParseError ((Printexc.to_string err),
				       !(Pp_lib.file),!(Pp_lib.line)));
       List.iter (fun e -> eprintf "%s\n" (string_of_error e))
	 (List.rev !errors);
       eprintf "Fatal: unrecoverable parse error (5)\n";
       exit 5)
else string_of_ppexpr start slexpr
in let out = match !(exec_state.output) with
  | None -> stdout
  | Some fn -> open_out fn
in fprintf out "%s\n" product
(*;
printf "%s\n" (string_of_ppexpr_tree ppexpr)*)
