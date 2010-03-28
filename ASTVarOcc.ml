open Camlp4
open PreCast
open Ast

let pp = Format.fprintf

(* Initialize variable *)
let level = ref 0 (* level of the current var *)
let varname = ref "" (* varname (searched var)*)
let varloc = ref "" (* var location (searched var)*)
let varlevel = ref 0 (* var level (searched var)*)
let varExpr = ref ""
let foundleft = ref false
let varwrite = ref false (* var status (read or write) *)
let evaluate = ref false (* indicate if we need to increase level (not the same var)*)
let evaluated = ref false (* indicate that the level increased *)
let accessmodule = ref false
let modulename = ref ""
let varlevelfoundinmodule = ref 0 (* varlevel found in module *)
let listmodule = ref [("", 0)]
let maxlevel = ref 0 (* var maxlevel *)
let lastvarlevel = ref 0 (* lastlevel found *)
let lastExpr = ref "" (* last expression found *)
let listvars = ref [("",(0, ""))] (* list of all vars *)
let dontwant = ["+";"-";"*";"/"] (* we don't allow opertor as varname *)

let string_of_loc loc =
	(string_of_int (Loc.start_off loc)) ^ "," ^ (string_of_int (Loc.stop_off loc))

let lt = (Str.regexp "<")
let gt = (Str.regexp ">")
let amp = (Str.regexp "&")
let apos = (Str.regexp "'")
let quot = (Str.regexp "\"")

	
(* escape XML chars *)
let escape_string str: string =
	let str = Str.global_replace lt "&lt;" str in
	let str = Str.global_replace gt "&gt;" str in
	let str = Str.global_replace amp "&amp;" str in
	let str = Str.global_replace apos "&apos;" str in
	let str = Str.global_replace quot "&quot;" str in
	str

let rec print_ident f = function (* The type of identifiers (including path like Foo(X).Bar.y) *)
	(* i . i *) (** Access in module *)
	| IdAcc(loc, ident1, ident2) -> 

			lastExpr := "IdAcc";
			(*let currlevel = !level in*)
				(*level := !lastvarlevel;*)
				(*level := !maxlevel;*)
				print_ident f ident1;
				accessmodule := true;
				print_ident f ident2;
				(*level := currlevel;*)
				accessmodule := false;
				lastExpr := ""
	(* i i *) (** Application *)
	| IdApp(loc, ident1, ident2) ->	print_ident f ident1; print_ident f ident2
		
	(* foo *) (** Lowercase identifier *)
	| IdLid(loc, name) -> 
		begin
			let name = (escape_string name) in
				if (name = !varname) then
				begin
					if (!evaluate) then
					begin
						level := !maxlevel + 1;
						if (!level > !maxlevel) then
							maxlevel := !level;
						evaluate := false;
						if (!lastExpr = "StValLeft") then
						begin
							foundleft := true;
							level := !lastvarlevel + 1;
							lastvarlevel := !level;
						end;
						evaluated := true
					end;
					let string = "<var loc='"^(string_of_loc loc)^"' write='"^(string_of_bool !varwrite)^"'><name>"^(escape_string name)^"</name></var>" in
						if (!lastExpr = "IdAcc") then
						begin
							if (!accessmodule) then
							begin
								try
									let correctlevel = snd(List.find (fun x -> fst(x) = !modulename) !listmodule) in
										listvars := List.append !listvars ((!lastExpr,(correctlevel, string))::[]);
									if (!varloc = (string_of_loc loc)) then
									begin
							 		  varlevel := correctlevel;
										varExpr := !lastExpr;
									end;
								with
									| Not_found -> ()
							end
						end
						else
						begin
							if (!varloc = (string_of_loc loc)) then
							begin
							  varlevel := !level;
								varExpr := !lastExpr;
							end;
							listvars := List.append !listvars ((!lastExpr,(!level, string))::[])
						end;
					varwrite := false;
				end
				else
					if (!evaluate) then
					begin
						evaluate := false
					end
					else
						();
		end
		
	(* Bar *) (** Uppercase identifier *)
	| IdUid(loc, name) ->
		begin
			let name = (escape_string name) in
				if (name = !varname) then
				begin
					if (!evaluate) then
					begin
						level := !maxlevel + 1;
						if (!level > !maxlevel) then
							maxlevel := !level;
						evaluate := false;
						evaluated := true
					end;
					if (!varloc = (string_of_loc loc)) then
									varlevel := !level;
						
					let string = "<var loc='"^(string_of_loc loc)^"' write='"^(string_of_bool !varwrite)^"'><name>"^name^"</name></var>" in
						if (!lastExpr = "IdAcc") then
						begin
								modulename := name;
						end
						else
							listvars := List.append !listvars ((!lastExpr,(!level, string))::[]);
					varwrite := false;
				end
				else
					modulename := name;
		end
		
	(* $s$ *) (** Antiquotation *)
	| IdAnt(loc, name) -> ()

and print_ctyp f = function (* Representation of types                                     *)
	(** Empty type *)
	| TyNil(loc) -> ()
	(* t as t *) (* list 'a as 'a *) (** Type aliasing *)
	| TyAli(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* _ *) (** Wildcard *)
	| TyAny(loc) -> ()
	(* t t *) (* list 'a *) (** Application *)
	| TyApp(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* t) -> t *) (* int) -> string *) (** Arrow *)
	| TyArr(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* #i *) (* #point *) (** Class type *)
	| TyCls(loc, ident1) -> print_ident f ident1
	(* ~s:t *) (** Label type *)
	| TyLab(loc, name, ctyp1) -> print_ctyp f ctyp1
	(* i *) (* Lazy.t *) (** Type identifier *)
	| TyId(loc, ident1) -> print_ident f ident1
	(* t == t *) (* type t = [ A | B ] == Foo.t *) (** Type manifest *)
	| TyMan(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* type t 'a 'b 'c = t constraint t = t constraint t = t *) (** Type declaration *)
	| TyDcl(loc, name, ctyps, ctyp1, (*TODO*) constraints) -> print_ctyps f ctyps; print_ctyp f ctyp1; print_constraints f constraints
	(* < (t)? (..)? > *) (* < move : int) -> 'a .. > as 'a  *) (**   Object type *)
	| TyObj(loc, ctyp1, meta_bool1) -> print_ctyp f ctyp1;
	(* ?s:t *) (** Optional label type *)
	| TyOlb(loc, name, ctyp1) -> print_ctyp f ctyp1
	(* ! t . t *) (* ! 'a . list 'a) -> 'a *) (** Polymorphic type *)
	| TyPol(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* 's *)
	| TyQuo(loc, name) -> ()
	(* +'s *)
	| TyQuP(loc, name) -> ()
	(* -'s *)
	| TyQuM(loc, name) -> ()
	(* `s *) (** Polymorphic variant *)
	| TyVrn(loc, name) -> ()
	(* { t } *) (* { foo : int ; bar : mutable string } *) (** Record *)
	| TyRec(loc, ctyp1) -> ()
	(* t : t *) (** Field declaration *)
	| TyCol(loc, ctyp1, ctyp2) -> ()
	(* t; t *) (** Semicolon-separated type list *)
	| TySem(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* t, t *) (** Comma-separated type list *)
	| TyCom(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* [ t ] *) (* [ A of int, string | B ] *) (** Sum type *)
	| TySum(loc, ctyp1) -> print_ctyp f ctyp1
	(* t of t *) (* A of int *)
	| TyOf(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* t, t *)
	| TyAnd(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* t | t *) (** "Or" pattern between types *)
	| TyOr(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* private t *) (** Private type *)
	| TyPrv(loc, ctyp1) -> print_ctyp f ctyp1
	(* mutable t *) (** Mutable type *)
	| TyMut(loc, ctyp1) -> print_ctyp f ctyp1
	(* ( t ) *) (* (int * string) *) (** Tuple *)
	| TyTup(loc, ctyp1) -> print_ctyp f ctyp1
	(* t * t *)
	| TySta(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* [ = t ] *)
	| TyVrnEq(loc, ctyp1) -> print_ctyp f ctyp1
	(* [ > t ] *)
	| TyVrnSup(loc, ctyp1) -> print_ctyp f ctyp1
	(* [ < t ] *)
	| TyVrnInf(loc, ctyp1) -> print_ctyp f ctyp1
	(* [ < t > t ] *)
	| TyVrnInfSup(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* t & t *)
	| TyAmp(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* t of & t *)
	| TyOfAmp(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* $s$ *) (** Antiquotation *)
	| TyAnt(loc, name) -> ()

and print_patt f = function (* The type of patterns                                       *)
	(**   Empty pattern *)
	| PaNil(loc) -> ()
	(* i *) (** Identifier *)
	| PaId(loc, ident1) -> print_ident f ident1
	(* p as p *) (* (Node x y as n) *) (** Alias *)
	| PaAli(loc, patt1, patt2) -> print_patt f patt1; print_patt f patt2
	(* $s$ *) (** Antiquotation *)
	| PaAnt(loc, name) -> ()
	(* _ *) (** Wildcard *)
	| PaAny(loc) -> ()
	(* p p *) (* fun x y) -> *) (** Application *)
	| PaApp(loc, patt1, patt2) -> evaluate:= true; print_patt f patt1; evaluate:=true;print_patt f patt2
	(* [| p |] *) (** Array *)
	| PaArr(loc, patt1) -> print_patt f patt1
	(* p, p *) (** Comma-separated pattern list *)
	| PaCom(loc, patt1, patt2) -> 
		print_patt f patt1; 
		evaluate := true;
		print_patt f patt2
	(* p; p *) (** Semicolon-separated pattern list *)
	| PaSem(loc, patt1, patt2) -> print_patt f patt1; print_patt f patt2
	(* c *) (* 'x' *) (** Character *)
	| PaChr(loc, name) -> ()
	(** Integer *)
	| PaInt(loc, name) -> ()
	(** Int32 *)
	| PaInt32(loc, name) -> ()
	(** Int64 *)
	| PaInt64(loc, name) -> ()
	(** NativeInt *)
	| PaNativeInt(loc, name) -> ()
	(** Float *)
	| PaFlo(loc, name) -> ()
	(* ~s or ~s:(p) *) (** Label *)
	| PaLab(loc, name, patt1) -> print_patt f patt1
	(* ?s or ?s:(p) *) (** Optional label *)
	| PaOlb(loc, name, patt1) -> print_patt f patt1
	(* ?s:(p = e) or ?(p = e) *) (** Optional label with default value *)
	| PaOlbi(loc, name, patt1, expr1) -> print_patt f patt1; print_expr f expr1
	(* p | p *) (** Or *)
	| PaOrp(loc, patt1, patt2) -> print_patt f patt1; print_patt f patt2
	(* p .. p *) (** Pattern range *)
	| PaRng(loc, patt1, patt2) -> print_patt f patt1; print_patt f patt2
	(* { p } *) (** Record *)
	| PaRec(loc, patt1) -> print_patt f patt1
	(* i = p *) (** Equality *)
	| PaEq(loc, ident1, patt1) -> print_ident f ident1; print_patt f patt1
	(* s *) (** String *)
	| PaStr(loc, name) -> ()
	(* ( p ) *) (** Tuple *)
	| PaTup(loc, patt1) -> 
		lastExpr := "PaTup";
		print_patt f patt1
	(* (p : t) *) (** Type constraint *)
	| PaTyc(loc, patt1, ctyp1) -> print_patt f patt1; print_ctyp f ctyp1
	(* #i *)
	| PaTyp(loc, ident1) -> print_ident f ident1
	(* `s *) (** Polymorphic variant *)
	| PaVrn(loc, name) -> ()
	(* lazy p *)
	| PaLaz(loc, patt1) -> print_patt f patt1
and print_expr f = function (* The type of expressions                                    *)
	(** Empty expression *)
	| ExNil(loc) -> ()
	(* i *) (**   Identifier *)
	| ExId(loc, ident1) -> 
		print_ident f ident1;
	(* e.e *) (** Access in module *)
	| ExAcc(loc, expr1, expr2) -> 
		evaluate := false;
		print_expr f expr1;
		print_expr f expr2
	(* $s$ *) (** Antiquotation *)
	| ExAnt(loc, name) -> ()
	(* e e *) (** Application *)
	| ExApp(loc, expr1, expr2) -> 
		varwrite := false;
		print_expr f expr1;
		print_expr f expr2;
	(* e.(e) *) (** Array access *)
	| ExAre(loc, expr1, expr2) -> print_expr f expr1; print_expr f expr2
	(* [| e |] *) (** Array declaration *)
	| ExArr(loc, expr1) -> print_expr f expr1
	(* e; e *) (** Semicolon-separated expression list *)
	| ExSem(loc, expr1, expr2) -> print_expr f expr1; print_expr f expr2
	(* assert False *) (** assert False *)
	| ExAsf(loc) -> ()
	(* assert e *) (** assert e *)
	| ExAsr(loc, expr1) -> print_expr f expr1
	(* e := e *) (** Assignment *)
	| ExAss(loc, expr1, expr2) -> evaluate := false; varwrite := true; print_expr f expr1; print_expr f expr2
	(* 'c' *) (** Character *)
	| ExChr(loc, name) -> ()
	(* (e : t) or (e : t :> t) *) (** Coercion *)
	| ExCoe(loc, expr1, ctyp1, ctyp2) -> print_expr f expr1; print_ctyp f ctyp1; print_ctyp f ctyp2
	(* 3.14 *) (** Float *)
	| ExFlo(loc, name) -> ()
	(* for s = e to/downto e do { e } *) (** For loop *)
	| ExFor(loc, name, expr1, expr2, meta_bool1, expr3) -> print_expr f expr1; print_expr f expr2; print_expr f expr3
	(* fun [ mc ] *) (** Function with match case *)
	| ExFun(loc, match_case1) -> 
		if (!level > !maxlevel) then
			maxlevel := !level;
		evaluate := true;
		varwrite := true;
		print_match_case f match_case1;
		if (!evaluated) then
			begin
				evaluated := false
			end;
	(* if e then e else e *) (** if/then/else *)
	| ExIfe(loc, expr1, expr2, expr3) -> 
		evaluate := false;
		varwrite := false;
		print_expr f expr1; print_expr f expr2; print_expr f expr3
	(* 42 *) (** Int *)
	| ExInt(loc, name) -> ()
	(** Int32 *)
	| ExInt32(loc, name) -> ()
	(** Int64 *)
	| ExInt64(loc, name) -> ()
	(** NativeInt *)
	| ExNativeInt(loc, name) -> ()
	(* ~s or ~s:e *) (** Label argument with/without expression *)
	| ExLab(loc, name, expr1) -> print_expr f expr1
	(* lazy e *) (** Lazy evaluation *)
	| ExLaz(loc, expr1) -> print_expr f expr1
	(* let b in e or let rec b in e *) (** Let statement with/without recursion *)
	| ExLet(loc, meta_bool1, binding1, expr1) -> 
		lastExpr := "ExLet";
		let levelbefore = !level in
		if (!level > !maxlevel) then
			maxlevel := !level;
		evaluate := true;
		varwrite := true;
		print_binding f false binding1;
		print_expr f expr1;
		level := levelbefore;
		lastExpr := "";
		if (!evaluated) then
			begin
				level := levelbefore;
				evaluated := false
			end;		
	
	(* let module s = me in e *) (** "Let module in" construct *)
	| ExLmd(loc, name, module_expr1, expr1) -> print_module_expr f module_expr1; print_expr f expr1
	(* match e with [ mc ] *) (** Match case *)
	| ExMat(loc, expr1, match_case1) -> print_expr f expr1; print_match_case f match_case1
	(* new i *) (** New object *)
	| ExNew(loc, ident1) -> print_ident f ident1
	(* object ((p))? (cst)? end *) (** Object declaration *)
	| ExObj(loc, patt1, class_str_item1) -> print_patt f patt1; print_class_str_item f class_str_item1
	(* ?s or ?s:e *) (** Optional label *)
	| ExOlb(loc, name, expr1) -> print_expr f expr1
	(* {< rb >} *) (** Overloading *)
	| ExOvr(loc, rec_binding1) -> print_rec_binding f rec_binding1
	(* { rb } or { (e) with rb } *) (** Record *)
	| ExRec(loc, rec_binding1, expr1) -> print_rec_binding f rec_binding1; print_expr f expr1
	(* do { e } *) (** Sequence with "do" statement *)
	| ExSeq(loc, expr1) -> print_expr f expr1
	(* e#s *) (** Method call *)
	| ExSnd(loc, expr1, name) -> print_expr f expr1;
	(* e.[e] *) (** String access *)
	| ExSte(loc, expr1, expr2) -> print_expr f expr1; print_expr f expr2
	(* s *) (* "foo" *) (** String *)
	| ExStr(loc, name) -> ()
	(* try e with [ mc ] *) (** "Try .. with" construct *)
	| ExTry(loc, expr1, match_case1) -> print_expr f expr1; print_match_case f match_case1
	(* (e) *) (** Tuple *)
	| ExTup(loc, expr1) -> print_expr f expr1
	(* e, e *) (** Comma-separated expression list *)
	| ExCom(loc, expr1, expr2) -> 
		print_expr f expr1;
		print_expr f expr2
	(* (e : t) *) (** Type constraint *)
	| ExTyc(loc, expr1, ctyp1) -> print_expr f expr1; print_ctyp f ctyp1
	(* `s *) (** Polymorphic variant *)
	| ExVrn(loc, name) -> ()
	(* while e do { e } *) (** "While .. do" constraint *)
	| ExWhi(loc, expr1, expr2) -> 
		evaluate := false;
		varwrite := false;
		print_expr f expr1; print_expr f expr2
and print_module_type f = function (* The type of module types                                   *)
	| MtNil(loc) -> ()
	(* i *) (* A.B.C *)
	| MtId(loc, ident1) -> print_ident f ident1
	(* functor (s : mt)) -> mt *)
	| MtFun(loc, name, module_type1, module_type2) -> print_module_type f module_type1; print_module_type f module_type2
	(* 's *)
	| MtQuo(loc, name) -> ()
	(* sig sg end *)
	| MtSig(loc, sig_item1) -> print_sig_item f sig_item1
	(* mt with wc *)
	| MtWit(loc, module_type1, with_constr1) -> print_module_type f module_type1; print_with_constr f with_constr1
	(* $s$ *)
	| MtAnt(loc, name) -> ()
and print_sig_item f = function (* The type of signature items                                *)
	| SgNil(loc) -> ()
	(* class cict *)
	| SgCls(loc, class_type1) -> print_class_type f class_type1
	(* class type cict *)
	| SgClt(loc, class_type1) -> print_class_type f class_type1
	(* sg ; sg *)
	| SgSem(loc, sig_item1, sig_item2) -> print_sig_item f sig_item1; print_sig_item f sig_item2
	(* # s or # s e *)
	| SgDir(loc, name, expr1) -> print_expr f expr1
	(* exception t *)
	| SgExc(loc, ctyp1) -> print_ctyp f ctyp1
	(* external s : t = s ... s *)
	| SgExt(loc, name, ctyp1, strings (*meta_list string*)) -> print_ctyp f ctyp1;
	(* include mt *)
	| SgInc(loc, module_type1) -> print_module_type f module_type1
	(* module s : mt *)
	| SgMod(loc, name, module_type1) -> print_module_type f module_type1
	(* module rec mb *)
	| SgRecMod(loc, module_binding1) -> print_module_binding f module_binding1
	(* module type s = mt *)
	| SgMty(loc, name, module_type1) -> print_module_type f module_type1
	(* open i *)
	| SgOpn(loc, ident1) -> print_ident f ident1
	(* type t *)
	| SgTyp(loc, ctyp1) -> print_ctyp f ctyp1
	(* value s : t *)
	| SgVal(loc, name, ctyp1) -> print_ctyp f ctyp1
	(* $s$ *)
	| SgAnt(loc, name) -> ()
and print_with_constr f = function (* The type of `with' constraints                             *)
	| WcNil(loc) -> ()
	(* type t = t *)
	| WcTyp(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* module i = i *)
	| WcMod(loc, ident1, ident2) -> print_ident f ident1; print_ident f ident2
	(* wc, wc *)
	| WcAnd(loc, with_constr1, with_constr2) -> print_with_constr f with_constr1; print_with_constr f with_constr2
	(* $s$ *)
	| WcAnt(loc, name) -> ()
and print_binding f isRec = function (* The type of let bindings                                   *)
	| BiNil(loc) -> ()
	(* bi, bi *) (* let a = 42, print_c f = function 43 *)
	| BiAnd(loc, binding1, binding2) -> print_binding f isRec binding1; evaluate:=true;print_binding f isRec binding2
	(* p = e *) (* let patt = expr *)
	| BiEq(loc, patt1, expr1) -> 
		let decreased = ref false in
		if (!lastExpr = "StVal" || !lastExpr = "ExLet") then
			lastExpr := !lastExpr^"Left";
		print_patt f patt1; 
		if (!lastExpr = "StValLeft" && !foundleft) then
		begin
			decreased := true;
			if (not(isRec)) then
				level := !level -1;
			foundleft := false;
			lastExpr := "StValRight"
		end
		else 
			if (!lastExpr = "ExLetLeft") then
				lastExpr := "ExLetRight";
		print_expr f expr1;
		if (!decreased = true) then
			level := !level + 1;
	(* $s$ *)
	| BiAnt(loc, name) -> ()
and print_rec_binding f = function (* The type of record definitions                             *)
	(** Empty record definition *)
	| RbNil(loc) -> ()
	(* rb ; rb *)
	| RbSem(loc, rec_binding1, rec_binding2) -> print_rec_binding f rec_binding1; print_rec_binding f rec_binding2
	(* i = e *)
	| RbEq(loc, ident1, expr1) -> print_ident f ident1; print_expr f expr1
	(* $s$ *)
	| RbAnt(loc, name) -> ()
and print_module_binding f = function (* The type of recursive module definitions                   *)
	(** Empty module definition *)
	| MbNil(loc) -> ()
	(* mb, mb *) (* module rec (s : mt) = me, (s : mt) = me *)
	| MbAnd(loc, module_binding1, module_binding2) -> print_module_binding f module_binding1; print_module_binding f module_binding2
	(* s : mt = me *)
	| MbColEq(loc, name, module_type1, module_expr1) -> print_module_type f module_type1; print_module_expr f module_expr1
	(* s : mt *)
	| MbCol(loc, name, module_type1) -> print_module_type f module_type1
	(* $s$ *)
	| MbAnt(loc, name) -> ()
and print_match_case f = function (* The type of cases for match/function/try constructions     *)
	(** Empty case *)
	| McNil(loc) -> ()
	(* a | a *)
	| McOr(loc, match_case1, match_case2) -> print_match_case f match_case1; print_match_case f match_case2
	(* p (when e)?) -> e *)
	| McArr(loc, patt1, expr1, expr2) -> print_patt f patt1; print_expr f expr1; print_expr f expr2
	(* $s$ *)
	| McAnt(loc, name) -> ()
and print_module_expr f = function (* The type of module expressions                             *)
	(** Empty module expression *)
	| MeNil(loc) -> ()
	(* i *)
	| MeId(loc, ident1) -> print_ident f ident1
	(* me me *)
	| MeApp(loc, module_expr1, module_expr2) -> print_module_expr f module_expr1; print_module_expr f module_expr2
	(* functor (s : mt)) -> me *)
	| MeFun(loc, name, module_type1, module_expr1) -> print_module_type f module_type1; print_module_expr f module_expr1
	(* struct st end *)
	| MeStr(loc, str_item1) -> print_str_item f str_item1
	(* (me : mt) *)
	| MeTyc(loc, module_expr1, module_type1) -> print_module_expr f module_expr1; print_module_type f module_type1
	(* $s$ *)
	| MeAnt(loc, name) -> ()

and print_str_item f = function (* The type of structure items                                *)
	| StNil(loc) -> ()
	(* class cice *)
	| StCls(loc, class_expr1) -> print_class_expr f class_expr1
	(* class type cict *)
	| StClt(loc, class_type1) -> print_class_type f class_type1
	(* st ; st *)
	| StSem(loc, str_item1, str_item2) -> print_str_item f str_item1; print_str_item f str_item2
	(* # s or # s e *)
	| StDir(loc, name, expr1) -> print_expr f expr1
	(* exception t or exception t = i *)
	| StExc(loc, ctyp1, option_ident) -> print_ctyp f ctyp1; print_option_ident f option_ident
	(* e *)
	| StExp(loc, expr1) -> print_expr f expr1
	(* external s : t = s ... s *)
	| StExt(loc, name, ctyp1, (*TODO*) strings(*meta_list string*)) -> print_ctyp f ctyp1;
	(* include me *)
	| StInc(loc, module_expr1) -> print_module_expr f module_expr1
	(* module s = me *)
	| StMod(loc, name, module_expr1) ->
		modulename := escape_string name;
		let length_atPre = List.length !listvars in 
		print_module_expr f module_expr1;
		if (List.length !listvars != length_atPre) then
			listmodule := List.append !listmodule ((!modulename, !maxlevel)::[]);
		lastvarlevel := !maxlevel;
		level := !maxlevel;
		modulename := ""
		
	(* module rec mb *)
	| StRecMod(loc, module_binding1) -> print_module_binding f module_binding1
	(* module type s = mt *)
	| StMty(loc, name, module_type1) -> print_module_type f module_type1
	(* open i *)
	| StOpn(loc, ident1) -> print_ident f ident1
	(* type t *)
	| StTyp(loc, ctyp1) -> print_ctyp f ctyp1
	(* value (rec)? bi *)
	| StVal(loc, meta_bool1, binding1) -> 
		lastExpr := "StVal";
		if (!level > !maxlevel) then
			maxlevel := !level;
		(*level := !maxlevel;*)
		evaluate := true;
		varwrite := true;
		level := !level - 1;
		print_binding f (meta_bool1 = BTrue) binding1;
		level := !level + 1;
		lastExpr := "";
		if (!evaluated) then
			begin
				evaluated := false
			end;
		
	(* $s$ *)
	| StAnt(loc, name) -> ()
and print_class_type f = function (* The type of class types                                    *)
	| CtNil(loc) -> ()
	(* (virtual)? i ([ t ])? *)
	| CtCon(loc, meta_bool1, ident1, ctyp1) -> print_ident f ident1; print_ctyp f ctyp1
	(* [t]) -> ct *)
	| CtFun(loc, ctyp1, class_type1) -> print_ctyp f ctyp1; print_class_type f class_type1
	(* object ((t))? (csg)? end *)
	| CtSig(loc, ctyp1, class_sig_item1) -> print_ctyp f ctyp1; print_class_sig_item f class_sig_item1
	(* ct, ct *)
	| CtAnd(loc, class_type1, class_type2) -> print_class_type f class_type1; print_class_type f class_type2
	(* ct : ct *)
	| CtCol(loc, class_type1, class_type2) -> print_class_type f class_type1; print_class_type f class_type2
	(* ct = ct *)
	| CtEq(loc, class_type1, class_type2) -> print_class_type f class_type1; print_class_type f class_type2
	(* $s$ *)
	| CtAnt(loc, name) -> ()
and print_class_sig_item f = function (* The type of class signature items                          *)
	| CgNil(loc) -> ()
	(* type t = t *)
	| CgCtr(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* csg ; csg *)
	| CgSem(loc, class_sig_item1, class_sig_item2) -> print_class_sig_item f class_sig_item1; print_class_sig_item f class_sig_item2
	(* inherit ct *)
	| CgInh(loc, class_type1) -> print_class_type f class_type1
	(* method s : t or method private s : t *)
	| CgMth(loc, name, meta_bool1, ctyp1) -> print_ctyp f ctyp1
	(* value (virtual)? (mutable)? s : t *)
	| CgVal(loc, name, meta_bool1, meta_bool2, ctyp1) -> print_ctyp f ctyp1
	(* method virtual (mutable)? s : t *)
	| CgVir(loc, name, meta_bool1, ctyp1) -> print_ctyp f ctyp1
	(* $s$ *)
	| CgAnt(loc, name) -> ()
and print_class_expr f = function (* The type of class expressions                              *)
	| CeNil(loc) -> ()
	(* ce e *)
	| CeApp(loc, class_expr1, expr1) -> print_class_expr f class_expr1; print_expr f expr1
	(* (virtual)? i ([ t ])? *)
	| CeCon(loc, meta_bool1, ident1, ctyp1) -> print_ident f ident1; print_ctyp f ctyp1
	(* fun p -> ce *)
	| CeFun(loc, patt1, class_expr1) -> print_patt f patt1; print_class_expr f class_expr1
	(* let (rec)? bi in ce *)
	| CeLet(loc, meta_bool1, binding1, class_expr1) -> print_binding f (meta_bool1 = BTrue) binding1; print_class_expr f class_expr1
	(* object ((p))? (cst)? end *)
	| CeStr(loc, patt1, class_str_item1) -> print_patt f patt1; print_class_str_item f class_str_item1
	(* ce : ct *)
	| CeTyc(loc, class_expr1, class_type1) -> print_class_expr f class_expr1; print_class_type f class_type1
	(* ce, ce *)
	| CeAnd(loc, class_expr1, class_expr2) -> print_class_expr f class_expr1; print_class_expr f class_expr2
	(* ce = ce *)
	| CeEq(loc, class_expr1, class_expr2) -> print_class_expr f class_expr1; print_class_expr f class_expr2
	(* $s$ *)
	| CeAnt(loc, name) -> ()
and print_class_str_item f = function (* The type of class structure items                          *)
	| CrNil(loc) -> ()
	(* cst ; cst *)
	| CrSem(loc, class_str_item1, class_str_item2) -> print_class_str_item f class_str_item1; print_class_str_item f class_str_item2;
	(* type t = t *)
	| CrCtr(loc, ctyp1, ctyp2) -> print_ctyp f ctyp1; print_ctyp f ctyp2
	(* inherit ce or inherit ce as s *)
	| CrInh(loc, class_expr1, name) -> print_class_expr f class_expr1
	(* initializer e *)
	| CrIni(loc, expr1) -> print_expr f expr1
	(* method (private)? s : t = e or method (private)? s = e *)
	| CrMth(loc, name, meta_bool1, expr1, ctyp1) -> print_expr f expr1; print_ctyp f ctyp1
	(* value (mutable)? s = e *)
	| CrVal(loc, name, meta_bool1, expr1) -> print_expr f expr1
	(* method virtual (private)? s : t *)
	| CrVir(loc, name, meta_bool1, ctyp1) -> print_ctyp f ctyp1
	(* value virtual (private)? s : t *)
	| CrVvr(loc, name, meta_bool1, ctyp1) -> print_ctyp f ctyp1
	(* $s$ *)
	| CrAnt(loc, name) -> ()

and print_ctyps f = function
	| [] -> pp f ""
	| x:: r -> print_ctyp f x; print_ctyps f r

and print_constraints f = function
	| [] -> pp f ""
	| (ctyp1, ctyp2):: r -> print_ctyp f ctyp1; print_ctyp f ctyp2; print_constraints f r

and print_option_ident f = function
	| ONone -> pp f ""
	| OSome(x) -> print_ident f x
	| OAnt(str) -> ()

let print_ast_in_xml channel argument argument2=
	
	(* Initialize variables *)
	level := 0;
  varname := "";
  varloc := "";
  varlevel :=  0;
  evaluate := false;
  evaluated := false;
	modulename := "";
	accessmodule := false;
	varlevelfoundinmodule := 0;
	listmodule := [];
  maxlevel := 0;
  lastvarlevel := 0;
  lastExpr := "";
  listvars := [];
	varname := argument;
	varloc := argument2;
	
	match Deserializerp4.deserialize_chan channel with
	| Some parse_tree ->
			if (not(List.exists (fun x -> x = !varname) dontwant)) then
				print_str_item Format.str_formatter parse_tree;
			print_endline "<varocc>";
			if (!varExpr <> "ExLetLeft" && !varExpr <> "ExLetRight") then
			begin
				(* write all vars with the search level *)
				let currlist = ref !listvars in
					if (List.exists (fun x -> fst(x) = "ExLetLeft" && fst(snd(x)) = !varlevel) !listvars) then
						currlist := (List.filter (fun x -> fst(x) <> "ExLetLeft" && fst(x) <> "ExLetRight") !listvars);
			  	while((List.length !currlist)>0) do
						let elem = (List.hd !currlist) in
					  	let level = fst(snd(elem)) in
							if ( level> 0 && level == !varlevel) then
								print_endline (snd(snd(elem)));
						currlist := List.tl !currlist;
					done;
			end
			else
			begin
				let currlist = ref !listvars in
					if (List.exists (fun x -> fst(x) = "ExLetLeft" && fst(snd(x)) = !varlevel) !listvars) then
						currlist := (List.filter (fun x -> fst(x) = "ExLetLeft" || fst(x) = "ExLetRight") !listvars);
			  	while((List.length !currlist)>0) do
						let elem = (List.hd !currlist) in
							let level = fst(snd(elem)) in
								if ( level> 0 && level == !varlevel) then
									print_endline (snd(snd(elem)));
								currlist := List.tl !currlist;
					done;
			end;
			print_string "</varocc>";
			Format.flush_str_formatter ()
	| None -> ""

