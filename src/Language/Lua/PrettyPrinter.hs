{-# OPTIONS_GHC -Wall
                -fno-warn-hi-shadowing
                -fno-warn-name-shadowing
                -fno-warn-unused-do-bind #-}
{-# LANGUAGE FlexibleInstances #-}

module Language.Lua.PrettyPrinter (pprint, Printer(..)) where

import Prelude hiding (EQ, GT, LT)
import Text.PrettyPrint.Leijen hiding ((<$>))

import Language.Lua.Types

data Printer = Printer { ident :: Int }

intercalate :: Doc -> [Doc] -> Doc
intercalate s elems = sep (punctuate s elems)

infixr 5 <$>
(<$>) :: Doc -> Doc -> Doc
x <$> y | isEmpty y = x
        | otherwise = x <> line <> y

class LPretty a where
    pprint :: Printer -> a -> Doc

instance LPretty [Char] where
    pprint _ s = text s

instance LPretty Bool where
    pprint _ True  = text "true"
    pprint _ False = text "false"

instance LPretty Exp where
    pprint _ Nil              = text "nil"
    pprint p (Bool s)         = pprint p s
    pprint _ (Number n)       = text n
    pprint _ (String s)       = dquotes (text s)
    pprint _ Vararg           = text "..."
    pprint p (EFunDef f)      = pprint p f
    pprint p (PrefixExp pe)   = pprint p pe
    pprint p (TableConst t)   = pprint p t
    pprint p (Binop op e1 e2) = pprint p e1 <+> pprint p op <+> pprint p e2
    pprint p (Unop op e)      = pprint p op <> pprint p e

instance LPretty Var where
    pprint _ (Name n)             = text n
    pprint p (Select pe e)        = pprint p pe <> brackets (pprint p e)
    pprint p (SelectName pe name) = group (pprint p pe <$$> (char '.' <> pprint p name))

instance LPretty Binop where
    pprint _ Add    = char '+'
    pprint _ Sub    = char '-'
    pprint _ Mul    = char '*'
    pprint _ Div    = char '/'
    pprint _ Exp    = char '^'
    pprint _ Mod    = char '%'
    pprint _ Concat = text ".."
    pprint _ LT     = char '<'
    pprint _ LTE    = text "<="
    pprint _ GT     = char '>'
    pprint _ GTE    = text ">="
    pprint _ EQ     = text "=="
    pprint _ NEQ    = text "~="
    pprint _ And    = text "and"
    pprint _ Or     = text "or"

instance LPretty Unop where
    pprint _ Neg = char '-'
    pprint _ Not = text "not "
    pprint _ Len = char '#'

instance LPretty PrefixExp where
    pprint p (PEVar var)         = pprint p var
    pprint p (PEFunCall funcall) = pprint p funcall
    pprint p (Paren e)           = parens (pprint p e)

instance LPretty Table where
    pprint p (Table fields) = braces (nest 4 (cat (punctuate comma (map (pprint p) fields))))

instance LPretty TableField where
    pprint p (ExpField e1 e2)    = brackets (pprint p e1) <+> equals <+> pprint p e2
    pprint p (NamedField name e) = pprint p name <+> equals <+> pprint p e
    pprint p (Field e)           = pprint p e

instance LPretty Block where
    pprint p (Block stats ret)
        = case stats of
            [] -> ret'
            _  -> (foldr (<$>) empty (map (pprint p) stats)) <$> ret'
      where ret' = case ret of
                     Nothing -> empty
                     Just e  -> nest 2 (text "return" </> (intercalate comma (map (pprint p) e)))

instance LPretty FunName where
    pprint p (FunName name s methods) = text name <> s' <> (intercalate colon (map (pprint p) methods))
      where s' = case s of
                   Nothing -> empty
                   Just s' -> char '.' <> text s'

instance LPretty FunDef where
    pprint p (FunDef body) = pprint p body

instance LPretty FunBody where
    pprint p funbody = pprintFunction p Nothing funbody

pprintFunction :: Printer -> Maybe Doc -> FunBody -> Doc
pprintFunction p funname (FunBody args vararg block)
    = group (nest 4 (funhead <$> funbody) <$> end)
  where funhead = case funname of
                    Nothing -> nest 2 (text "function" </> args')
                    Just n  -> nest 2 (text "function" </> n </> args')
        args' = parens (align (cat (punctuate (comma <> space)
                                        (map (pprint p) (args ++ if vararg then ["..."] else [])))))
        funbody = pprint p block
        end = text "end"

instance LPretty FunCall where
    pprint p (NormalFunCall pe arg)     = group (nest 4 (pprint p pe <$$> pprint p arg))
    pprint p (MethodCall pe method arg) = group (nest 4 (pprint p pe <$$> (colon <> text method) <$$> pprint p arg))

instance LPretty FunArg where
    pprint p (Args exps)   = parens (nest 4 (cat (punctuate (comma <> space) (map (pprint p) exps))))
    pprint p (TableArg t)  = pprint p t
    pprint _ (StringArg s) = dquotes (text s)

instance LPretty Stat where
    pprint p (Assign names vals)
        =   (intercalate comma (map (pprint p) names))
        <+> equals
        <+> (intercalate comma (map (pprint p) vals))
    pprint p (FunCall funcall) = pprint p funcall
    pprint p (Label name)      = text "::" <> text name <> text "::"
    pprint p Break             = text "break"
    pprint p (Goto name)       = text "goto" <+> text name
    pprint p (Do block)        = group (nest 4 (text "do" <$> pprint p block) <$> text "end")
    pprint p (While guard e)
        =  (nest 4 (text "while" <+> pprint p guard <+> text "do"
                   </> indent 4 (pprint p e)))
       </> text "end"
    pprint p (Repeat block guard)
        = nest 4 (text "repeat" </> pprint p block) </> (nest 4 (text "until" </> pprint p guard))

    pprint p (If cases elsePart) = group (printIf cases elsePart)
      where printIf ((guard, block):xs) e
                =   group (nest 4 (text "if" <+> pprint p guard <+> text "then"
                        <$> pprint p block))
                <$> printIf' p xs e

            printIf' p [] Nothing  = text "end"
            printIf' p [] (Just b) = group (nest 4 (text "else" </> pprint p b)
                                         <$> text "end")
            printIf' p ((guard, block):xs) e
                =   group (nest 4 (text "elseif" <+> pprint p guard <+> text "then"
                        <$> pprint p block))
                <$> printIf' p xs e

    pprint p (ForRange name e1 e2 e3 block)
        =   text "for" <+> text name <> equals <> pprint p e1 <> comma <> pprint p e2 <> e3' <+> text "do"
        <$> indent 4 (pprint p block)
        <$> text "end"
      where e3' = case e3 of
                    Nothing -> empty
                    Just e  -> comma <> pprint p e

    pprint p (ForIn names exps block)
        =   text "for" <+> (intercalate comma (map (pprint p) names))
                <+> text "in" <+> (intercalate comma (map (pprint p) exps)) <+> text "do"
        <$> indent 4 (pprint p block)
        <$> text "end"

    pprint p (FunAssign name body) = pprintFunction p (Just (pprint p name)) body
    pprint p (LocalFunAssign name body) = text "local" <+> pprintFunction p (Just (pprint p name)) body
    pprint p (LocalAssign names exps)
        = text "local" <+> (intercalate comma (map (pprint p) names)) <+> equals <+> exps'
      where exps' = case exps of
                      Nothing -> empty
                      Just es -> intercalate comma (map (pprint p) es)
    pprint p EmptyStat = empty