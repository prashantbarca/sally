(* Interpret simple program *)
open Simple_ast;;
open Apron;;
open Format;;

exception Unimplemented of string;;

let from_decls ds =
  (* go through the decl list and collect the nat, int, and float variables *)
  let rec get_vars nats ints floats bools = function
    | [] -> (nats, ints, floats, bools)
    | Simple_ast.Nat_decl n::ds -> get_vars (Var.of_string n::nats) ints floats bools ds
    | Simple_ast.Int_decl i::ds -> get_vars nats (Var.of_string i::ints) floats bools ds
    | Simple_ast.Real_decl f::ds -> get_vars nats ints (Var.of_string f::floats) bools ds
    | Simple_ast.Bool_decl b::ds -> get_vars nats ints floats (Var.of_string b::bools) ds in
  (* create the constraint nat >= 0 for a given variable nat in the environment env *)
  let get_nat_constraints env nat =
    let linexpr = Linexpr1.make env in
    Linexpr1.set_coeff linexpr nat (Coeff.Scalar (Scalar.of_int 1));
    Linexpr1.set_cst linexpr (Coeff.Scalar (Scalar.of_int 0));
    Lincons1.make linexpr Lincons1.SUPEQ in
  (* create the constraint bool = [0, 1] for a given variable bool in the environment env *)
  let get_bool_constraints env bool =
    let linexpr = Linexpr1.make env in
    Linexpr1.set_coeff linexpr bool (Coeff.Scalar (Scalar.of_int (-1)));
    Linexpr1.set_cst linexpr (Coeff.Interval (Interval.of_int 0 1));
    Lincons1.make linexpr Lincons1.EQ in
  let (nats, ints, floats, bools) = get_vars [] [] [] [] ds in
  let env = Environment.make (Array.of_list (nats @ ints @ bools)) (Array.of_list floats) in
  let invs = (List.map (get_nat_constraints env) nats) @ (List.map (get_bool_constraints env) bools) in
  (env, invs);;

let rec is_bool = function
  | And (_, _) -> true
  | Or (_, _) -> true
  | Not _ -> true
  | Ge (_, _) -> true
  | Gt (_, _) -> true
  | Eq (_, _) -> true
  | Neq (_, _) -> true
  | Cond (_, e1, e2) -> (is_bool e1) || (is_bool e2)
  | True -> true
  | False -> true
  | _ -> false;;

let rec arith_to_texpr man ctx v binop e1 e2 =
  let v1 = Var.of_string ((Var.to_string v)^"_l") in
  let v2 = Var.of_string ((Var.to_string v)^"_r") in
  (* Solve branches recursively *)
  let abs_e1 = from_expr man ctx v1 e1 in
  let abs_e2 = from_expr man ctx v2 e2 in
  let abs = Abstract1.unify man abs_e1 abs_e2 in
  let is_int =
    (((Environment.typ_of_var (abs.Abstract1.env) v1) = Environment.INT) &&
    ((Environment.typ_of_var (abs.Abstract1.env) v2) = Environment.INT)) in
  let env =
    if is_int
    then Environment.add (abs.Abstract1.env) [|v|] [||]
    else Environment.add (abs.Abstract1.env) [||] [|v|] in
  let abs = Abstract1.change_environment man abs env false in
  let typ = (* more options exist *)
    if is_int
    then Texpr1.Int
    else Texpr1.Real in
  (* The expression for applying the operator - need to resolve rounding *)
  let texpr =
    Texpr1.of_expr (abs.Abstract1.env)
      (Texpr1.Binop (binop, Texpr1.Var v1, Texpr1.Var v2, typ, Texpr1.Rnd)) in
  (* The new environment *)
  (abs, texpr)

and

