(** Copyright (c) 2016-present, Facebook, Inc.

    This source code is licensed under the MIT license found in the
    LICENSE file in the root directory of this source tree. *)

open Core
open OUnit2

open Ast
open Expression
open Statement

open Test


let test_empty_stub _ =
  assert_true (Module.create ~qualifier:[] ~stub:true ~statements:[] |> Module.empty_stub);
  assert_false (Module.create ~qualifier:[] ~stub:false ~statements:[] |> Module.empty_stub);
  assert_false (Module.create ~qualifier:[] ~stub:true ~statements:[+Pass] |> Module.empty_stub)


let test_aliased_export _ =
  let assert_aliased_exports ?(qualifier = []) source aliased_exports =
    let module_definition =
      let { Source.statements; _ } = parse source in
      Module.create ~qualifier ~stub:false ~statements
    in
    let assert_aliased_export (source, expected_target) =
      let actual_target =
        Access.create source
        |> Module.aliased_export module_definition
        |> (fun value -> Option.value_exn value)
        |> Access.show
      in
      assert_equal
        ~printer:Fn.id
        expected_target
        actual_target
    in
    List.iter ~f:assert_aliased_export aliased_exports
  in

  assert_aliased_exports
    {|
      from other.module import Class
      from different.module import function
      import blah
      import standard_library_module as module
    |}
    [
      "Class", "other.module.Class";
      "function", "different.module.function";
      "blah", "blah";
      "module", "standard_library_module";
    ];

  assert_aliased_exports
    "from some.module import aliased as alias"
    ["alias", "some.module.aliased"];

  assert_aliased_exports
    "from some.module import one, two"
    [
      "one", "some.module.one";
      "two", "some.module.two";
    ];

  assert_aliased_exports
    "from some.module import *"
    ["*", "some.module"];

  assert_aliased_exports
    ~qualifier:(Access.create "some.module")
    "from . import path as other"
    ["other", "some.module.path"];

  assert_aliased_exports
    ~qualifier:(Access.create "some.module")
    "from some.module.derp import path as other"
    ["other", "some.module.derp.path"];

  assert_aliased_exports
    ~qualifier:(Access.create "some.module")
    "from some.module.other import other as other"
    ["other", "other.other"];


  assert_aliased_exports
    "from builtins import path as other"
    ["other", "path"];

  assert_aliased_exports
    {|
      from other import thing
      from other import thing
    |}
    ["thing", "other.thing"]


let test_wildcard_exports _ =
  let module_from_source ~source ~qualifier =
    let { Source.statements; _ } = parse source in
    Module.create ~qualifier ~stub:false ~statements
  in
  let assert_wildcard_exports ?(qualifier = []) source expected =
    assert_equal
      ~printer:(fun expression_list ->
          List.map ~f:(Expression.Access.show) expression_list
          |> String.concat ~sep:", ")
      (List.map ~f:(Expression.Access.create) expected)
      (module_from_source ~source ~qualifier |> Module.wildcard_exports)
  in
  let assert_in_wildcard_exports ?(qualifier = []) source access expected_bool =
    if expected_bool then
      assert_true
        (Module.in_wildcard_exports
           (module_from_source ~source ~qualifier)
           (Expression.Access.create access))
    else
      assert_false
        (Module.in_wildcard_exports
           (module_from_source ~source ~qualifier)
           (Expression.Access.create access))
  in
  assert_wildcard_exports
    {|
      from other.module import Class
      from different.module import function
      import blah
      import standard_library_module as module
      def foo(): pass
      variable = 1
      class Bar: pass
    |}
    ["Class"; "function"; "blah"; "module"; "foo"; "variable"; "Bar"];

  assert_wildcard_exports
    {|
      from other.module import Class
      from different.module import function
      import blah
      import standard_library_module as module
      def foo(): pass
      variable = 1
      class Bar: pass
      __all__ = ["only_export"]
    |}
    ["only_export"];

  assert_wildcard_exports
    {|
      def foo(): ...
      variable = ...
      class Bar: ...
    |}
    ["foo"; "variable"; "Bar"];

  assert_wildcard_exports
    {|
      import standard_library_module as _module
      def _foo(): pass
      _variable = 1
      class _Bar: pass
    |}
    [];

  assert_wildcard_exports
    ~qualifier:(Access.create "_underscore")
    {|
      def foo(): ...
      variable = ...
      class Bar: ...
    |}
    ["foo"; "variable"; "Bar"];

  assert_wildcard_exports
    ~qualifier:(Access.create "qualified")
    {|
      def qualified.foo(): ...
      qualified.variable = ...
      class qualified.Bar: ...
    |}
    ["foo"; "variable"; "Bar"];

  assert_in_wildcard_exports
    {|
      def foo(): ...
      variable = ...
      class Bar: ...
    |}
    "foo"
    true


let () =
  "module">:::[
    "empty_stub">::test_empty_stub;
    "aliased_export">::test_aliased_export;
    "wildcard_exports">::test_wildcard_exports;
  ]
  |> run_test_tt_main
