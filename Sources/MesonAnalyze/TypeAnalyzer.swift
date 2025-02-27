import Foundation
import IOUtils
import Logging
import MesonAST
import Timing

public final class TypeAnalyzer: ExtendedCodeVisitor {
  static let LOG = Logger(label: "MesonAnalyze::TypeAnalyzer")
  static let ITERATION_DICT_VAR_COUNT = 2
  static let GET_SET_VARIABLE_ARG_COUNT_MAX = 2
  var scope: Scope
  var t: TypeNamespace
  var tree: MesonTree
  var metadata: MesonMetadata
  let typeanalyzersState: TypeAnalyzersState = TypeAnalyzersState()
  let options: [MesonOption]
  var stack: [[String: [Type]]] = []
  var overriddenVariables: [[String: [Type]]] = []
  var ignoreUnknownIdentifer: [String] = []
  var depth: UInt = 0
  var variablesNeedingUse: [[IdExpression]] = []
  var subprojectState: SubprojectState?
  var visitedFiles: [String] = []
  var foundVariables: [[String]] = []
  var subproject: Subproject?
  var version: Version?
  var analysisOptions: AnalysisOptions

  let pureFunctions: Set<String> = [
    "disabler", "environment", "files", "generator", "get_variable", "import",
    "include_directories", "is_disabler", "is_variable", "join_paths", "structured_sources",
  ]
  // Missing: Compiler functions and the ones from the modules
  let pureMethods: Set<String> = [
    "build_machine.cpu", "build_machine.cpu_family", "build_machine.endian", "build_machine.system",
    "meson.backend", "meson.build_options", "meson.build_root", "meson.can_run_host_binaries",
    "meson.current_build_dir", "meson.current_source_dir", "meson.get_cross_property",
    "meson.get_external_property", "meson.global_build_root", "meson.global_source_root",
    "meson.has_exe_wrapper", "meson.has_external_property", "meson.is_cross_build",
    "meson.is_subproject", "meson.is_unity", "meson.project_build_root", "meson.project_license",
    "meson.project_license_files", "meson.project_name", "meson.project_source_root",
    "meson.project_version", "meson.source_root", "meson.version", "both_libs.get_shared_lib",
    "both_libs.get_static_lib", "build_tgt.extract_all_objects", "build_tgt.extract_objects",
    "build_tgt.found", "build_tgt.full_path", "build_tgt.full_path", "build_tgt.name",
    "build_tgt.path", "build_tgt.private_dir_include", "cfg_data.get", "cfg_data.get_unquoted",
    "cfg_data.has", "cfg_data.keys", "custom_idx.full_path", "custom_tgt.full_path",
    "custom_tgt.to_list", "dep.as_link_whole", "dep.as_system", "dep.found",
    "dep.get_configtool_variable", "dep.get_pkgconfig_variable", "dep.get_variable",
    "dep.include_type", "dep.name", "dep.partial_dependency", "dep.type_name", "dep.version",
    "disabler.found", "external_program.found", "external_program.full_path",
    "external_program.path", "external_program.version", "feature.allowed", "feature.auto",
    "feature.disabled", "feature.enabled", "module.found", "runresult.compiled",
    "runresult.returncode", "runresult.stderr", "runresult.stdout", "subproject.found",
    "subproject.get_variable", "str.contains", "str.endswith", "str.format", "str.join",
    "str.replace", "str.split", "str.startswith", "str.strip", "str.substring", "str.to_lower",
    "str.to_upper", "str.underscorify", "str.version_compare", "bool.to_int", "bool.to_string",
    "dict.get", "dict.has_key", "dict.keys", "int.even", "int.is_odd", "int.to_string",
    "list.contains", "list.get", "list.length",
  ]

  let compilerIds: Set<String> = [
    "arm", "armclang", "ccomp", "ccrx", "clang", "clang-cl", "dmd", "emscripten", "flang", "g95",
    "gcc", "intel", "intel-cl", "icc", "intel-llvm", "intel-llvm-cl", "lcc", "llvm", "mono", "msvc",
    "nagfor", "nvidia_hpc", "open64", "pathscale", "pgi", "rustc", "sun", "c2000", "ti", "valac",
    "xc16", "cython", "nasm", "yasm", "ml", "armasm", "mwasmarm", "mwasmeppc",
  ]

  let argumentSyntaxes: Set<String> = ["gcc", "msvc", "gnu", ""]

  let linkerIds: Set<String> = [
    "ld.bfd", "ld.gold", "ld.lld", "ld.mold", "ld.solaris", "ld.wasm", "ld64", "ld64.lld", "link",
    "lld-link", "xilink", "optlink", "rlink", "xc16-ar", "ar2000", "ti-ar", "armlink", "pgi",
    "nvlink", "ccomp", "mwldarm", "mwldeppc",
  ]

  let cpuFamilies: Set<String> = [
    "aarch64", "alpha", "arc", "arm", "avr", "c2000", "csky", "dspic", "e2k", "ft32", "ia64",
    "loongarch64", "m68k", "microblaze", "mips", "mips32", "mips64", "msp430", "parisc", "pic24",
    "ppc", "ppc64", "riscv32", "riscv64", "rl78", "rx", "s390", "s390x", "sh4", "sparc", "sparc64",
    "wasm32", "wasm64", "x86", "x86_64",
  ]

  let osNames: Set<String> = [
    "android", "cygwin", "darwin", "dragonfly", "emscripten", "freebsd", "gnu", "haiku", "linux",
    "netbsd", "openbsd", "windows", "sunos",
  ]

  public init(
    parent: Scope,
    tree: MesonTree,
    options: [MesonOption],
    subprojectState: SubprojectState? = nil,
    subproject: Subproject? = nil,
    analysisOptions: AnalysisOptions
  ) {
    self.scope = parent
    self.tree = tree
    self.t = tree.ns
    self.options = options
    self.metadata = MesonMetadata()
    self.subprojectState = subprojectState
    self.subproject = subproject
    self.analysisOptions = analysisOptions
  }