arith_from_expr man ctx v binop e1 e2 =
  let (abs, texpr) = arith_to_texpr man ctx v binop e1 e2 in
  (* The assignment of the variable v to the texpr in the new environment *)
  let abs' = Abstract1.assign_texpr man abs v texpr None in
  let is_int = Environment.typ_of_var (abs'.Abstract1.env) v = Environment.INT in
  let env =
    if is_int
    then Environment.add (ctx.Abstract1.env) [|v|] [||]
    else Environment.add (ctx.Abstract1.env) [||] [|v|] in
  Abstract1.change_environment man abs' env false

and

comp_from_expr man ctx v typ e1 e2 =
  let env = ctx.Abstract1.env in
  (* get e1 - e2 *)
  let (abs, texpr) = arith_to_texpr man ctx v Texpr1.Sub e1 e2 in
  (* now make e1 - e2 typ 0 constraint *)
  let tcons = Tcons1.make texpr typ in
  let tcons_arr = Tcons1.array_make abs.Abstract1.env 1 in
  Tcons1.array_set tcons_arr 0 tcons;
  let abs' = Abstract1.change_environment man (Abstract1.meet_tcons_array man abs tcons_arr) env false in
  (* Array.iter (fun x -> printf "env ints: %s\n" (Var.to_string x) ) (fst (Environment.vars env)); *)
  if (Abstract1.is_eq man abs' ctx)
  then from_expr man ctx v True
  else if (Abstract1.is_bottom man (Abstract1.meet man abs' ctx))
  then from_expr man ctx v False
  else
    let env' = Environment.add env [|v|] [||] in
    let linexpr = Linexpr1.make env' in
    Linexpr1.set_coeff linexpr v (Coeff.Scalar (Scalar.of_int (-1)));
    Linexpr1.set_cst linexpr (Coeff.Interval (Interval.of_int 0 1));
    let lincons = Lincons1.make linexpr Lincons1.EQ in
    let lincons_arr = Lincons1.array_make env' 1 in
    Lincons1.array_set lincons_arr 0 lincons;
    (* returned abstract value is one in which the condition is true *)
    let ctx' = Abstract1.change_environment man abs' env' false in
    printf "Cond true: %a@." Abstract1.print ctx';
    Abstract1.meet_lincons_array man ctx' lincons_arr

and

set_var_to_scalar man abs v expr =
  Abstract1.assign_texpr man abs v (Texpr1.of_expr (abs.Abstract1.env) expr) None

and

from_expr man ctx v = function
  | Nat n -> from_expr man ctx v (Int n)
  | Int i ->
      let env = Environment.add (ctx.Abstract1.env) [|v|] [||] in
      let ctx' = Abstract1.change_environment man ctx env false in
      set_var_to_scalar man ctx' v (Texpr1.Cst (Coeff.Scalar (Scalar.of_int i)))
  | Float f ->
      let env = Environment.add (ctx.Abstract1.env) [||] [|v|] in
      let ctx' = Abstract1.change_environment man ctx env false in
      set_var_to_scalar man ctx' v (Texpr1.Cst (Coeff.Scalar (Scalar.of_float f)))
  | Ident e ->
      let (ints, _) = Environment.vars (ctx.Abstract1.env) in
      let env =
        if Array.exists (fun x -> (x = (Var.of_string e))) ints
        then Environment.add (ctx.Abstract1.env) [|v|] [||]
        else Environment.add (ctx.Abstract1.env) [||] [|v|] in
      let ctx' = Abstract1.change_environment man ctx env false in
      set_var_to_scalar man ctx' v (Texpr1.Var (Var.of_string e))
  | Add (e1, e2) -> arith_from_expr man ctx v Texpr1.Add e1 e2
  | Sub (e1, e2) -> arith_from_expr man ctx v Texpr1.Sub e1 e2
  | Mul (e1, e2) -> arith_from_expr man ctx v Texpr1.Mul e1 e2
  | Div (e1, e2) -> arith_from_expr man ctx v Texpr1.Div e1 e2
  | Ge (e1, e2) -> comp_from_expr man ctx v Tcons1.SUPEQ e1 e2
  | Gt (e1, e2) -> comp_from_expr man ctx v Tcons1.SUP e1 e2
  | Eq (e1, e2) -> comp_from_expr man ctx v Tcons1.EQ e1 e2
  | Neq (e1, e2) -> comp_from_expr man ctx v Tcons1.DISEQ e1 e2
  | Not e -> raise (Unimplemented "Not")
  | And (e1, e2) ->
      let e1' = from_expr man ctx v e1 in
      let e2' = from_expr man ctx v e2 in
      let env = Environment.add ctx.Abstract1.env [|v|] [||] in
      let res =
        Abstract1.meet man
          (Abstract1.change_environment man e1' env false)
          (Abstract1.change_environment man e2' env false) in
      if Abstract1.is_bottom man res
      then from_expr man ctx v False
      else res
  | Or (e1, e2) ->
      let e1' = from_expr man ctx v e1 in
      let e2' = from_expr man ctx v e2 in
      let env = Environment.add ctx.Abstract1.env [|v|] [||] in
      Abstract1.join man
        (Abstract1.change_environment man e1' env false)
        (Abstract1.change_environment man e2' env false)
  | Cond (e1, e2, e3) ->
      let v_str = Var.to_string v in
      let v_if = Var.of_string (v_str^"_if") in
      let cond = from_expr man ctx v_if e1 in
      let cond' = Abstract1.change_environment man cond (ctx.Abstract1.env) false in
      if (Abstract1.is_bottom man (Abstract1.unify man cond (from_expr man ctx v_if False)))
      then from_expr man cond' v e2
      else if (Abstract1.is_bottom man (Abstract1.unify man cond (from_expr man ctx v_if True)))
      then from_expr man ctx v e3
      else
        let e2' = from_expr man cond' v e2 in
        let e3' = from_expr man ctx v e3 in
        let e2' =
          if is_bool e2 && Interval.is_zero (Abstract1.bound_variable man e2' v)
          then Abstract1.bottom man ctx.Abstract1.env
          else e2' in
        let e3' =
          if is_bool e3 && Interval.is_zero (Abstract1.bound_variable man e3' v)
          then Abstract1.bottom man ctx.Abstract1.env
          else e3' in
        let env = Environment.lce (e2'.Abstract1.env) (e3'.Abstract1.env) in
        Abstract1.join man
          (Abstract1.change_environment man e2' env false)
          (Abstract1.change_environment man e3' env false)
  | Assign (e1, e2) ->
      Abstract1.unify man
        (from_expr man ctx v e1)
        (from_expr man ctx v e2)
  | True -> from_expr man ctx v (Int 1) (*Abstract1.top man ctx.Abstract1.env*)
  | False -> from_expr man ctx v (Int 0) (*Abstract1.bottom man ctx.Abstract1.env*)
  | Seq (e::es) ->
      let ctx' = Abstract1.change_environment man (from_expr man ctx (Var.of_string "tmp") e) ctx.Abstract1.env false in
      from_expr man ctx' v (Seq es)
  | Seq [] -> ctx;;
      
let simple_to_abs man p =
  let (env, invs') = from_decls p.Simple_ast.decls in
  let invs = invs' in
  from_expr man (Abstract1.top man env) (Var.of_string "tmp") p.expr;;