import MesonAST

public class OptionTypeAnalyzer: MesonTypeAnalyzer {
  public func derive(node: Node, fn: Function, options: [MesonOption], ns: TypeNamespace) -> [Type]
  {
    if let fe = node as? FunctionExpression, let feid = fe.id as? IdExpression,
      feid.id == "get_option", let alo = fe.argumentList, let al = alo as? ArgumentList,
      !al.args.isEmpty
    {
      let arg0 = al.args[0]
      if let sl = arg0 as? StringLiteral {
        let t = sl.contents()
        let opt = options.first { $0.name == t }
        if let o = opt {
          if o is StringOption {
            return [ns.types["str"]!]
          } else if o is IntOption {
            return [ns.types["int"]!]
          } else if o is BoolOption {
            return [ns.types["bool"]!]
          } else if o is FeatureOption {
            return [ns.types["feature"]!]
          } else if o is ComboOption {
            return [ns.types["str"]!]
          } else {
            return [ListType(types: [ns.types["str"]!])]
          }
        }
      }
    }
    return fn.returnTypes
  }
}
