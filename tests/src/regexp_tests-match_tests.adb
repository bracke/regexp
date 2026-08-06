with Regexp;
with Regexp_Tests.Support;

package body Regexp_Tests.Match_Tests is
   use Regexp;
   use Regexp_Tests.Support;

   function Abort_Immediately return Boolean is
   begin
      return True;
   end Abort_Immediately;

   procedure Test_Core_Matching (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("abc", "xxabcxx", Match_Ok, "literal match", 3, 5);
      Check_Match ("abc", "abx", No_Match, "literal no match");
      Check_Match ("a.c", "xxabc", Match_Ok, "dot match", 3, 5);
      Check_Match ("a.c", "a" & Character'Val (10) & "c", No_Match, "dot no line break");
      Check_Match ("a.c", "a" & Character'Val (13) & "c", No_Match, "dot no carriage return");
      Check_Match ("^abc", "abcdef", Match_Ok, "start anchor", 1, 3);
      Check_Match ("abc$", "xxabc", Match_Ok, "end anchor", 3, 5);
      Check_Match ("abc$", "abc" & Character'Val (10), No_Match, "end anchor not before LF");
      Check_Match ("ab*c", "ac", Match_Ok, "star zero", 1, 2);
      Check_Match ("ab*c", "abbbc", Match_Ok, "star many", 1, 5);
      Check_Match ("ab+c", "ac", No_Match, "plus requires one");
      Check_Match ("ab+c", "abbc", Match_Ok, "plus many", 1, 4);
      Check_Match ("ab?c", "ac", Match_Ok, "question zero", 1, 2);
      Check_Match ("ab?c", "abc", Match_Ok, "question one", 1, 3);
      Check_Match ("a*", "bbb", Match_Ok, "zero length", 1, 0);
      Check_Match ("b*", "aaab", Match_Ok, "zero length before later non-zero match", 1, 0);
      Check_Match ("^$", "", Match_Ok, "empty text anchors", 1, 0);
      Check_Match ("^a*$", "aaa", Match_Ok, "entire anchored star", 1, 3);
      Check_Match ("a*", "", Match_Ok, "empty text zero length", 1, 0);
      Check_Match ("a*", "aaa", Match_Ok, "star longest", 1, 3);
      Check_Match ("a*?", "aaa", Match_Ok, "lazy star shortest", 1, 0);
      Check_Match ("a+?", "aaa", Match_Ok, "lazy plus shortest", 1, 1);
      Check_Match ("a??a", "aaa", Match_Ok, "lazy optional shortest", 1, 1);
      Check_Match ("a*", "bbb", No_Match, "entire zero length over non-empty", Entire => True);
      Check_Match ("cat|dog", "xxdogxx", Match_Ok, "alternation second branch", 3, 5);
      Check_Match ("cat|dog", "xxcatxx", Match_Ok, "alternation first branch", 3, 5);
      Check_Match ("cat|dog", "xxfoxxx", No_Match, "alternation no match");
      Check_Match ("ab*|cd+", "xxabbb", Match_Ok, "alternation with quantifier", 3, 6);
      Check_Match ("(?:cat|dog)", "xxdogxx", Match_Ok, "grouped alternation", 3, 5);
      Check_Match ("()", "abc", Match_Ok, "empty capturing group", 1, 0);
      Check_Match ("(?:)", "abc", Match_Ok, "empty non-capturing group", 1, 0);
      Check_Match ("|a", "", Match_Ok, "leading empty alternative", 1, 0, Entire => True);
      Check_Match ("a|", "", Match_Ok, "trailing empty alternative", 1, 0, Entire => True);
      Check_Match ("a||b", "", Match_Ok, "middle empty alternative", 1, 0, Entire => True);
      Check_Match ("x(?:ab)+y", "xxababyy", Match_Ok, "grouped plus quantifier", 2, 7);
      Check_Match ("(?:ab){2,3}", "xxababab", Match_Ok, "grouped bounded repeat", 3, 8);
      Check_Match ("(?:(?:ab)|cd)+", "xxabcd", Match_Ok, "nested grouped alternation", 3, 6);
      Check_Match ("a(?=b)", "xab", Match_Ok, "positive lookahead", 2, 2);
      Check_Match ("a(?=b)", "xac", No_Match, "positive lookahead negative case");
      Check_Match ("a(?!b)", "xac", Match_Ok, "negative lookahead", 2, 2);
      Check_Match ("a(?!b)", "xab", No_Match, "negative lookahead negative case");
      Check_Match ("a(?!b)", "xa", Match_Ok, "negative lookahead at end", 2, 2);
      Check_Match ("(?=ab)ab", "xxab", Match_Ok, "leading lookahead", 3, 4);
      Check_Match ("(?<=a)b", "xab", Match_Ok, "positive lookbehind", 3, 3);
      Check_Match ("(?<=a)b", "xcb", No_Match, "positive lookbehind negative case");
      Check_Match ("(?<!a)b", "xcb", Match_Ok, "negative lookbehind", 3, 3);
      Check_Match ("(?<!a)b", "xab", No_Match, "negative lookbehind negative case");
      Check_Match ("(?<!a)b", "b", Match_Ok, "negative lookbehind at start", 1, 1);
      Check_Match ("(?<=ab|cd)e", "xxcde", Match_Ok, "fixed-width alternation lookbehind", 5, 5);
      Check_Match
        ("(?i:a)",
         "A",
         Match_Ok,
         "inline case-insensitive option",
         1,
         1,
         Options => (Case_Sensitive => True, others => <>));
      Check_Match ("(?-i:a)", "A", No_Match, "inline case-sensitive option");
      Check_Match ("(?i:[a])", "A", Match_Ok, "inline option applies to class", 1, 1);
      Check_Match
        ("(?i:a)b",
         "AB",
         No_Match,
         "inline option scope does not leak",
         Options => (Case_Sensitive => True, others => <>));
      Check_Match ("(?s:.)", Character'Val (10) & "x", Match_Ok, "inline dot newline", 1, 1);
      Check_Match
        ("(?-s:.)",
         "" & Character'Val (10),
         No_Match,
         "inline dot newline disabled",
         Options => (Dot_Matches_Newline => True, others => <>));
      Check_Match ("(?m:^b)", "a" & Character'Val (10) & "b", Match_Ok, "inline multiline anchor", 3, 3);
      Check_Match
        ("(?-m:^b)",
         "a" & Character'Val (10) & "b",
         No_Match,
         "inline multiline anchor disabled",
         Options => (Multiline_Anchors => True, others => <>));
      Check_Match ("(a)\1", "xaa", Match_Ok, "numbered backreference", 2, 3);
      Check_Match ("(a)\1", "xab", No_Match, "numbered backreference negative case");
      Check_Match ("(?<word>a)\k<word>", "xaa", Match_Ok, "named backreference", 2, 3);
      Check_Match ("(?i:(a)\1)", "xAa", Match_Ok, "case-insensitive backreference", 2, 3);
      Check_Match ("^(a)\1$", "aa", Match_Ok, "entire backreference", 1, 2, Entire => True);
      Check_Match ("a*+a", "aaa", No_Match, "possessive star commits");
      Check_Match ("a++a", "aaa", No_Match, "possessive plus commits");
      Check_Match ("a?+a", "a", No_Match, "possessive optional commits");
      Check_Match ("a{2,4}+a", "aaaa", No_Match, "possessive bounded repeat commits");
      Check_Match ("a*+b", "aaab", Match_Ok, "possessive star success", 1, 4);
      Check_Match ("(?>ab|a)b", "ab", No_Match, "atomic group commits first alternative");
      Check_Match ("(?:ab|a)b", "ab", Match_Ok, "non-atomic group can use shorter alternative", 1, 2);
      Check_Match ("\|", "a|b", Match_Ok, "escaped alternation literal", 2, 2);
      Check_Match ("a{2}", "baac", Match_Ok, "exact repeat", 2, 3);
      Check_Match ("a{2}", "bac", No_Match, "exact repeat too short");
      Check_Match ("a{2,4}", "baaaaac", Match_Ok, "bounded repeat longest", 2, 5);
      Check_Match ("a{2,4}?", "baaaaac", Match_Ok, "lazy bounded repeat shortest", 2, 3);
      Check_Match ("a{2,4}", "bac", No_Match, "bounded repeat under minimum");
      Check_Match ("a{2,}", "baaaaac", Match_Ok, "open repeat", 2, 6);
      Check_Match ("a{2,}?", "baaaaac", Match_Ok, "lazy open repeat shortest", 2, 3);
      Check_Match ("a{0,2}", "bbb", Match_Ok, "zero-minimum repeat", 1, 0);
      Check_Match ("\d{3}", "ab1234", Match_Ok, "escape repeat", 3, 5);
      Check_Match ("[a-c]{2}", "xxbc", Match_Ok, "class repeat", 3, 4);
      Check_Match ("(?:ab)+?", "xxababyy", Match_Ok, "lazy grouped plus", 3, 4);
      Check_Match ("^a{2,4}$", "aaa", Match_Ok, "anchored bounded repeat", 1, 3, Entire => True);
      Check_Match ("\bcat\b", "a cat b", Match_Ok, "word boundary", 3, 5);
      Check_Match ("\bcat\b", "scatter", No_Match, "word boundary negative");
      Check_Match ("\Bcat\B", "scatters", Match_Ok, "non-word boundary", 2, 4);
   end Test_Core_Matching;

   procedure Test_Character_Classes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("[a-c]+", "xxbca", Match_Ok, "class match", 3, 5);
      Check_Match ("[A-C]+", "xxbca", Match_Ok, "case-insensitive class", 3, 5);
      Check_Match ("[A-Z]+", "--abc", Match_Ok, "case-insensitive range", 3, 5);
      Check_Match
        ("[A-C]+",
         "xxbca",
         No_Match,
         "case-sensitive class",
         Options => (Case_Sensitive => True, others => <>));
      Check_Match ("[a-]+", "xxa-a", Match_Ok, "trailing hyphen class match", 3, 5);
      Check_Match ("[-a]+", "xx-a", Match_Ok, "leading hyphen class match", 3, 4);
      Check_Match ("[\-\]]+", "xx-]", Match_Ok, "escaped class literals", 3, 4);
      Check_Match ("[a-cx]+", "yyabcx", Match_Ok, "mixed range and literal", 3, 6);
      Check_Match ("[a-z&&[d-f]]+", "abcde", Match_Ok, "class intersection", 4, 5);
      Check_Match ("[a-z&&[^aeiou]]+", "ate by", Match_Ok, "class intersection with negation", 2, 2);
      Check_Match ("[a-z--[aeiou]]+", "seal", Match_Ok, "class subtraction", 1, 1);
      Check_Match ("[a-z--[^aeiou]]+", "seal", Match_Ok, "class subtraction with negation", 2, 3);
      Check_Match ("[^a]+", "aaabb", Match_Ok, "negated class", 4, 5);
      Check_Match ("[^A]+", "aaa", No_Match, "case-insensitive negated class");
      Check_Match
        ("[^A]+",
         "bbb",
         Match_Ok,
         "case-insensitive negated class accepts other letters",
         1,
         3);
      Check_Match
        ("[^A]+",
         "aaa",
         Match_Ok,
         "case-sensitive negated class accepts lowercase a",
         1,
         3,
         Options => (Case_Sensitive => True, others => <>));
      Check_Match ("\d+", "ab123", Match_Ok, "digit class", 3, 5);
      Check_Match ("\D+", "123ab", Match_Ok, "non-digit class", 4, 5);
      Check_Match ("[^\d]+", "123ab", Match_Ok, "negated digit class", 4, 5);
      Check_Match ("\w+", "--a_1", Match_Ok, "word class", 3, 5);
      Check_Match ("\W+", "ab--", Match_Ok, "non-word class", 3, 4);
      Check_Match ("\s+", "ab cd", Match_Ok, "space class", 3, 3);
      Check_Match ("\s+", "ab" & Character'Val (9) & "cd", Match_Ok, "tab class", 3, 3);
      Check_Match ("\s+", "ab" & Character'Val (10) & "cd", Match_Ok, "lf class", 3, 3);
      Check_Match ("\s+", "ab" & Character'Val (13) & "cd", Match_Ok, "cr class", 3, 3);
      Check_Match ("\S+", "  ab", Match_Ok, "non-space class", 3, 4);
      Check_Match ("\p{digit}+", "ab12cd", Match_Ok, "unicode digit property", 3, 4);
      Check_Match ("\p{digit}+", "abcd", No_Match, "unicode digit property mismatch");
      Check_Match ("\P{digit}+", "ab12cd", Match_Ok, "inverse unicode digit property", 1, 2);
      Check_Match ("\P{digit}+", "1234", No_Match, "inverse unicode digit property mismatch");
      --  A bare p or P in a class is the letter, not a property. Reading it
      --  as a property made every set holding one fail to compile, ruling out
      --  sets as ordinary as [dp] and [pq].
      Check_Match ("[dp]", "xp", Match_Ok, "literal p in a class", 2, 2);
      Check_Match ("[dp]", "xq", No_Match, "literal p in a class mismatch");
      Check_Match ("[P]", "aP", Match_Ok, "literal capital P in a class", 2, 2);
      Check_Match ("[^p]", "pa", Match_Ok, "literal p in a negated class", 2, 2);
      Check_Match
        ("[\p{digit}]",
         "a1",
         Match_Ok,
         "unicode property inside class",
         2,
         2);
      Check_Match
        ("[^\p{digit}]",
         "a1",
         Match_Ok,
         "negated unicode property inside class",
         1,
         1);
   end Test_Character_Classes;

   procedure Test_Escaped_Literals (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("\.", "x.", Match_Ok, "escaped dot", 2, 2);
      Check_Match ("\*", "x*", Match_Ok, "escaped star", 2, 2);
      Check_Match ("\+", "x+", Match_Ok, "escaped plus", 2, 2);
      Check_Match ("\?", "x?", Match_Ok, "escaped question", 2, 2);
      Check_Match ("\(", "x(", Match_Ok, "escaped open paren", 2, 2);
      Check_Match ("\)", "x)", Match_Ok, "escaped close paren", 2, 2);
      Check_Match ("\[", "x[", Match_Ok, "escaped open bracket", 2, 2);
      Check_Match ("\]", "x]", Match_Ok, "escaped close bracket", 2, 2);
      Check_Match ("\{", "x{", Match_Ok, "escaped open brace", 2, 2);
      Check_Match ("\}", "x}", Match_Ok, "escaped close brace", 2, 2);
      Check_Match ("\\", "x\", Match_Ok, "escaped backslash", 2, 2);
      Check_Match ("\^", "x^", Match_Ok, "escaped caret", 2, 2);
      Check_Match ("\$", "x$", Match_Ok, "escaped dollar", 2, 2);
   end Test_Escaped_Literals;

   procedure Test_Match_Options (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Check_Match ("abc", "ABC", Match_Ok, "case insensitive default", 1, 3);
      Check_Match
        ("abc",
         "ABC",
         No_Match,
         "case sensitive",
         Options => (Case_Sensitive => True, others => <>));
      Check_Match
        ("cat",
         "a cat b",
         Match_Ok,
         "whole word positive",
         3,
         5,
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("cat",
         "scatter",
         No_Match,
         "whole word negative",
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("^",
         "abc",
         No_Match,
         "whole word start anchor before word",
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("^",
         " abc",
         Match_Ok,
         "whole word start anchor before space",
         1,
         0,
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("cat",
         "cat_1",
         No_Match,
         "whole word rejects underscore suffix",
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("cat",
         "cat1",
         No_Match,
         "whole word rejects digit suffix",
         Options => (Whole_Word => True, others => <>));
      Check_Match
        ("cat",
         "cat",
         Match_Ok,
         "whole word entire positive",
         1,
         3,
         Options => (Whole_Word => True, others => <>),
         Entire => True);
      Check_Match
        ("cat",
         "cat1",
         No_Match,
         "whole word entire negative",
         Options => (Whole_Word => True, others => <>),
         Entire => True);
      Check_Match
        ("abc",
         "ABC",
         No_Match,
         "matches entire case sensitive",
         Options => (Case_Sensitive => True, others => <>),
         Entire => True);

      Check_Match
        ("a+",
         "aaaaa",
         Match_Limit_Exceeded,
         "abort callback",
         Options => (Abort_Callback => Abort_Immediately'Access, others => <>));
   end Test_Match_Options;

   procedure Test_Backreferences (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  A backreference must consume the whole captured span, not one unit
      --  of it. A single-character group cannot tell those two apart, so
      --  every case here captures more than one character.
      Check_Match ("(ab)\1", "abab", Match_Ok, "two-character backreference", 1, 4);
      Check_Match ("(abc)\1", "abcabc", Match_Ok, "three-character backreference", 1, 6);
      Check_Match ("(ab)\1", "abcabc", No_Match, "two-character backreference negative case");
      Check_Match ("(abc)\1", "abcabd", No_Match, "three-character backreference negative case");
      Check_Match ("x(ab)\1y", "xababy", Match_Ok, "backreference between literals", 1, 6);

      --  The span the reference consumed has to show up in the match extent.
      Check_Match ("(ab)\1", "zabab", Match_Ok, "backreference match extent", 2, 5);

      --  Non-regular patterns. "the text is some string written twice" is not
      --  a regular language, so these are the cases that need a backtracking
      --  path rather than a lock-step simulation.
      Check_Match ("^(.*)\1$", "abab", Match_Ok, "doubled string", 1, 4);
      Check_Match ("^(.*)\1$", "abac", No_Match, "doubled string negative case");
      Check_Match ("^(.+)\1+$", "ababab", Match_Ok, "repeated string", 1, 6);

      --  Several groups, referenced out of order.
      Check_Match ("(ab)(cd)\2\1", "abcdcdab", Match_Ok, "two groups reversed", 1, 8);
      Check_Match ("(ab)(cd)\2\1", "abcdabcd", No_Match, "two groups reversed negative case");

      --  A quantified group leaves its last repetition captured.
      Check_Match ("(a*)\1", "aaaa", Match_Ok, "quantified group backreference", 1, 4);

      --  An empty capture matches empty text.
      Check_Match ("(z*)\1x", "x", Match_Ok, "empty group backreference", 1, 1);

      --  Match options still apply on the backtracking path.
      Check_Match
        ("(ab)\1", "ABAB", Match_Ok, "case-insensitive multi-character backreference",
         1, 4, Options => (Case_Sensitive => False, others => <>));
      Check_Match
        ("^(ab)\1$", "abab", Match_Ok, "entire multi-character backreference",
         1, 4, Entire => True);
      Check_Match
        ("^(ab)\1$", "ababab", No_Match, "entire backreference rejects a longer text",
         Entire => True);
   end Test_Backreferences;

   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Regexp match tests");
   end Name;

   overriding procedure Register_Tests (T : in out Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Core_Matching'Access), "Core matching");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Character_Classes'Access), "Character classes");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Escaped_Literals'Access), "Escaped literal matching");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Match_Options'Access), "Match options");
      Register_Routine (T, AUnit.Test_Cases.Test_Routine'(Test_Backreferences'Access), "Backreferences");
   end Register_Tests;
end Regexp_Tests.Match_Tests;