  public func visitSubdirCall(node: SubdirCall) {
    node.visitChildren(visitor: self)
    self.metadata.registerSubdirCall(call: node)
    let newPath =
      Path(node.file.file).absolute().parent().description + Path.separator + node.subdirname
      + "\(Path.separator)meson.build"
    let subtree = self.tree.findSubdirTree(file: newPath)
    if let st = subtree {
      let tmptree = self.tree
      self.tree = st
      self.scope = Scope(parent: self.scope)
      st.ast?.setParents()
      st.ast?.parent = node
      st.ast?.visit(visitor: self)
      self.tree = tmptree
      node.append(st.ast)
    } else {
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(
          sev: .error,
          node: node,
          message: "Unable to find subdir \(node.subdirname)"
        )
      )
      Self.LOG.warning("Not found: \(node.subdirname)")
    }
  }

  public func visitMultiSubdirCall(node: MultiSubdirCall) {
    node.visitChildren(visitor: self)
    let base = Path(node.file.file).absolute().parent().description
    for subdirname in node.subdirnames {
      if subdirname.isEmpty { continue }
      let newPath = base + Path.separator + subdirname + "\(Path.separator)meson.build"
      let subtree = self.tree.findSubdirTree(file: newPath)
      if let st = subtree {
        let tmptree = self.tree
        self.tree = st
        self.scope = Scope(parent: self.scope)
        st.ast?.setParents()
        st.ast?.parent = node
        st.ast?.visit(visitor: self)
        self.tree = tmptree
        node.append(st.ast)
      } else {
        Self.LOG.warning("Not found (Multisubdir): \(subdirname)")
      }
    }
  }

  public func applyToStack(_ name: String, _ types: [Type]) {
    if self.stack.isEmpty { return }
    if self.scope.variables[name] != nil {
      let orVCount = self.overriddenVariables.count - 1
      if self.overriddenVariables[orVCount][name] == nil {
        self.overriddenVariables[orVCount][name] = self.scope.variables[name]!
      } else {
        self.overriddenVariables[orVCount][name]! += self.scope.variables[name]!
      }
    }
    let ssC = self.stack.count - 1
    if self.stack[ssC][name] == nil {
      self.stack[ssC][name] = types
    } else {
      self.stack[ssC][name]! += types
    }
  }

  public func visitSourceFile(file: SourceFile) {
    self.depth += 1
    self.variablesNeedingUse.append([])
    self.visitedFiles.append(file.file.file)
    file.visitChildren(visitor: self)
    foundVariables.append(Array(self.scope.variables.keys))
    self.depth -= 1
    let needingUse = self.variablesNeedingUse.removeLast()
    if self.depth == 0 {
      var exportedVars: [String] = []
      if let s = self.subproject as? WrapBasedSubproject {
        exportedVars = Array(s.wrap.provides.dependencyNames.values)
      }
      for n in needingUse {
        if exportedVars.contains(n.id) { continue }
        if let ass = n.parent as? AssignmentStatement, let rhs = ass.rhs as? FunctionExpression,
          let fnid = rhs.id as? IdExpression, fnid.id == "declare_dependency"
        {
          continue
        }
        self.metadata.registerDiagnostic(
          node: n,
          diag: MesonDiagnostic(sev: .warning, node: n, message: "Unused assignment")
        )
      }
    } else {
      self.variablesNeedingUse[self.variablesNeedingUse.count - 1] += needingUse
    }
  }

  public func visitBuildDefinition(node: BuildDefinition) {
    var lastAlive: Node?
    var firstDead: Node?
    var lastDead: Node?
    if self.depth == 1 {
      if node.stmts.isEmpty {
        self.metadata.registerDiagnostic(
          node: node,
          diag: MesonDiagnostic(
            sev: .error,
            node: node,
            message: "Missing project() call at top of file"
          )
        )
      } else {
        if let fne = node.stmts[0] as? FunctionExpression, let id = fne.id as? IdExpression,
          id.id == "project"
        {
          // Found our project call
          if let al = fne.argumentList as? ArgumentList {
            for a in al.args
            where (a is KeywordItem) && ((a as! KeywordItem).key is IdExpression)
              && ((a as! KeywordItem).key as! IdExpression).id == "meson_version"
            {
              let value = (a as! KeywordItem).value
              guard let sl = value as? StringLiteral else { continue }
              self.version = Version.parseVersion(s: sl.contents())
              Self.LOG.info("Version = \(sl.contents())")
              break
            }
          }
        } else {
          self.metadata.registerDiagnostic(
            node: node.stmts[0],
            diag: MesonDiagnostic(
              sev: .error,
              node: node.stmts[0],
              message: "First statement is not a project() call"
            )
          )
        }
      }
    }
    node.visitChildren(visitor: self)
    for b in node.stmts {
      self.checkNoEffect(b)
      if lastAlive == nil {
        if self.isDead(b) { lastAlive = b }
      } else {
        if firstDead == nil {
          firstDead = b
          lastDead = b
        } else {
          lastDead = b
        }
      }
    }
    self.applyDead(lastAlive, firstDead, lastDead)
  }

  public func visitErrorNode(node: ErrorNode) {
    node.visitChildren(visitor: self)
    self.metadata.registerDiagnostic(
      node: node,
      diag: MesonDiagnostic(sev: .error, node: node, message: node.message)
    )
  }

  private func checkCondition(_ c: Node) -> Bool {
    var appended = false
    if let fn = c as? FunctionExpression, let fnid = fn.id as? IdExpression,
      fnid.id == "is_variable", let al = fn.argumentList as? ArgumentList, !al.args.isEmpty,
      let sl = al.args[0] as? StringLiteral
    {
      self.ignoreUnknownIdentifer.append(sl.contents())
      appended = true
    }
    var foundBoolOrAny = false
    for t in c.types where t is `Any` || t is BoolType || t is Disabler {
      foundBoolOrAny = true
      break
    }
    if !foundBoolOrAny && !c.types.isEmpty {
      let t = c.types.map { $0.toString() }.joined(separator: "|")
      self.metadata.registerDiagnostic(
        node: c,
        diag: MesonDiagnostic(sev: .error, node: c, message: "Condition is not bool: \(t)")
      )
    }
    return appended
  }

  public func visitSelectionStatement(node: SelectionStatement) {
    self.stack.append([:])
    self.overriddenVariables.append([:])
    var oldVars: [String: [Type]] = [:]
    self.scope.variables.forEach { oldVars[$0.key] = Array($0.value) }
    var idx = 0
    var allLeft: [IdExpression] = []
    for b in node.blocks {
      var appended = false
      if idx < node.conditions.count {
        let c = node.conditions[idx]
        c.visit(visitor: self)
        appended = self.checkCondition(c)
      }
      var lastAlive: Node?
      var firstDead: Node?
      var lastDead: Node?
      self.variablesNeedingUse.append([])
      for b1 in b {
        b1.visit(visitor: self)
        self.checkNoEffect(b1)
        if lastAlive == nil {
          if self.isDead(b1) { lastAlive = b1 }
        } else {
          if firstDead == nil {
            firstDead = b1
            lastDead = b1
          } else {
            lastDead = b1
          }
        }
      }
      self.applyDead(lastAlive, firstDead, lastDead)
      if appended { self.ignoreUnknownIdentifer.removeLast() }
      let needingUse = self.variablesNeedingUse.removeLast()
      allLeft += needingUse
      idx += 1
    }
    var dedupedUnusedAssignments: Set<String> = []
    var toInsert = self.variablesNeedingUse[self.variablesNeedingUse.count - 1]
    for n in allLeft where !dedupedUnusedAssignments.contains(n.id) {
      dedupedUnusedAssignments.insert(n.id)
      toInsert.append(n)
    }
    let types = self.stack.removeLast()
    // If: 1 c, 1 b
    // If,else if: 2c, 2b
    // if, else if, else, 2c, 3b
    for k in types.keys {
      // This leaks some overwritten types. This can't be solved
      // without costly static analysis
      // x = 'Foo'
      // if bar
      //   x = 2
      // else
      //   x = true
      // endif
      // x is now str|int|bool instead of int|bool
      var arr = (self.scope.variables[k] ?? []) + types[k]!
      if node.conditions.count == node.blocks.count { arr += (oldVars[k] ?? []) }
      self.scope.variables[k] = dedup(types: arr)
    }
    self.overriddenVariables.removeLast()
  }

  public func visitBreakStatement(node: BreakNode) { self.checkIfInLoop(node, "break") }

  public func visitContinueStatement(node: ContinueNode) { self.checkIfInLoop(node, "continue") }

  func checkIfInLoop(_ node: Node, _ str: String) {
    var parent = node.parent
    while parent != nil {
      if parent is IterationStatement { return }
      if parent is BuildDefinition { break }
      parent = parent!.parent
    }
    self.metadata.registerDiagnostic(
      node: node,
      diag: MesonDiagnostic(
        sev: .error,
        node: node,
        message: "\(str) statements are only allowed inside loops"
      )
    )
  }

  private func analyseIterationStatementTwoIdentifiers(_ node: IterationStatement) {
    let iterTypes = node.expression.types
    node.ids[0].types = [self.t.strType]
    let first = iterTypes.first { $0 is Dict }
    if let dd = first, let ddd = dd as? Dict {
      node.ids[1].types = ddd.types
    } else {
      node.ids[1].types = []
      self.metadata.registerDiagnostic(
        node: node.expression,
        diag: MesonDiagnostic(
          sev: .error,
          node: node.expression,
          message: iterTypes.first { $0 is ListType || $0 is RangeType } != nil
            ? "Iterating over a list/range requires one identifier"
            : "Expression yields no iterable result"
        )
      )
    }
    if let id0Expr = (node.ids[0] as? IdExpression), let id1Expr = (node.ids[1] as? IdExpression) {
      self.applyToStack(id1Expr.id, node.ids[1].types)
      self.scope.variables[id1Expr.id] = node.ids[1].types
      self.checkIdentifier(id1Expr)
      self.applyToStack(id0Expr.id, node.ids[0].types)
      self.scope.variables[id0Expr.id] = node.ids[0].types
      self.checkIdentifier(id0Expr)
    }
  }

  private func analyseIterationStatementSingleIdentifier(_ node: IterationStatement) {
    let iterTypes = node.expression.types
    var res: [Type] = []
    var errs = 0
    var foundDict = false
    for l in iterTypes {
      if l is RangeType {
        res.append(self.t.intType)
      } else if let lt = l as? ListType {
        res += lt.types
      } else {
        if l is Dict { foundDict = true }
        errs += 1
      }
    }
    if errs != iterTypes.count {
      node.ids[0].types = res
    } else {
      node.ids[0].types = []
      self.metadata.registerDiagnostic(
        node: node.expression,
        diag: MesonDiagnostic(
          sev: .error,
          node: node.expression,
          message: foundDict
            ? "Iterating over a dict requires two identifiers"
            : "Expression yields no iterable result"
        )
      )
    }
    if let id0Expr = (node.ids[0] as? IdExpression) {
      self.applyToStack(id0Expr.id, node.ids[0].types)
      self.scope.variables[id0Expr.id] = node.ids[0].types
      self.checkIdentifier(id0Expr)
    }
  }

  public func visitIterationStatement(node: IterationStatement) {
    node.expression.visit(visitor: self)
    for id in node.ids { id.visit(visitor: self) }
    if node.ids.count == 1 {
      analyseIterationStatementSingleIdentifier(node)
    } else if node.ids.count == Self.ITERATION_DICT_VAR_COUNT {
      analyseIterationStatementTwoIdentifiers(node)
    } else {
      self.metadata.registerDiagnostic(
        begin: node.ids[0],
        end: node.ids[node.ids.count - 1],
        diag: MesonDiagnostic(
          sev: .error,
          begin: node.ids[0],
          end: node.ids[node.ids.count - 1],
          message: "Iteration statement expects only one or two identifiers"
        )
      )
    }
    var lastAlive: Node?
    var firstDead: Node?
    var lastDead: Node?
    for b in node.block {
      b.visit(visitor: self)
      self.checkNoEffect(b)
      if lastAlive == nil {
        if self.isDead(b) { lastAlive = b }
      } else {
        if firstDead == nil {
          firstDead = b
          lastDead = b
        } else {
          lastDead = b
        }
      }
    }
    self.applyDead(lastAlive, firstDead, lastDead)
  }

  private func checkIdentifier(_ node: IdExpression) {
    if self.analysisOptions.disableNameLinting { return }
    if !isSnakeCase(str: node.id) && !isShoutingSnakeCase(str: node.id) {
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(sev: .warning, node: node, message: "Expected snake case")
      )
    }
  }

  private func evalPlusEquals(_ l: Type, _ r: Type) -> Type? {
    if l is `IntType` && r is `IntType` {
      return self.t.intType
    } else if l is Str && r is Str {
      return self.t.strType
    } else if let ll = l as? ListType, let lr = r as? ListType {
      return ListType(types: dedup(types: ll.types + lr.types))
    } else if let ll = l as? ListType {
      return ListType(types: dedup(types: ll.types + CollectionOfOne(r)))
    } else if let dl = l as? Dict, let dr = r as? Dict {
      return Dict(types: dedup(types: dl.types + dr.types))
    } else if let dl = l as? Dict {
      return Dict(types: dedup(types: dl.types + CollectionOfOne(r)))
    }
    return nil
  }

  private func evalAssignmentTypes(
    _ l: Type,
    _ r: Type,
    _ op: AssignmentOperator,
    _ newTypes: inout [Type]
  ) {
    switch op {
    case .divequals:
      if l is `IntType` && r is `IntType` {
        newTypes.append(self.t.intType)
      } else if l is Str && r is Str {
        newTypes.append(self.t.strType)
      }
    case .minusequals, .modequals, .mulequals:
      if l is `IntType` && r is `IntType` { newTypes.append(self.t.intType) }
    case .plusequals: if let t = evalPlusEquals(l, r) { newTypes.append(t) }
    default: _ = 1
    }
  }

  private func evalAssignment(_ op: AssignmentOperator, _ lhs: [Type], _ rhs: [Type]) -> [Type]? {
    var newTypes: [Type] = []
    for l in lhs { for r in rhs { evalAssignmentTypes(l, r, op, &newTypes) } }
    return newTypes.isEmpty ? nil : newTypes
  }

  private func registerNeedForUse(_ node: IdExpression) {
    self.variablesNeedingUse[self.variablesNeedingUse.count - 1].append(node)
  }

  private func extractVoidAssignment(_ node: AssignmentStatement) {
    var name = ""
    if let fe = node.rhs as? FunctionExpression, let f = fe.function {
      name = f.id()
    } else if let me = node.rhs as? MethodExpression, let m = me.method {
      name = m.id()
    }
    if !name.hasPrefix("install_") {
      self.metadata.registerDiagnostic(
        node: node.lhs,
        diag: MesonDiagnostic(sev: .error, node: node.lhs, message: "Can't assign from void")
      )
    }
  }

  public func visitAssignmentStatement(node: AssignmentStatement) {
    node.visitChildren(visitor: self)
    if !(node.lhs is IdExpression) {
      self.metadata.registerDiagnostic(
        node: node.lhs,
        diag: MesonDiagnostic(sev: .error, node: node.lhs, message: "Can only assign to variables")
      )
      return
    }
    guard node.op != nil else { return }
    guard let lhsIdExpr = node.lhs as? IdExpression else { return }
    if node.rhs.types.isEmpty && (node.rhs is FunctionExpression || node.lhs is MethodExpression) {
      self.extractVoidAssignment(node)
      return
    }
    if node.op == .equals {
      var arr = node.rhs.types
      if arr.isEmpty, let arrLit = node.rhs as? ArrayLiteral, arrLit.args.isEmpty {
        arr = [ListType(types: [])]
      }
      if arr.isEmpty, let dictLit = node.rhs as? DictionaryLiteral, dictLit.values.isEmpty {
        arr = [Dict(types: [])]
      }
      if lhsIdExpr.id == "meson" || lhsIdExpr.id == "build_machine"
        || lhsIdExpr.id == "target_machine" || lhsIdExpr.id == "host_machine"
      {
        self.metadata.registerDiagnostic(
          node: node,
          diag: MesonDiagnostic(
            sev: .error,
            node: node,
            message: "Attempted to re-assign to existing, read-only variable"
          )
        )
        self.metadata.registerIdentifier(id: lhsIdExpr)
        return
      }
      lhsIdExpr.types = arr
      self.checkIdentifier(lhsIdExpr)
      self.applyToStack(lhsIdExpr.id, arr)
      self.scope.variables[lhsIdExpr.id] = arr
      self.registerNeedForUse(lhsIdExpr)
    } else {
      let newTypes = evalAssignment(node.op!, node.lhs.types, node.rhs.types)
      var deduped = dedup(types: newTypes == nil ? node.lhs.types : newTypes!)
      if deduped.isEmpty && node.rhs.types.isEmpty && self.scope.variables[lhsIdExpr.id] != nil
        && !self.scope.variables[lhsIdExpr.id]!.isEmpty
      {
        deduped = dedup(types: self.scope.variables[lhsIdExpr.id]!)
      }
      if newTypes == nil && !node.rhs.types.isEmpty && !node.lhs.types.isEmpty {
        self.metadata.registerDiagnostic(
          node: node,
          diag: MesonDiagnostic(
            sev: .error,
            node: node,
            message:
              "Unable to apply operator `\(node.op!)` to types \(self.joinTypes(types: node.lhs.types)) and \(self.joinTypes(types: node.rhs.types))"
          )
        )
      }
      lhsIdExpr.types = deduped
      self.applyToStack(lhsIdExpr.id, deduped)
      self.scope.variables[lhsIdExpr.id] = deduped
    }
    self.metadata.registerIdentifier(id: lhsIdExpr)
  }

  private func specialFunctionCallHandling(_ node: FunctionExpression, _ fn: Function) {
    guard let al = node.argumentList as? ArgumentList else { return }
    if fn.name == "get_variable" {
      let args = al.args
      if !args.isEmpty, let sl = args[0] as? StringLiteral {
        let varname = sl.contents()
        var types: [Type] = []
        if let sv = self.scope.variables[varname] { types += sv } else { types += fn.returnTypes }
        if args.count >= Self.GET_SET_VARIABLE_ARG_COUNT_MAX { types += args[1].types }
        node.types = types
        Self.LOG.info("get_variable: \(varname) = \(self.joinTypes(types: types))")
      } else if !args.isEmpty {
        var types: [Type] = fn.returnTypes
        if args.count >= Self.GET_SET_VARIABLE_ARG_COUNT_MAX { types += args[1].types }
        let guessedNames = Set(MesonAnalyze.guessSetVariable(fe: node))
        types += guessedNames.map({ self.scope.variables[$0] ?? [] }).flatMap({ $0 })
        node.types = self.dedup(types: types)
        Self.LOG.info(
          "get_variable (Imprecise): ??? = \(self.joinTypes(types: node.types)): Guessed variable names: \(guessedNames)"
        )
      }
    } else if fn.name == "subdir" {
      if let sl = al.args[0] as? StringLiteral {
        let s = sl.contents()
        self.metadata.registerDiagnostic(
          node: node,
          diag: MesonDiagnostic(sev: .error, node: node, message: s + "/meson.build not found")
        )
      }
    } else if fn.name == "get_option", !al.args.isEmpty, let sl = al.args[0] as? StringLiteral,
      let opts = self.tree.options
    {
      self.analyzeOptsCalls(node, sl, opts)
    }
  }

  private func analyzeOptsCalls(_ node: Node, _ sl: StringLiteral, _ opts: OptionState) {
    let optname = sl.contents()
    if let opt = opts.opts[optname] {
      if opt.deprecated {
        self.metadata.registerDiagnostic(
          node: node,
          diag: MesonDiagnostic(
            sev: .warning,
            node: node,
            message: "Option `\(optname)` is deprecated"
          )
        )
      }
    } else {
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(sev: .error, node: node, message: "Unknown option `\(optname)`")
      )
    }
  }

  private func setFunctionCallTypes(node: FunctionExpression, fn: Function) {
    if fn.name != "subproject" {
      node.types = self.typeanalyzersState.apply(
        node: node,
        options: self.options,
        f: fn,
        ns: self.t
      )
    } else {
      let names = Set(MesonAnalyze.guessSetVariable(fe: node))
      Self.LOG.info("Guessed args to `subproject` as \(names)")
      node.types = [MesonAST.Subproject(names: Array(names))]
      if let ssT = self.subprojectState {
        var n = names
        for s in ssT.subprojects where n.contains(s.name) { n.remove(s.name) }
        if !n.isEmpty {
          self.metadata.registerDiagnostic(
            node: node,
            diag: MesonDiagnostic(
              sev: .error,
              node: node,
              message: "Unable to find subprojects \(n)"
            )
          )
        }
      }
    }
  }

  // swiftlint:disable cyclomatic_complexity
  public func visitFunctionExpression(node: FunctionExpression) {
    node.visitChildren(visitor: self)
    guard let funcNameId = node.id as? IdExpression else { return }
    let funcName = funcNameId.id
    if let fn = self.t.lookupFunction(name: funcName) {
      self.setFunctionCallTypes(node: node, fn: fn)
      self.specialFunctionCallHandling(node, fn)
      node.function = fn
      self.metadata.registerFunctionCall(call: node)
      if let args = node.argumentList, args is ArgumentList {
        self.checkCall(node: node)
      } else if node.argumentList == nil {
        if node.function!.minPosArgs() != 0 {
          self.metadata.registerDiagnostic(
            node: node,
            diag: MesonDiagnostic(
              sev: .error,
              node: node,
              message: "Expected " + String(node.function!.minPosArgs())
                + " positional arguments, but got none!"
            )
          )
        }
      }
      if let al = node.argumentList as? ArgumentList {
        for a in al.args where a is KeywordItem {
          self.metadata.registerKwarg(item: a as! KeywordItem, f: fn)
        }
        if node.function!.name == "set_variable" {
          let args = al.args
          if !args.isEmpty {
            if let sl = args[0] as? StringLiteral {
              let varname = sl.contents()
              let types = args[1].types
              self.scope.variables[varname] = types
              self.applyToStack(varname, types)
              Self.LOG.info("set_variable: \(varname) = \(self.joinTypes(types: types))")
            } else {
              guessSetVariable(args: args, node: node)
            }
          }
        }
      }
      if self.version != nil,
        let alts = DeprecationState.check(name: fn.id(), version: self.version!)
      {
        self.registerDeprecated(fn.id(), node.id, alts)
      }
    } else {
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(sev: .error, node: node, message: "Unknown function `\(funcName)`")
      )
    }
  }
  // swiftlint:enable cyclomatic_complexity

  private func guessSetVariable(args: [Node], node: FunctionExpression) {
    let vars = Set(MesonAnalyze.guessSetVariable(fe: node))
    Self.LOG.info(
      "Guessed values to set_variable: \(vars) at \(node.file.file):\(node.location.format())"
    )
    for v in vars {
      let types = args[1].types
      self.scope.variables[v] = types
      self.applyToStack(v, types)
    }
  }

  public func visitArgumentList(node: ArgumentList) { node.visitChildren(visitor: self) }

  public func visitKeywordItem(node: KeywordItem) {
    node.visitChildren(visitor: self)
    if let id = node.key as? IdExpression, self.version != nil {
      if let alts = DeprecationState.check(name: "<\(id.id)>", version: self.version!) {
        self.registerDeprecated("Keyword \(id.id)", node.key, alts)
      }
    }
  }

  private func registerDeprecated(_ s: String, _ n: Node, _ alternatives: [String]) {
    self.metadata.registerDiagnostic(
      node: n,
      diag: MesonDiagnostic(
        sev: .warning,
        node: n,
        message: "\(s) is deprecated. Use one of these: \(alternatives.joined(separator: ", "))"
      )
    )
  }

  public func visitConditionalExpression(node: ConditionalExpression) {
    node.visitChildren(visitor: self)
    node.types = dedup(types: node.ifFalse.types + node.ifTrue.types)
    for t in node.condition.types where t is `Any` || t is BoolType || t is Disabler { return }
    if !node.condition.types.isEmpty {
      let t = node.condition.types.map { $0.toString() }.joined(separator: "|")
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(sev: .error, node: node, message: "Condition is not bool: \(t)")
      )
    }
  }

  public func visitUnaryExpression(node: UnaryExpression) {
    node.visitChildren(visitor: self)
    switch node.op! {
    case .minus: node.types = [self.t.intType]
    case .not, .exclamationMark: node.types = [self.t.boolType]
    }
  }

  public func visitSubscriptExpression(node: SubscriptExpression) {
    node.visitChildren(visitor: self)
    var newTypes: [Type] = []
    for t in node.outer.types {
      if let d = t as? Dict {
        newTypes += d.types
      } else if let lt = t as? ListType {
        newTypes += lt.types
      } else if t is Str {
        newTypes += [self.t.strType]
      } else if t is CustomTgt {
        newTypes += [self.t.types["custom_idx"]!]
      }
    }
    node.types = dedup(types: newTypes)
    self.metadata.registerArrayAccess(node: node)
  }

  private func guessMethod(node: MethodExpression, methodName: String, ownResultTypes: inout [Type])
    -> Bool
  {
    let guessedMethod = self.t.lookupMethod(name: methodName)
    if let guessedM = guessedMethod {
      Self.LOG.info("Guessed method \(guessedM.id()) at \(node.file.file)\(node.location.format())")
      ownResultTypes += self.typeanalyzersState.apply(
        node: node,
        options: self.options,
        f: guessedM,
        ns: self.t
      )
      node.method = guessedM
      self.metadata.registerMethodCall(call: node)
      node.types = dedup(types: ownResultTypes)
      return true
    }
    return false
  }

  // swiftlint:disable cyclomatic_complexity
  private func findMethod(
    node: MethodExpression,
    methodName: String,
    nAny: inout Int,
    bits: inout Int,
    ownResultTypes: inout [Type]
  ) -> Bool {
    var found = false
    let types = node.obj.types
    for t in types {
      if t is `Any` {
        nAny += 1
        bits |= (1 << 0)
        continue
      } else if let l = t as? ListType, l.types.count == 1 && l.types[0] is `Any` {
        nAny += 1
        bits |= (1 << 1)
        continue
      } else if let d = t as? Dict, d.types.count == 1 && d.types[0] is `Any` {
        nAny += 1
        bits |= (1 << 2)
        continue
      }
      if methodName == "get" { continue }
      if let m = t.getMethod(name: methodName, ns: self.t) {
        ownResultTypes += self.typeanalyzersState.apply(
          node: node,
          options: self.options,
          f: m,
          ns: self.t
        )
        node.method = m
        self.metadata.registerMethodCall(call: node)
        found = true
        if let al = node.argumentList as? ArgumentList, !al.args.isEmpty,
          m.id() == "subproject.get_variable", let stO = t as? MesonAST.Subproject,
          let s = self.subprojectState
        {
          let calculatedNames = Set(guessGetVariableMethod(me: node))
          var foundVariables = false
          for subproject in s.subprojects where stO.names.contains(subproject.name) {
            if let ast = subproject.tree, let sscope = ast.scope {
              for name in calculatedNames where sscope.variables.keys.contains(name) {
                ownResultTypes += sscope.variables[name]!
                foundVariables = true
              }
            }
          }
          if !calculatedNames.isEmpty && !foundVariables {
            self.metadata.registerDiagnostic(
              node: node,
              diag: MesonDiagnostic(
                sev: .error,
                node: node,
                message: "Unable to find variables called \(calculatedNames) in subprojects"
              )
            )
          }
        }
      }
    }
    if methodName == "get" && node.obj.types.first(where: { $0 is ListType }) != nil,
      let al = node.argumentList as? ArgumentList, let il = al.args.first,
      il.types.first(where: { $0 is `IntType` }) != nil
    {
      let m = self.t.vtables["list"]![1]
      ownResultTypes = self.typeanalyzersState.apply(
        node: node,
        options: self.options,
        f: m,
        ns: self.t
      )
      node.method = m
      self.metadata.registerMethodCall(call: node)
      return true
    }
    if methodName == "get" && node.obj.types.first(where: { $0 is Dict }) != nil,
      let al = node.argumentList as? ArgumentList, let sl = al.args.first,
      sl.types.first(where: { $0 is Str }) != nil
    {
      let m = self.t.vtables["dict"]![0]
      ownResultTypes = self.typeanalyzersState.apply(
        node: node,
        options: self.options,
        f: m,
        ns: self.t
      )
      node.method = m
      self.metadata.registerMethodCall(call: node)
      return true
    }
    if methodName == "get" && node.obj.types.first(where: { $0 is CfgData }) != nil {
      let m = self.t.vtables["cfg_data"]![0]
      ownResultTypes = self.typeanalyzersState.apply(
        node: node,
        options: self.options,
        f: m,
        ns: self.t
      )
      node.method = m
      self.metadata.registerMethodCall(call: node)
      return true
    }
    return found
  }

  public func visitMethodExpression(node: MethodExpression) {
    node.visitChildren(visitor: self)
    let types = node.obj.types
    var ownResultTypes: [Type] = []
    var found = false
    guard let methodNameId = node.id as? IdExpression else { return }
    let methodName = methodNameId.id
    var nAny = 0
    var bits = 0
    found = findMethod(
      node: node,
      methodName: methodName,
      nAny: &nAny,
      bits: &bits,
      ownResultTypes: &ownResultTypes
    )
    node.types = dedup(types: ownResultTypes)
    if !found && ((nAny == types.count) || (bits == 0b111 && types.count == 3)) {
      found = guessMethod(node: node, methodName: methodName, ownResultTypes: &ownResultTypes)
    }
    let onlyDisabler = types.count == 1 && types[0] is Disabler
    if !found && !onlyDisabler {
      let t = joinTypes(types: types)
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(
          sev: .error,
          node: node,
          message: "No method `\(methodName)` found for types `\(t)'"
        )
      )
    } else if !found && onlyDisabler {
      Self.LOG.info("Ignoring invalid method for disabler")
    } else {
      if let args = node.argumentList, args is ArgumentList {
        if self.version != nil,
          let alts = DeprecationState.check(name: node.method!.id(), version: self.version!)
        {
          self.registerDeprecated(node.method!.id(), node.id, alts)
        }
        self.checkCall(node: node)
      } else if node.argumentList == nil {
        if node.method!.minPosArgs() != 0 {
          self.metadata.registerDiagnostic(
            node: node,
            diag: MesonDiagnostic(
              sev: .error,
              node: node,
              message: "Expected " + String(node.method!.minPosArgs())
                + " positional arguments, but got none!"
            )
          )
        }
      }
      if let al = node.argumentList as? ArgumentList {
        for a in al.args where a is KeywordItem {
          self.metadata.registerKwarg(item: a as! KeywordItem, f: node.method!)
        }
      }
      if self.version != nil,
        let alts = DeprecationState.check(name: node.method!.id(), version: self.version!)
      {
        self.registerDeprecated(node.method!.id(), node.id, alts)
      }
      if let sl = node.obj as? StringLiteral, node.method!.id() == "str.format" {
        var args: [Node] = []
        if let al = node.argumentList as? ArgumentList { args = al.args }
        self.checkFormat(sl, args)
      }
    }
  }
  // swiftlint:enable cyclomatic_complexity

  private func checkFormat(_ sl: StringLiteral, _ args: [Node]) {
    let s = sl.contents()
    var idx = 0
    for arg in args {
      if !s.contains("@\(idx)@") {
        self.metadata.registerDiagnostic(
          node: arg,
          diag: MesonDiagnostic(
            sev: .warning,
            node: arg,
            message: "Unused parameter in format() call"
          )
        )
      }
      idx += 1
    }
    do {
      let pattern = #"@(\d+)@"#
      let regex = try NSRegularExpression(pattern: pattern, options: [])
      let matches = regex.matches(in: s, options: [], range: NSRange(s.startIndex..., in: s))

      var found = Set<UInt>()
      for match in matches {
        if let range = Range(match.range(at: 1), in: s) {
          let matchedSubstring = String(s[range])
          let asInt = UInt(matchedSubstring)!
          if asInt >= args.count { found.insert(asInt) }
        }
      }
      if found.isEmpty {
        if args.isEmpty {
          self.metadata.registerDiagnostic(
            node: sl.parent!,
            diag: MesonDiagnostic(
              sev: .warning,
              node: sl.parent!,
              message: "Pointless str.format() call"
            )
          )
        }
        return
      }
      let params = found.map { "@\($0)@" }.joined(separator: ", ")
      self.metadata.registerDiagnostic(
        node: sl,
        diag: MesonDiagnostic(sev: .error, node: sl, message: "Parameters out of bounds: \(params)")
      )
    } catch { Self.LOG.error("Error: \(error)") }

  }

  private func checkKwargsAfterPositionalArguments(_ args: [Node]) {
    var kwargsOnly = false
    for arg in args {
      if kwargsOnly {
        if arg is KeywordItem { continue }
        self.metadata.registerDiagnostic(
          node: arg,
          diag: MesonDiagnostic(
            sev: .error,
            node: arg,
            message: "Unexpected positional argument after a keyword argument"
          )
        )
        continue
      } else if arg is KeywordItem {
        kwargsOnly = true
      }
    }
  }

  private func checkKwargs(_ fn: Function, _ args: [Node], _ node: Node) {
    var usedKwargs: [String: KeywordItem] = [:]
    for arg in args where arg is KeywordItem {
      let k = (arg as! KeywordItem).key
      if let kId = k as? IdExpression {
        if usedKwargs[kId.id] != nil {
          self.metadata.registerDiagnostic(
            node: arg,
            diag: MesonDiagnostic(
              sev: .warning,
              node: arg,
              message: "Duplicate key word argument \(kId.id)"
            )
          )
          continue
        }
        usedKwargs[kId.id] = (arg as! KeywordItem)
        if !fn.hasKwarg(name: kId.id) && kId.id != "kwargs" {
          self.metadata.registerDiagnostic(
            node: arg,
            diag: MesonDiagnostic(
              sev: .error,
              node: arg,
              message: "Unknown key word argument '" + kId.id + "'!"
            )
          )
        }
      }
    }
    if usedKwargs["kwargs"] == nil {
      for requiredKwarg in fn.requiredKwargs() where usedKwargs[requiredKwarg] == nil {
        self.metadata.registerDiagnostic(
          node: node,
          diag: MesonDiagnostic(
            sev: .error,
            node: node,
            message: "Missing required key word argument '" + requiredKwarg + "'!"
          )
        )
      }
    }
  }

  private func checkCall(node: Expression) {
    let args: [Node]
    let fn: Function
    if let fne = node as? FunctionExpression {
      fn = fne.function!
      if let al = fne.argumentList as? ArgumentList { args = al.args } else { args = [] }
    } else if let me = node as? MethodExpression {
      fn = me.method!
      if let al = me.argumentList as? ArgumentList { args = al.args } else { args = [] }
    } else {
      return
    }
    checkKwargsAfterPositionalArguments(args)
    var nKwargs = 0
    var nPos = 0
    for arg in args { if arg is KeywordItem { nKwargs += 1 } else { nPos += 1 } }
    if nPos < fn.minPosArgs() {
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(
          sev: .error,
          node: node,
          message: "Expected " + String(fn.minPosArgs()) + " positional arguments, but got "
            + String(nPos) + "!"
        )
      )
    }
    if nPos > fn.maxPosArgs() {
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(
          sev: .error,
          node: node,
          message: "Expected " + String(fn.maxPosArgs()) + " positional arguments, but got "
            + String(nPos) + "!"
        )
      )
    }
    checkKwargs(fn, args, node)
    checkArgTypes(fn, args, node)
  }

  private func checkArgTypes(_ fn: Function, _ args: [Node], _ node: Node) {
    var posArgsIdx = 0
    for arg in args {
      if arg is KeywordItem {
        let givenTypes = (arg as! KeywordItem).value.types
        guard let kwarg = fn.kwargs[((arg as! KeywordItem).key as! IdExpression).id] else {
          continue
        }
        let expectedTypes = kwarg.types
        self.checkTypes(fn, arg, expectedTypes, givenTypes)
      } else {
        if let posArg = fn.posArg(posArgsIdx) { self.checkTypes(fn, arg, posArg.types, arg.types) }
        posArgsIdx += 1
      }
    }
  }

  private func atleastPartiallyCompatible(_ given: [Type], _ expected: [Type]) -> Bool {
    if given.isEmpty { return true }
    for g in given {
      if g is `Any` || g is Disabler { return true }
      for e in expected where self.compatible(g, e) || e is `Any` { return true }
    }
    return false
  }

  private func checkTypes(_ fn: Function, _ arg: Node, _ expected: [Type], _ given: [Type]) {
    if self.atleastPartiallyCompatible(given, expected) { return }
    self.metadata.registerDiagnostic(
      node: arg,
      diag: MesonDiagnostic(
        sev: .error,
        node: arg,
        message: "Expected \(self.joinTypes(types: expected)), got \(self.joinTypes(types: given))"
      )
    )
  }

  private func compatible(_ given: Type, _ expected: Type) -> Bool {
    if given.toString() == expected.toString() { return true }
    if let g = given as? AbstractObject, let p = g.parent, self.compatible(p, expected) {
      return true
    }
    if let l = given as? ListType, let r = expected as? ListType {
      return self.atleastPartiallyCompatible(l.types, r.types)
    }
    if let r = expected as? ListType, self.atleastPartiallyCompatible([given], r.types) {
      return true
    }
    if let l = given as? ListType, self.atleastPartiallyCompatible(l.types, [expected]) {
      return true
    }
    if let l = given as? Dict, let r = expected as? Dict {
      return self.atleastPartiallyCompatible(l.types, r.types)
    }
    return false
  }

  public func evalStack(name: String) -> [Type] {
    var ret: [Type] = []
    for ov in self.overriddenVariables where ov[name] != nil { ret += ov[name]! }
    return ret
  }

  private func ignoreIdExpression(node: IdExpression) -> Bool {
    let parent = node.parent
    return (parent is FunctionExpression && (parent as! FunctionExpression).id.equals(right: node))
      || (parent is MethodExpression && (parent as! MethodExpression).id.equals(right: node))
      || (parent is KeywordItem && (parent as! KeywordItem).key.equals(right: node))
      || self.ignoreUnknownIdentifer.contains(node.id)
  }

  public func visitIdExpression(node: IdExpression) {
    let s = self.evalStack(name: node.id)
    node.types = dedup(types: s + (scope.variables[node.id] ?? []))
    node.visitChildren(visitor: self)
    if let p = node.parent {
      if let ass = p as? AssignmentStatement {
        if ass.op != .equals || ass.rhs.equals(right: node) { self.registerUsed(node.id) }
      } else if let kw = p as? KeywordItem, kw.value.equals(right: node) {
        self.registerUsed(node.id)
      } else if p is FunctionExpression {
        // Do nothing
      } else {
        self.registerUsed(node.id)
      }
    } else {
      self.registerUsed(node.id)
    }
    if self.ignoreIdExpression(node: node) { return }
    if !isKnownId(id: node) {
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(sev: .error, node: node, message: "Unknown identifier `\(node.id)`")
      )
    }
    self.metadata.registerIdentifier(id: node)
  }

  private func registerUsed(_ id: String) {
    var new: [[IdExpression]] = []
    for arr in self.variablesNeedingUse.reversed() {
      var n: [IdExpression] = []
      for a in arr where a.id != id { n.append(a) }
      new.append(n)
    }
    self.variablesNeedingUse = new
  }

  private func isKnownId(id: IdExpression) -> Bool {
    let parent = id.parent
    if let a = parent as? AssignmentStatement, let b = a.lhs as? IdExpression {
      if b.id == id.id && a.op == .equals { return true }
    } else if let i = parent as? IterationStatement {
      for idd in i.ids { if let l = idd as? IdExpression, id.id == l.id { return true } }
    } else if let kw = parent as? KeywordItem, let b = kw.key as? IdExpression, id.id == b.id {
      return true
    } else if let fe = parent as? FunctionExpression, let b = fe.id as? IdExpression, id.id == b.id
    {
      return true
    } else if let me = parent as? MethodExpression, let b = me.id as? IdExpression, id.id == b.id {
      return true
    }

    return self.scope.variables[id.id] != nil
  }

  private func isType(_ type: Type, _ name: String) -> Bool {
    return type.name == name || type.name == "any"
  }

  public func visitBinaryExpression(node: BinaryExpression) {
    node.visitChildren(visitor: self)
    if node.op == nil {
      // Emergency fix
      node.types = dedup(types: node.lhs.types + node.rhs.types)
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(sev: .error, node: node, message: "Missing binary operator")
      )
      return
    }
    let (nErrors, newTypes) = self.evalBinaryExpression(node.op!, node.lhs.types, node.rhs.types)
    let nTimes = node.lhs.types.count * node.rhs.types.count
    if nTimes != 0 && nErrors == nTimes && (!node.lhs.types.isEmpty) && (!node.rhs.types.isEmpty)
      && !self.isSpecial(node.lhs.types) && !self.isSpecial(node.rhs.types)
    {
      self.metadata.registerDiagnostic(
        node: node,
        diag: MesonDiagnostic(
          sev: .error,
          node: node,
          message:
            "Unable to apply operator `\(node.op!)` to types \(self.joinTypes(types: node.lhs.types)) and \(self.joinTypes(types: node.rhs.types))"
        )
      )
    }
    node.types = dedup(types: newTypes)
    if node.parent! is AssignmentStatement || node.parent! is SelectionStatement {
      if let me = node.lhs as? MethodExpression, let sl = node.rhs as? StringLiteral {
        self.checkIfSpecialComparison(me, sl)
      } else if let me = node.rhs as? MethodExpression, let sl = node.lhs as? StringLiteral {
        self.checkIfSpecialComparison(me, sl)
      }
    }
  }

  private func checkIfSpecialComparison(_ me: MethodExpression, _ sl: StringLiteral) {
    if let m = me.method, !self.analysisOptions.disableAllIdLinting {
      let mid = m.id()
      let arg = sl.contents()
      if mid == "compiler.get_id", !self.compilerIds.contains(arg),
        !self.analysisOptions.disableCompilerIdLinting
      {
        self.metadata.registerDiagnostic(
          node: sl,
          diag: MesonDiagnostic(sev: .warning, node: sl, message: "Unknown compiler id")
        )
      } else if mid == "compiler.get_argument_syntax", !self.argumentSyntaxes.contains(arg),
        !self.analysisOptions.disableCompilerArgumentIdLinting
      {
        self.metadata.registerDiagnostic(
          node: sl,
          diag: MesonDiagnostic(
            sev: .warning,
            node: sl,
            message: "Unknown compiler argument syntax"
          )
        )
      } else if mid == "compiler.get_linker_id",
        !self.linkerIds.contains(arg) || self.compilerIds.contains(arg),
        !self.analysisOptions.disableLinkerIdLinting
      {
        self.metadata.registerDiagnostic(
          node: sl,
          diag: MesonDiagnostic(sev: .warning, node: sl, message: "Unknown linker id")
        )
      } else if mid == "build_machine.cpu_family", !self.cpuFamilies.contains(arg),
        !self.analysisOptions.disableCpuFamilyLinting
      {
        self.metadata.registerDiagnostic(
          node: sl,
          diag: MesonDiagnostic(sev: .warning, node: sl, message: "Unknown cpu family")
        )
      } else if mid == "build_machine.system", !self.osNames.contains(arg),
        !self.analysisOptions.disableOsFamilyLinting
      {
        self.metadata.registerDiagnostic(
          node: sl,
          diag: MesonDiagnostic(sev: .warning, node: sl, message: "Unknown operating system name")
        )
      }
    }
  }

  private func isSpecial(_ types: [Type]) -> Bool {
    if types.count != 3 { return false }
    var counter = 0
    for t in types {
      if t is `Any` {
        counter += 1
      } else if let lt = t as? ListType, lt.types.count == 1, lt.types[0] is `Any` {
        counter += 1
      } else if let dt = t as? Dict, dt.types.count == 1, dt.types[0] is `Any` {
        counter += 1
      }
    }
    return counter == 3
  }
  public func visitStringLiteral(node: StringLiteral) {
    node.types = [self.t.strType]
    self.metadata.registerStringLiteral(node: node)
  }

  public func visitArrayLiteral(node: ArrayLiteral) {
    node.visitChildren(visitor: self)
    let t = node.args.flatMap { $0.types }
    node.types = [ListType(types: dedup(types: t))]
  }

  public func visitBooleanLiteral(node: BooleanLiteral) { node.types = [self.t.boolType] }

  public func visitIntegerLiteral(node: IntegerLiteral) { node.types = [self.t.intType] }

  public func visitDictionaryLiteral(node: DictionaryLiteral) {
    node.visitChildren(visitor: self)
    let t = node.values.flatMap { $0.types }
    node.types = [Dict(types: dedup(types: t))]
    var seenKeys: Set<String> = []
    for keyV in node.values
    where keyV is KeyValueItem && ((keyV as! KeyValueItem).key) is StringLiteral {
      let sl = ((keyV as! KeyValueItem).key) as! StringLiteral
      if seenKeys.contains(sl.contents()) {
        self.metadata.registerDiagnostic(
          node: sl,
          diag: MesonDiagnostic(
            sev: .warning,
            node: sl,
            message: "Duplicate key \"\(sl.contents())\""
          )
        )
      } else {
        seenKeys.insert(sl.contents())
      }
    }
  }

  public func visitKeyValueItem(node: KeyValueItem) {
    node.visitChildren(visitor: self)
    node.types = node.value.types
  }

  private func isSnakeCase(str: String) -> Bool {
    for s in str where s.isUppercase { return false }
    return true
  }

  private func isShoutingSnakeCase(str: String) -> Bool {
    for s in str where s.isLowercase { return false }
    return true
  }

  public func joinTypes(types: [Type]) -> String {
    return types.map { $0.toString() }.sorted().joined(separator: "|")
  }

  private func checkNoEffect(_ b: Node) {
    var noEffect = false
    if b is IntegerLiteral || b is StringLiteral || b is BooleanLiteral || b is ArrayLiteral
      || b is DictionaryLiteral
    {
      noEffect = true
    } else if let fn = b as? FunctionExpression, let fnid = fn.id as? IdExpression {
      let fname = fnid.id
      noEffect = self.pureFunctions.contains(fname)
    } else if let me = b as? MethodExpression, let method = me.method {
      let methodName = method.id()
      noEffect = self.pureMethods.contains(methodName)
    }
    if noEffect {
      self.metadata.registerDiagnostic(
        node: b,
        diag: MesonDiagnostic(
          sev: .warning,
          node: b,
          message: "Statement does not have an effect or the result to the call is unused"
        )
      )
    }
  }

  private func isDead(_ b: Node) -> Bool {
    // We could check, if it is e.g. an assert(false)
    if let fn = b as? FunctionExpression, let fnid = fn.id as? IdExpression,
      fnid.id == "error" || fnid.id == "subdir_done"
    {
      return true
    }
    return false
  }

  private func applyDead(_ lastAlive: Node?, _ firstDead: Node?, _ lastDead: Node?) {
    if lastAlive == nil { return }
    if firstDead == nil || lastDead == nil { return }
    self.metadata.registerDiagnostic(
      begin: firstDead!,
      end: lastDead!,
      diag: MesonDiagnostic(sev: .warning, begin: firstDead!, end: lastDead!, message: "Dead code")
    )
  }

  // swiftlint:disable cyclomatic_complexity
  public func dedup(types: [Type]) -> [Type] {
    if types.isEmpty || types.count == 1 { return types }
    var listtypes: [Type] = []
    var dicttypes: [Type] = []
    var subprojectNames: [String] = []
    var hasAny: Bool = false
    var hasBool: Bool = false
    var hasInt: Bool = false
    var hasStr: Bool = false
    var objs: [String: Type] = [:]
    var gotList: Bool = false
    var gotDict: Bool = false
    var gotSubproject: Bool = false
    for t in types {
      if t is `Any` {
        hasAny = true
        continue
      } else if t is BoolType {
        hasBool = true
      } else if t is `IntType` {
        hasInt = true
      } else if t is Str {
        hasStr = true
      } else if let d = t as? Dict {
        dicttypes += d.types
        gotDict = true
      } else if let lt = t as? ListType {
        listtypes += lt.types
        gotList = true
      } else if let st = t as? MesonAST.Subproject {
        subprojectNames += st.names
        gotSubproject = true
      } else {
        objs[t.name] = t
      }
    }
    var ret: [Type] = []
    if !listtypes.isEmpty || gotList { ret.append(ListType(types: dedup(types: listtypes))) }
    if !dicttypes.isEmpty || gotDict { ret.append(Dict(types: dedup(types: dicttypes))) }
    if !subprojectNames.isEmpty || gotSubproject {
      ret.append(MesonAST.Subproject(names: Array(Set(subprojectNames))))
    }
    if hasAny { ret.append(self.t.types["any"]!) }
    if hasBool { ret.append(self.t.boolType) }
    if hasInt { ret.append(self.t.intType) }
    if hasStr { ret.append(self.t.strType) }
    ret += objs.values
    return ret
  }

  private func evalBinaryExpression(_ op: BinaryOperator, _ lhs: [Type], _ rhs: [Type]) -> (
    Int, [Type]
  ) {
    var newTypes: [Type] = []
    var nErrors = 0
    for l in lhs {
      for r in rhs {
        // Theoretically not an error (yet),
        // but practically better safe than sorry.
        if r.name == "any" && l.name == "any" {
          nErrors += 1
          continue
        }
        switch op {
        case .and, .or:
          if isType(l, "bool") && isType(r, "bool") {
            newTypes.append(self.t.boolType)
          } else {
            nErrors += 1
          }
        case .div:
          if isType(l, "int") && isType(r, "int") {
            newTypes.append(self.t.intType)
          } else if isType(l, "str") && isType(r, "str") {
            newTypes.append(self.t.strType)
          } else {
            nErrors += 1
          }
        case .equalsEquals:
          if isType(l, "int") && isType(r, "int") {
            newTypes.append(self.t.boolType)
          } else if isType(l, "str") && isType(r, "str") {
            newTypes.append(self.t.boolType)
          } else if isType(l, "bool") && isType(r, "bool") {
            newTypes.append(self.t.boolType)
          } else if isType(l, "dict") && isType(r, "dict") {
            newTypes.append(self.t.boolType)
          } else if isType(l, "list") && isType(r, "list") {
            newTypes.append(self.t.boolType)
          } else if l is AbstractObject && r is AbstractObject && l.name == r.name {
            newTypes.append(self.t.boolType)
          } else {
            nErrors += 1
          }
        case .ge, .gt, .le, .lt:
          if isType(l, "int") && isType(r, "int") {
            newTypes.append(self.t.boolType)
          } else if isType(l, "str") && isType(r, "str") {
            newTypes.append(self.t.boolType)
          } else {
            nErrors += 1
          }
        case .IN: newTypes.append(self.t.boolType)
        case .minus, .modulo, .mul:
          if isType(l, "int") && isType(r, "int") {
            newTypes.append(self.t.intType)
          } else {
            nErrors += 1
          }
        case .notEquals:
          if isType(l, "int") && isType(r, "int") {
            newTypes.append(self.t.boolType)
          } else if isType(l, "str") && isType(r, "str") {
            newTypes.append(self.t.boolType)
          } else if isType(l, "bool") && isType(r, "bool") {
            newTypes.append(self.t.boolType)
          } else if isType(l, "dict") && isType(r, "dict") {
            newTypes.append(self.t.boolType)
          } else if isType(l, "list") && isType(r, "list") {
            newTypes.append(self.t.boolType)
          } else if l is AbstractObject && r is AbstractObject && l.name == r.name {
            newTypes.append(self.t.boolType)
          } else {
            nErrors += 1
          }
        case .notIn: newTypes.append(self.t.boolType)
        case .plus:
          if isType(l, "int") && isType(r, "int") {
            newTypes.append(self.t.intType)
          } else if isType(l, "str") && isType(r, "str") {
            newTypes.append(self.t.strType)
          } else if let ll = l as? ListType, let lr = r as? ListType {
            newTypes.append(ListType(types: dedup(types: ll.types + lr.types)))
          } else if let ll = l as? ListType {
            newTypes.append(ListType(types: dedup(types: ll.types + CollectionOfOne(r))))
          } else if let dl = l as? Dict, let dr = r as? Dict {
            newTypes.append(Dict(types: dedup(types: dl.types + dr.types)))
          } else if let dl = l as? Dict {
            newTypes.append(Dict(types: dedup(types: dl.types + CollectionOfOne(r))))
          } else {
            nErrors += 1
          }
        }
      }
    }
    return (nErrors, nErrors == lhs.count * rhs.count ? lhs : newTypes)
  }

  // swiftlint:enable cyclomatic_complexity
}
