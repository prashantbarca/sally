/*
 * context.h
 *
 *  Created on: Nov 21, 2014
 *      Author: dejan
 */

#pragma once

#include "expr/term_manager.h"

#include "system/state_type.h"
#include "system/state_formula.h"
#include "system/transition_formula.h"
#include "system/transition_system.h"

#include "utils/exception.h"
#include "utils/symbol_table.h"

namespace sal2 {
namespace system {

class context_exception : public exception {
public:
  context_exception(std::string msg) : exception(msg) {}
};

/**
 * A context to create and keep track of transition systems, their types,
 * formulas, properties...
 */
class context {

  /** The term manager */
  expr::term_manager& d_term_manager;

  /** Symbol table for state types */
  utils::symbol_table<state_type*> d_state_types;

  /** Symbol table for state formulas */
  utils::symbol_table<state_formula*> d_state_formulas;

  /** Symbol table for state transition formulas */
  utils::symbol_table<transition_formula*> d_transition_formulas;

  /** Symbol table for transition systems */
  utils::symbol_table<transition_system*> d_transition_systems;

public:

  /** Construct the parser state */
  context(expr::term_manager& tm);

  /** Returns the term manager for the parser */
  expr::term_manager& tm() { return d_term_manager; }

  /** Add a state type with the given id (to be managed by the context) */
  void add_state_type(std::string id, state_type* st);

  /** Get the state type with the given id */
  const state_type* get_state_type(std::string id) const;

  /** True if id exists */
  bool has_state_type(std::string id) const;

  /** Add a new state formula with the given id (to be managed by the context) */
  void add_state_formula(std::string id, state_formula* sf);

  /** Get the state formula with the given id */
  const state_formula* get_state_formula(std::string id) const;

  /** True if id exists */
  bool has_state_formula(std::string id) const;

  /** Add a new state transition with the given id (to be managed by the context) */
  void add_transition_formula(std::string id, transition_formula* tf);

  /** Get the state transition formula with the given id */
  const transition_formula* get_transition_formula(std::string id) const;

  /** True if id exists */
  bool has_transition_formula(std::string id) const;

  /** Add a new state transition system with the givwen id (to be managed by the context) */
  void add_transition_system(std::string id, transition_system* ts);

  /** Get the transition system with the given id */
  const transition_system* get_transition_system(std::string id) const;

  /** True if id exists */
  bool has_transition_system(std::string id) const;

};


}
}