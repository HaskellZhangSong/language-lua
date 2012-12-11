{-# LANGUAGE FlexibleContexts, NoMonomorphismRestriction #-}
{-# OPTIONS_GHC -Wall #-}

-- | Lexer/Parsec interface
module Text.Parsec.LTok where

import Language.Lua.Lexer (LTok, AlexPosn(..))
import Language.Lua.Token

import Text.Parsec hiding (satisfy)

type Parser = Parsec [LTok] ()

-- | This parser succeeds whenever the given predicate returns true when called with
-- parsed `LTok`. Same as 'Text.Parsec.Char.satisfy'.
satisfy :: (Stream [LTok] m LTok) => (LTok -> Bool) -> ParsecT [LTok] u m LToken
satisfy f = tokenPrim show nextPos tokeq
  where nextPos :: SourcePos -> LTok -> [LTok] -> SourcePos
        nextPos pos _ ((_, (Right (AlexPn _ l c))):_) = setSourceColumn (setSourceLine pos l) c
        nextPos pos _ ((_, (Left _)):_)               = pos -- TODO: ??
        nextPos pos _ []                              = pos

        tokeq :: LTok -> Maybe LToken
        tokeq t = if f t then Just (fst t) else Nothing

-- | Parses given `LToken`.
tok :: (Stream [LTok] m LTok) => LToken -> ParsecT [LTok] u m LToken
tok t = satisfy (\(t', _) -> t' == t) <?> show t

-- | Parses a `LTokIdent`.
anyIdent :: Monad m => ParsecT [LTok] u m LToken
anyIdent = satisfy p <?> "ident"
  where p (t, _) = case t of LTokIdent _ -> True
                             _ -> False

-- | Parses a `LTokNum`.
anyNum :: Monad m => ParsecT [LTok] u m LToken
anyNum = satisfy p <?> "number"
    where p (t, _) = case t of LTokNum _ -> True
                               _ -> False

-- | Parses a `LTokSLit`.
string :: Monad m => ParsecT [LTok] u m LToken
string = satisfy p <?> "string"
    where p (t, _) = case t of LTokSLit _ -> True
                               _ -> False
